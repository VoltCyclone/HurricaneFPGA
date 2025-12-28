/// Command Protocol Parser
/// Parses commands from USB CDC-ACM and formats them for FPGA UART

use crate::recoil::{RecoilManager, parse_recoil_add, parse_recoil_name};
use crate::state::MouseState;
use crate::descriptor_cache::DescriptorCache;

pub struct CommandProcessor {
    buffer: [u8; 256],
    index: usize,
    pub recoil_manager: RecoilManager,
    pub mouse_state: MouseState,
    pub response_buffer: [u8; 256],
    pub response_len: usize,
}

#[derive(Debug, PartialEq)]
pub struct Command {
    pub code: u8,
    pub payload: [u8; 128],
    pub length: usize,
}

#[derive(Debug, PartialEq)]
pub enum CommandType {
    FpgaCommand(Command),  // Send to FPGA
    Response,              // Response ready in buffer
    Restart,               // Restart device
    NoOp,                  // No action needed
}

impl Command {
    /// Convert command to UART frame for FPGA
    pub fn to_uart_frame(&self) -> [u8; 256] {
        let mut frame = [0u8; 256];
        let mut idx = 0;
        
        // Frame format: [CMD:XX] [LEN:YYYY] [PAYLOAD...] [CKSUM:ZZ]\n
        
        // Command code
        frame[idx..idx+5].copy_from_slice(b"[CMD:");
        idx += 5;
        frame[idx] = hex_digit(self.code >> 4);
        frame[idx+1] = hex_digit(self.code & 0x0F);
        idx += 2;
        frame[idx..idx+2].copy_from_slice(b"] ");
        idx += 2;
        
        // Length
        frame[idx..idx+5].copy_from_slice(b"[LEN:");
        idx += 5;
        frame[idx] = hex_digit((self.length as u8) >> 12);
        frame[idx+1] = hex_digit(((self.length as u8) >> 8) & 0x0F);
        frame[idx+2] = hex_digit(((self.length as u8) >> 4) & 0x0F);
        frame[idx+3] = hex_digit((self.length as u8) & 0x0F);
        idx += 4;
        frame[idx..idx+2].copy_from_slice(b"] ");
        idx += 2;
        
        // Payload (raw binary)
        for i in 0..self.length {
            frame[idx] = self.payload[i];
            idx += 1;
        }
        frame[idx] = b' ';
        idx += 1;
        
        // Checksum (simple sum of all bytes)
        let mut cksum = self.code;
        for i in 0..self.length {
            cksum = cksum.wrapping_add(self.payload[i]);
        }
        frame[idx..idx+7].copy_from_slice(b"[CKSUM:");
        idx += 7;
        frame[idx] = hex_digit(cksum >> 4);
        frame[idx+1] = hex_digit(cksum & 0x0F);
        idx += 2;
        frame[idx..idx+2].copy_from_slice(b"]\n");
        idx += 2;
        
        frame
    }
}

fn parse_int(data: &[u8]) -> Option<i16> {
    // Parse signed integer from ASCII bytes
    let mut value: i16 = 0;
    let mut negative = false;
    let mut idx = 0;
    
    // Skip whitespace
    while idx < data.len() && data[idx] == b' ' {
        idx += 1;
    }
    
    // Check for negative sign
    if idx < data.len() && data[idx] == b'-' {
        negative = true;
        idx += 1;
    }
    
    // Parse digits
    while idx < data.len() && data[idx] >= b'0' && data[idx] <= b'9' {
        value = value * 10 + (data[idx] - b'0') as i16;
        idx += 1;
    }
    
    if negative {
        value = -value;
    }
    
    Some(value)
}

fn format_i16(value: i16, buf: &mut [u8]) -> usize {
    // Format signed i16 as ASCII
    let mut idx = 0;
    let mut val = value;
    
    if val < 0 {
        buf[idx] = b'-';
        idx += 1;
        val = -val;
    }
    
    // Convert to ASCII digits (reverse order first)
    let mut temp = [0u8; 6];
    let mut temp_idx = 0;
    
    if val == 0 {
        temp[0] = b'0';
        temp_idx = 1;
    } else {
        while val > 0 {
            temp[temp_idx] = b'0' + (val % 10) as u8;
            val /= 10;
            temp_idx += 1;
        }
    }
    
    // Reverse into output buffer
    for i in (0..temp_idx).rev() {
        buf[idx] = temp[i];
        idx += 1;
    }
    
    idx
}

impl CommandProcessor {
    pub fn new() -> Self {
        CommandProcessor {
            buffer: [0u8; 256],
            index: 0,
            recoil_manager: RecoilManager::new(),
            mouse_state: MouseState::new(),
            response_buffer: [0u8; 256],
            response_len: 0,
        }
    }
    
    /// Parse incoming data from USB and extract commands
    pub fn parse(&mut self, data: &[u8], descriptor_cache: &mut DescriptorCache) -> CommandType {
        // Parse nozen command format: "nozen.move(x,y)\n", "nozen.left(1)\n", etc.
        
        for &byte in data {
            if byte == b'\n' || byte == b'\r' {
                // Process line - copy to avoid borrow checker issues
                let mut line_buf = [0u8; 256];
                let line_len = self.index;
                line_buf[..line_len].copy_from_slice(&self.buffer[..line_len]);
                self.index = 0;
                
                return self.parse_line(&line_buf[..line_len], descriptor_cache);
            } else if self.index < self.buffer.len() {
                self.buffer[self.index] = byte;
                self.index += 1;
            }
        }
        
        CommandType::NoOp
    }
    
    /// Get response data if available
    pub fn get_response(&mut self) -> Option<&[u8]> {
        if self.response_len > 0 {
            let len = self.response_len;
            self.response_len = 0;
            Some(&self.response_buffer[..len])
        } else {
            None
        }
    }
    
    fn parse_line(&mut self, line: &[u8], descriptor_cache: &mut DescriptorCache) -> CommandType {
        // Parse nozen command format
        // Examples:
        //   "nozen.move(10,-5)"
        //   "nozen.left(1)"
        //   "nozen.moveto(100,200)"
        //   "nozen.wheel(5)"
        //   "nozen.recoil.add(name){x,y,delay,...}"
        //   "nozen.getpos()"
        //   "nozen.print(message)"
        //   "nozen.restart"
        //
        // FPGA auto-forwarding (no "nozen." prefix):
        //   "[DESC:addr:iface]{hex_data}" - Auto-forwarded HID descriptor
        //
        // Debug commands:
        //   "nozen.descriptor.get(addr,iface)"
        //   "nozen.descriptor.stats"
        
        // Check for FPGA-forwarded descriptor (starts with [DESC:)
        if line.starts_with(b"[DESC:") {
            return self.handle_fpga_descriptor(line, descriptor_cache);
        }
        
        if line.starts_with(b"nozen.move(") {
            // Parse: nozen.move(x,y)
            self.parse_mouse_move(line)
        } else if line.starts_with(b"nozen.moveto(") {
            // Parse: nozen.moveto(x,y)
            self.parse_mouse_moveto(line)
        } else if line.starts_with(b"nozen.left(") {
            // Parse: nozen.left(0) or nozen.left(1)
            self.parse_button_command(line, 0x01, b"nozen.left(")
        } else if line.starts_with(b"nozen.right(") {
            // Parse: nozen.right(0) or nozen.right(1)
            self.parse_button_command(line, 0x02, b"nozen.right(")
        } else if line.starts_with(b"nozen.middle(") {
            // Parse: nozen.middle(0) or nozen.middle(1)
            self.parse_button_command(line, 0x04, b"nozen.middle(")
        } else if line.starts_with(b"nozen.side1(") {
            // Parse: nozen.side1(0) or nozen.side1(1)
            self.parse_button_command(line, 0x08, b"nozen.side1(")
        } else if line.starts_with(b"nozen.side2(") {
            // Parse: nozen.side2(0) or nozen.side2(1)
            self.parse_button_command(line, 0x10, b"nozen.side2(")
        } else if line.starts_with(b"nozen.wheel(") {
            // Parse: nozen.wheel(amount)
            self.parse_wheel_command(line)
        } else if line.starts_with(b"nozen.getpos") {
            // Get current mouse position
            self.handle_getpos()
        } else if line.starts_with(b"nozen.recoil.add(") {
            // Add recoil pattern
            self.handle_recoil_add(line)
        } else if line.starts_with(b"nozen.recoil.delete(") {
            // Delete recoil pattern
            self.handle_recoil_delete(line)
        } else if line.starts_with(b"nozen.recoil.list") {
            // List all recoil patterns
            self.handle_recoil_list()
        } else if line.starts_with(b"nozen.recoil.get(") {
            // Get specific recoil pattern
            self.handle_recoil_get(line)
        } else if line.starts_with(b"nozen.recoil.names") {
            // List recoil pattern names
            self.handle_recoil_names()
        } else if line.starts_with(b"nozen.print(") {
            // Print message
            self.handle_print(line)
        } else if line.starts_with(b"nozen.descriptor.get(") {
            // Get descriptor from cache (debug only)
            self.handle_descriptor_get(line, descriptor_cache)
        } else if line.starts_with(b"nozen.descriptor.stats") {
            // Get descriptor cache statistics (debug only)
            self.handle_descriptor_stats(descriptor_cache)
        } else if line.starts_with(b"nozen.restart") {
            // Restart device
            CommandType::Restart
        } else {
            CommandType::NoOp
        }
    }
    
    fn parse_mouse_move(&mut self, line: &[u8]) -> CommandType {
        // Parse "nozen.move(x,y)"
        let args_start = b"nozen.move(".len();
        let args = &line[args_start..];
        
        // Find the closing paren
        let paren_pos = match args.iter().position(|&c| c == b')') {
            Some(p) => p,
            None => return CommandType::NoOp,
        };
        let args = &args[..paren_pos];
        
        // Parse x,y
        let comma_pos = match args.iter().position(|&c| c == b',') {
            Some(p) => p,
            None => return CommandType::NoOp,
        };
        let x_str = &args[..comma_pos];
        let y_str = &args[comma_pos+1..];
        
        let x = match parse_int(x_str) {
            Some(v) => v,
            None => return CommandType::NoOp,
        };
        let y = match parse_int(y_str) {
            Some(v) => v,
            None => return CommandType::NoOp,
        };
        
        // Update mouse state
        self.mouse_state.update_relative(x, y);
        
        // Create INJECT_MOUSE command: [buttons, dx, dy, wheel, pan]
        let mut payload = [0u8; 128];
        payload[0] = 0x00;  // No buttons
        payload[1] = (x & 0xFF) as u8;  // dx (signed as unsigned)
        payload[2] = (y & 0xFF) as u8;  // dy
        payload[3] = 0x00;  // wheel
        payload[4] = 0x00;  // pan
        
        CommandType::FpgaCommand(Command {
            code: 0x11,  // INJECT_MOUSE
            payload,
            length: 5,
        })
    }
    
    fn parse_mouse_moveto(&mut self, line: &[u8]) -> CommandType {
        // Parse "nozen.moveto(x,y)"
        let args_start = b"nozen.moveto(".len();
        let args = &line[args_start..];
        
        let paren_pos = match args.iter().position(|&c| c == b')') {
            Some(p) => p,
            None => return CommandType::NoOp,
        };
        let args = &args[..paren_pos];
        
        let comma_pos = match args.iter().position(|&c| c == b',') {
            Some(p) => p,
            None => return CommandType::NoOp,
        };
        let x_str = &args[..comma_pos];
        let y_str = &args[comma_pos+1..];
        
        let target_x = match parse_int(x_str) {
            Some(v) => v,
            None => return CommandType::NoOp,
        };
        let target_y = match parse_int(y_str) {
            Some(v) => v,
            None => return CommandType::NoOp,
        };
        
        // Calculate delta from current position
        let (dx, dy) = self.mouse_state.delta_to(target_x, target_y);
        
        // Update state to new position
        self.mouse_state.set_position(target_x, target_y);
        
        // Send relative movement to FPGA
        let mut payload = [0u8; 128];
        payload[0] = 0x00;
        payload[1] = (dx & 0xFF) as u8;
        payload[2] = (dy & 0xFF) as u8;
        payload[3] = 0x00;
        payload[4] = 0x00;
        
        CommandType::FpgaCommand(Command {
            code: 0x11,  // INJECT_MOUSE
            payload,
            length: 5,
        })
    }
    
    fn parse_button_command(&self, line: &[u8], button_mask: u8, prefix: &[u8]) -> CommandType {
        // Parse "nozen.left(0)" or "nozen.left(1)"
        let args_start = prefix.len();
        let args = &line[args_start..];
        
        let _paren_pos = match args.iter().position(|&c| c == b')') {
            Some(p) => p,
            None => return CommandType::NoOp,
        };
        let state = args[0];
        
        let buttons = if state == b'1' { button_mask } else { 0x00 };
        
        // Create INJECT_MOUSE command
        let mut payload = [0u8; 128];
        payload[0] = buttons;
        payload[1] = 0x00;  // No movement
        payload[2] = 0x00;
        payload[3] = 0x00;
        payload[4] = 0x00;
        
        CommandType::FpgaCommand(Command {
            code: 0x11,  // INJECT_MOUSE
            payload,
            length: 5,
        })
    }
    
    fn parse_wheel_command(&self, line: &[u8]) -> CommandType {
        // Parse "nozen.wheel(amount)"
        let args_start = b"nozen.wheel(".len();
        let args = &line[args_start..];
        
        let paren_pos = match args.iter().position(|&c| c == b')') {
            Some(p) => p,
            None => return CommandType::NoOp,
        };
        let amount_str = &args[..paren_pos];
        
        let amount = match parse_int(amount_str) {
            Some(v) => v,
            None => return CommandType::NoOp,
        };
        
        // Create INJECT_MOUSE command with wheel movement
        let mut payload = [0u8; 128];
        payload[0] = 0x00;  // No buttons
        payload[1] = 0x00;  // No x movement
        payload[2] = 0x00;  // No y movement
        payload[3] = (amount & 0xFF) as u8;  // Wheel
        payload[4] = 0x00;  // Pan
        
        CommandType::FpgaCommand(Command {
            code: 0x11,  // INJECT_MOUSE
            payload,
            length: 5,
        })
    }
    
    // Handler functions for new commands
    
    fn handle_getpos(&mut self) -> CommandType {
        let (x, y) = self.mouse_state.position();
        // Format: "km.pos(x,y)\n"
        let mut resp = [0u8; 256];
        let mut idx = 0;
        
        resp[idx..idx+7].copy_from_slice(b"km.pos(");
        idx += 7;
        
        // Format x
        idx += format_i16(x, &mut resp[idx..]);
        resp[idx] = b',';
        idx += 1;
        
        // Format y
        idx += format_i16(y, &mut resp[idx..]);
        resp[idx] = b')';
        idx += 1;
        resp[idx] = b'\n';
        idx += 1;
        
        self.response_buffer[..idx].copy_from_slice(&resp[..idx]);
        self.response_len = idx;
        
        CommandType::Response
    }
    
    fn handle_recoil_add(&mut self, line: &[u8]) -> CommandType {
        match parse_recoil_add(line) {
            Some((name, steps)) => {
                let name_str = core::str::from_utf8(name).unwrap_or("???");
                let steps_slice: &[i16] = &steps;
                
                match self.recoil_manager.add_pattern(name_str, steps_slice) {
                    Ok(_) => {
                        let msg = b"Recoil pattern added\n";
                        self.response_buffer[..msg.len()].copy_from_slice(msg);
                        self.response_len = msg.len();
                        CommandType::Response
                    }
                    Err(e) => {
                        let mut resp = [0u8; 256];
                        let err_msg = b"Error: ";
                        resp[..err_msg.len()].copy_from_slice(err_msg);
                        let e_bytes = e.as_bytes();
                        let e_len = e_bytes.len().min(240);
                        resp[err_msg.len()..err_msg.len()+e_len].copy_from_slice(&e_bytes[..e_len]);
                        resp[err_msg.len()+e_len] = b'\n';
                        let total_len = err_msg.len()+e_len+1;
                        self.response_buffer[..total_len].copy_from_slice(&resp[..total_len]);
                        self.response_len = total_len;
                        CommandType::Response
                    }
                }
            }
            None => {
                let msg = b"Invalid recoil.add format\n";
                self.response_buffer[..msg.len()].copy_from_slice(msg);
                self.response_len = msg.len();
                CommandType::Response
            }
        }
    }
    
    fn handle_recoil_delete(&mut self, line: &[u8]) -> CommandType {
        match parse_recoil_name(line, b"nozen.recoil.delete") {
            Some(name) => {
                let name_str = core::str::from_utf8(name).unwrap_or("???");
                if self.recoil_manager.delete_pattern(name_str) {
                    let msg = b"Pattern deleted\n";
                    self.response_buffer[..msg.len()].copy_from_slice(msg);
                    self.response_len = msg.len();
                } else {
                    let msg = b"Pattern not found\n";
                    self.response_buffer[..msg.len()].copy_from_slice(msg);
                    self.response_len = msg.len();
                }
                CommandType::Response
            }
            None => {
                let msg = b"Invalid delete format\n";
                self.response_buffer[..msg.len()].copy_from_slice(msg);
                self.response_len = msg.len();
                CommandType::Response
            }
        }
    }
    
    fn handle_recoil_list(&mut self) -> CommandType {
        let mut resp = [0u8; 256];
        let mut idx = 0;
        
        let header = b"Stored patterns:\n";
        resp[idx..idx+header.len()].copy_from_slice(header);
        idx += header.len();
        
        for pattern in self.recoil_manager.list_patterns() {
            if idx + 64 > resp.len() { break; }
            
            // Write name
            let name_bytes = pattern.name.as_bytes();
            let name_len = name_bytes.len().min(32);
            resp[idx..idx+name_len].copy_from_slice(&name_bytes[..name_len]);
            idx += name_len;
            
            resp[idx..idx+3].copy_from_slice(b": {");
            idx += 3;
            
            // Write first few steps
            for (i, &step) in pattern.steps.iter().take(12).enumerate() {
                if idx + 10 > resp.len() { break; }
                if i > 0 {
                    resp[idx] = b',';
                    idx += 1;
                }
                idx += format_i16(step, &mut resp[idx..]);
            }
            
            if pattern.steps.len() > 12 {
                resp[idx..idx+4].copy_from_slice(b",...");
                idx += 4;
            }
            
            resp[idx..idx+2].copy_from_slice(b"}\n");
            idx += 2;
        }
        
        self.response_buffer[..idx].copy_from_slice(&resp[..idx]);
        self.response_len = idx;
        
        CommandType::Response
    }
    
    fn handle_recoil_get(&mut self, line: &[u8]) -> CommandType {
        match parse_recoil_name(line, b"nozen.recoil.get") {
            Some(name) => {
                let name_str = core::str::from_utf8(name).unwrap_or("???");
                match self.recoil_manager.get_pattern(name_str) {
                    Some(pattern) => {
                        let mut resp = [0u8; 256];
                        let mut idx = 0;
                        
                        // Write pattern name and data
                        let name_bytes = pattern.name.as_bytes();
                        let name_len = name_bytes.len().min(32);
                        resp[idx..idx+name_len].copy_from_slice(&name_bytes[..name_len]);
                        idx += name_len;
                        
                        resp[idx..idx+3].copy_from_slice(b": {");
                        idx += 3;
                        
                        for (i, &step) in pattern.steps.iter().enumerate() {
                            if idx + 10 > resp.len() { break; }
                            if i > 0 {
                                resp[idx] = b',';
                                idx += 1;
                            }
                            idx += format_i16(step, &mut resp[idx..]);
                        }
                        
                        resp[idx..idx+2].copy_from_slice(b"}\n");
                        idx += 2;
                        
                        self.response_buffer[..idx].copy_from_slice(&resp[..idx]);
                        self.response_len = idx;
                        
                        CommandType::Response
                    }
                    None => {
                        let msg = b"Pattern not found\n";
                        self.response_buffer[..msg.len()].copy_from_slice(msg);
                        self.response_len = msg.len();
                        CommandType::Response
                    }
                }
            }
            None => {
                let msg = b"Invalid get format\n";
                self.response_buffer[..msg.len()].copy_from_slice(msg);
                self.response_len = msg.len();
                CommandType::Response
            }
        }
    }
    
    fn handle_recoil_names(&mut self) -> CommandType {
        let mut resp = [0u8; 256];
        let mut idx = 0;
        
        let header = b"Available patterns:\n";
        resp[idx..idx+header.len()].copy_from_slice(header);
        idx += header.len();
        
        for name in self.recoil_manager.list_names() {
            if idx + name.len() + 3 > resp.len() { break; }
            
            resp[idx..idx+2].copy_from_slice(b"- ");
            idx += 2;
            
            let name_bytes = name.as_bytes();
            resp[idx..idx+name_bytes.len()].copy_from_slice(name_bytes);
            idx += name_bytes.len();
            
            resp[idx] = b'\n';
            idx += 1;
        }
        
        self.response_buffer[..idx].copy_from_slice(&resp[..idx]);
        self.response_len = idx;
        
        CommandType::Response
    }
    
    fn handle_print(&mut self, line: &[u8]) -> CommandType {
        // Parse "nozen.print(message)"
        let args_start = b"nozen.print(".len();
        if line.len() <= args_start {
            return CommandType::NoOp;
        }
        
        let args = &line[args_start..];
        let paren_pos = match args.iter().position(|&c| c == b')') {
            Some(p) => p,
            None => return CommandType::NoOp,
        };
        
        let message = &args[..paren_pos];
        let msg_len = message.len().min(254);
        
        self.response_buffer[..msg_len].copy_from_slice(&message[..msg_len]);
        self.response_buffer[msg_len] = b'\n';
        self.response_len = msg_len + 1;
        
        CommandType::Response
    }

    /// Handle FPGA-forwarded descriptor
    /// Format: [DESC:addr:iface]{hex_data}
    /// This is automatically sent by FPGA when it detects GET_DESCRIPTOR for HID Report
    fn handle_fpga_descriptor(&mut self, line: &[u8], descriptor_cache: &mut DescriptorCache) -> CommandType {
        use core::fmt::Write;
        
        // Parse: [DESC:AA:II]{hex_data}
        let mut idx = 6;  // Skip "[DESC:"
        
        // Parse address (hex)
        if idx + 2 > line.len() {
            return CommandType::NoOp;
        }
        let addr_high = hex_to_nibble(line[idx]).unwrap_or(0);
        let addr_low = hex_to_nibble(line[idx + 1]).unwrap_or(0);
        let addr = (addr_high << 4) | addr_low;
        idx += 2;
        
        // Skip ':'
        if idx >= line.len() || line[idx] != b':' {
            return CommandType::NoOp;
        }
        idx += 1;
        
        // Parse interface (hex)
        if idx >= line.len() {
            return CommandType::NoOp;
        }
        let iface = hex_to_nibble(line[idx]).unwrap_or(0);
        idx += 1;
        
        // Find hex data in braces
        while idx < line.len() && line[idx] != b'{' {
            idx += 1;
        }
        idx += 1;
        
        let start = idx;
        while idx < line.len() && line[idx] != b'}' {
            idx += 1;
        }
        
        // Parse hex data
        let hex_data = &line[start..idx];
        let mut descriptor_bytes = [0u8; 1024];
        let mut desc_len = 0;
        
        let mut i = 0;
        while i < hex_data.len() && desc_len < 1024 {
            // Skip whitespace/commas
            while i < hex_data.len() && (hex_data[i] == b' ' || hex_data[i] == b',') {
                i += 1;
            }
            
            if i + 1 < hex_data.len() {
                let high = hex_to_nibble(hex_data[i]);
                let low = hex_to_nibble(hex_data[i + 1]);
                
                if high.is_some() && low.is_some() {
                    descriptor_bytes[desc_len] = (high.unwrap() << 4) | low.unwrap();
                    desc_len += 1;
                }
                i += 2;
            } else {
                break;
            }
        }
        
        // Auto-parse and cache
        match descriptor_cache.add(addr, iface, &descriptor_bytes[..desc_len]) {
            Ok(()) => {
                // Get the cached descriptor
                let desc = descriptor_cache.get(addr, iface).unwrap();
                
                // Log successful auto-parse
                self.response_len = 0;
                let mut msg = heapless::String::<128>::new();
                let _ = write!(msg, "[AUTO] HID descriptor: dev={} if={} ", addr, iface);
                write_str(&mut self.response_buffer[..], msg.as_bytes(), &mut self.response_len);
                
                if desc.is_keyboard {
                    write_str(&mut self.response_buffer[..], b"[Keyboard] ", &mut self.response_len);
                }
                if desc.is_mouse {
                    write_str(&mut self.response_buffer[..], b"[Mouse] ", &mut self.response_len);
                }
                if desc.is_gamepad {
                    write_str(&mut self.response_buffer[..], b"[Gamepad] ", &mut self.response_len);
                }
                
                let _ = write!(msg, "{}B\n", desc_len);
                write_str(&mut self.response_buffer[..], msg.as_bytes(), &mut self.response_len);
                
                CommandType::Response
            }
            Err(_) => {
                // Parsing failed - still log it
                self.response_len = 0;
                let mut msg = heapless::String::<128>::new();
                let _ = write!(msg, "[WARN] Failed to parse descriptor: dev={} if={}\n", addr, iface);
                write_str(&mut self.response_buffer[..], msg.as_bytes(), &mut self.response_len);
                CommandType::Response
            }
        }
    }
    
    /// Handle descriptor.add command - DEPRECATED, use FPGA auto-forward instead
    /// Kept for manual testing only
    fn handle_descriptor_add(&mut self, line: &[u8], descriptor_cache: &mut DescriptorCache) -> CommandType {
        use core::fmt::Write;
        
        // Parse address and interface
        let mut idx = b"nozen.descriptor.add(".len();
        
        // Parse address
        let addr = match parse_u8_from_slice(&line[idx..]) {
            Some(v) => v,
            None => {
                self.response_len = 0;
                write_str(&mut self.response_buffer[..], b"[ERROR] Invalid address\n", &mut self.response_len);
                return CommandType::Response;
            }
        };
        
        // Skip to comma
        while idx < line.len() && line[idx] != b',' {
            idx += 1;
        }
        idx += 1;
        
        // Parse interface
        let iface = match parse_u8_from_slice(&line[idx..]) {
            Some(v) => v,
            None => {
                self.response_len = 0;
                write_str(&mut self.response_buffer[..], b"[ERROR] Invalid interface\n", &mut self.response_len);
                return CommandType::Response;
            }
        };
        
        // Find hex data in braces
        while idx < line.len() && line[idx] != b'{' {
            idx += 1;
        }
        idx += 1;
        
        let start = idx;
        while idx < line.len() && line[idx] != b'}' {
            idx += 1;
        }
        
        // Parse hex data
        let hex_data = &line[start..idx];
        let mut descriptor_bytes = [0u8; 1024];
        let mut desc_len = 0;
        
        let mut i = 0;
        while i < hex_data.len() && desc_len < 1024 {
            // Skip whitespace
            while i < hex_data.len() && (hex_data[i] == b' ' || hex_data[i] == b',') {
                i += 1;
            }
            
            if i + 1 < hex_data.len() {
                let high = hex_to_nibble(hex_data[i]);
                let low = hex_to_nibble(hex_data[i + 1]);
                
                if high.is_none() || low.is_none() {
                    self.response_len = 0;
                    write_str(&mut self.response_buffer[..], b"[ERROR] Invalid hex data\n", &mut self.response_len);
                    return CommandType::Response;
                }
                
                descriptor_bytes[desc_len] = (high.unwrap() << 4) | low.unwrap();
                desc_len += 1;
                i += 2;
            } else {
                break;
            }
        }
        
        // Add to cache
        match descriptor_cache.add(addr, iface, &descriptor_bytes[..desc_len]) {
            Ok(()) => {
                // Get the cached descriptor
                let desc = descriptor_cache.get(addr, iface).unwrap();
                
                self.response_len = 0;
                let mut msg = heapless::String::<128>::new();
                let _ = write!(msg, "[OK] Descriptor cached: addr={} iface={} type=", addr, iface);
                write_str(&mut self.response_buffer[..], msg.as_bytes(), &mut self.response_len);
                
                if desc.is_keyboard {
                    write_str(&mut self.response_buffer[..], b"Keyboard ", &mut self.response_len);
                }
                if desc.is_mouse {
                    write_str(&mut self.response_buffer[..], b"Mouse ", &mut self.response_len);
                }
                if desc.is_gamepad {
                    write_str(&mut self.response_buffer[..], b"Gamepad ", &mut self.response_len);
                }
                
                write_str(&mut self.response_buffer[..], b"\n", &mut self.response_len);
                CommandType::Response
            }
            Err(_) => {
                self.response_len = 0;
                write_str(&mut self.response_buffer[..], b"[ERROR] Failed to parse descriptor\n", &mut self.response_len);
                CommandType::Response
            }
        }
    }
    
    /// Handle descriptor.get command
    /// Format: nozen.descriptor.get(addr,iface)
    fn handle_descriptor_get(&mut self, line: &[u8], descriptor_cache: &mut DescriptorCache) -> CommandType {
        use core::fmt::Write;
        
        // Parse address and interface
        let mut idx = b"nozen.descriptor.get(".len();
        
        let addr = match parse_u8_from_slice(&line[idx..]) {
            Some(v) => v,
            None => {
                self.response_len = 0;
                write_str(&mut self.response_buffer[..], b"[ERROR] Invalid address\n", &mut self.response_len);
                return CommandType::Response;
            }
        };
        
        while idx < line.len() && line[idx] != b',' {
            idx += 1;
        }
        idx += 1;
        
        let iface = match parse_u8_from_slice(&line[idx..]) {
            Some(v) => v,
            None => {
                self.response_len = 0;
                write_str(&mut self.response_buffer[..], b"[ERROR] Invalid interface\n", &mut self.response_len);
                return CommandType::Response;
            }
        };
        
        // Get from cache
        if let Some(desc) = descriptor_cache.get(addr, iface) {
            self.response_len = 0;
            let mut msg = heapless::String::<128>::new();
            let _ = write!(msg, "[Descriptor] addr={} iface={}\n", addr, iface);
            write_str(&mut self.response_buffer[..], msg.as_bytes(), &mut self.response_len);
            
            let _ = write!(msg, "  Type: ");
            if desc.is_keyboard { let _ = write!(msg, "Keyboard "); }
            if desc.is_mouse { let _ = write!(msg, "Mouse "); }
            if desc.is_gamepad { let _ = write!(msg, "Gamepad "); }
            let _ = write!(msg, "\n");
            write_str(&mut self.response_buffer[..], msg.as_bytes(), &mut self.response_len);
            
            let _ = write!(msg, "  Fields: {}\n", desc.fields.len());
            write_str(&mut self.response_buffer[..], msg.as_bytes(), &mut self.response_len);
            
            CommandType::Response
        } else {
            self.response_len = 0;
            write_str(&mut self.response_buffer[..], b"[ERROR] Descriptor not found\n", &mut self.response_len);
            CommandType::Response
        }
    }
    
    /// Handle descriptor.stats command
    fn handle_descriptor_stats(&mut self, descriptor_cache: &DescriptorCache) -> CommandType {
        let stats = descriptor_cache.get_stats();
        
        self.response_len = 0;
        let stats_str = stats.format();
        write_str(&mut self.response_buffer[..], stats_str.as_bytes(), &mut self.response_len);
        write_str(&mut self.response_buffer[..], b"\n", &mut self.response_len);
        
        CommandType::Response
    }
}

/// Parse u8 from byte slice
fn parse_u8_from_slice(data: &[u8]) -> Option<u8> {
    let mut value = 0u8;
    let mut idx = 0;
    
    while idx < data.len() && data[idx] >= b'0' && data[idx] <= b'9' {
        value = value.wrapping_mul(10).wrapping_add(data[idx] - b'0');
        idx += 1;
    }
    
    if idx > 0 {
        Some(value)
    } else {
        None
    }
}

/// Convert hex character to nibble
fn hex_to_nibble(c: u8) -> Option<u8> {
    match c {
        b'0'..=b'9' => Some(c - b'0'),
        b'a'..=b'f' => Some(c - b'a' + 10),
        b'A'..=b'F' => Some(c - b'A' + 10),
        _ => None,
    }
}

/// Write string to buffer
fn write_str(buf: &mut [u8], data: &[u8], len: &mut usize) {
    let copy_len = data.len().min(buf.len() - *len);
    buf[*len..*len + copy_len].copy_from_slice(&data[..copy_len]);
    *len += copy_len;
}


fn hex_digit(nibble: u8) -> u8 {
    match nibble & 0x0F {
        0..=9 => b'0' + nibble,
        10..=15 => b'A' + (nibble - 10),
        _ => b'?',
    }
}
