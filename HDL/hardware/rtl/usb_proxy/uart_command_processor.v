///////////////////////////////////////////////////////////////////////////////
// File: uart_command_processor.v
// Description: UART Command Protocol Parser and Processor
//
// This module parses commands from the SAMD51 via UART0 and executes them.
// Commands use a simple frame format:
//   [CMD:XX] [LEN:YYYY] [PAYLOAD...] [CKSUM:ZZ]\n
//
// Supported Commands:
//   0x10: INJECT_KBD  - Inject keyboard HID report (8 bytes)
//   0x11: INJECT_MOUSE - Inject mouse HID report (5 bytes)
//   0x20: SET_FILTER  - Set report filter mask (4 bytes)
//   0x21: SET_MODE    - Change proxy mode (1 byte)
//
// Target: Lattice ECP5 on Cynthion device
///////////////////////////////////////////////////////////////////////////////

module uart_command_processor (
    // Clock and Reset
    input  wire        clk,                 // System clock
    input  wire        rst_n,               // Active low reset
    
    // UART RX Interface (from uart_interface)
    input  wire [7:0]  uart_rx_data,        // UART received data
    input  wire        uart_rx_valid,       // UART data valid
    output reg         uart_rx_ready,       // Ready to accept data
    
    // UART TX Interface (for responses)
    output reg  [7:0]  uart_tx_data,        // UART transmit data
    output reg         uart_tx_valid,       // UART data valid
    input  wire        uart_tx_ready,       // Ready to accept data
    
    // Keyboard Injection Interface
    output reg  [63:0] inject_kbd_report,   // 8-byte keyboard report
    output reg         inject_kbd_valid,    // Injection request
    input  wire        inject_kbd_ack,      // Injection acknowledged
    
    // Mouse Injection Interface
    output reg  [39:0] inject_mouse_report, // 5-byte mouse report
    output reg         inject_mouse_valid,  // Injection request
    input  wire        inject_mouse_ack,    // Injection acknowledged
    
    // Control Outputs
    output reg  [31:0] filter_mask,         // Report filter mask
    output reg         mode_proxy,          // Proxy mode enable
    output reg         mode_host            // Host mode enable
);

    // Command codes
    localparam CMD_INJECT_KBD   = 8'h10;
    localparam CMD_INJECT_MOUSE = 8'h11;
    localparam CMD_SET_FILTER   = 8'h20;
    localparam CMD_SET_MODE     = 8'h21;
    
    // Parser states
    localparam STATE_IDLE        = 4'd0;
    localparam STATE_WAIT_CMD    = 4'd1;
    localparam STATE_WAIT_LEN    = 4'd2;
    localparam STATE_READ_PAYLOAD = 4'd3;
    localparam STATE_WAIT_CKSUM  = 4'd4;
    localparam STATE_EXECUTE     = 4'd5;
    localparam STATE_SEND_ACK    = 4'd6;
    localparam STATE_SEND_NAK    = 4'd7;
    
    // Parser state machine
    reg [3:0]  parse_state;
    reg [7:0]  cmd_code;
    reg [15:0] cmd_length;
    reg [7:0]  cmd_payload [127:0];  // Max 128 bytes payload
    reg [7:0]  payload_index;
    reg [7:0]  checksum_calc;
    reg [7:0]  checksum_recv;
    
    // Bracket matching
    reg        in_frame;
    reg [7:0]  prev_char;
    
    // Command execution flags
    reg        cmd_valid;
    reg        cmd_error;
    
    // =======================================================================
    // Command Parser State Machine
    // =======================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            parse_state <= STATE_IDLE;
            uart_rx_ready <= 1'b1;
            cmd_code <= 8'd0;
            cmd_length <= 16'd0;
            payload_index <= 8'd0;
            checksum_calc <= 8'd0;
            checksum_recv <= 8'd0;
            in_frame <= 1'b0;
            prev_char <= 8'd0;
            cmd_valid <= 1'b0;
            cmd_error <= 1'b0;
        end else begin
            // Default: ready to accept UART data
            uart_rx_ready <= 1'b1;
            cmd_valid <= 1'b0;
            cmd_error <= 1'b0;
            
            case (parse_state)
                STATE_IDLE: begin
                    // Wait for command frame start: "["
                    if (uart_rx_valid && uart_rx_data == 8'h5B) begin  // '['
                        in_frame <= 1'b1;
                        checksum_calc <= 8'd0;
                        parse_state <= STATE_WAIT_CMD;
                    end
                    prev_char <= uart_rx_data;
                end
                
                STATE_WAIT_CMD: begin
                    // Look for "CMD:XX]" pattern
                    if (uart_rx_valid) begin
                        // Simple parsing: if we see "1" followed by hex digit, it's likely 0x1X command
                        // For now, just grab the last two hex chars before ']'
                        if (uart_rx_data == 8'h5D) begin  // ']'
                            // Previous char should be the command code in hex
                            cmd_code <= prev_char;
                            checksum_calc <= checksum_calc + prev_char;
                            parse_state <= STATE_WAIT_LEN;
                        end else if (uart_rx_data >= 8'h30 && uart_rx_data <= 8'h39) begin
                            // Digit '0'-'9'
                            cmd_code <= {cmd_code[3:0], (uart_rx_data - 8'h30)};
                        end else if (uart_rx_data >= 8'h41 && uart_rx_data <= 8'h46) begin
                            // Hex 'A'-'F'
                            cmd_code <= {cmd_code[3:0], (uart_rx_data - 8'h37)};
                        end else if (uart_rx_data >= 8'h61 && uart_rx_data <= 8'h66) begin
                            // Hex 'a'-'f'
                            cmd_code <= {cmd_code[3:0], (uart_rx_data - 8'h57)};
                        end
                        prev_char <= uart_rx_data;
                    end
                end
                
                STATE_WAIT_LEN: begin
                    // Look for "[LEN:YYYY]" pattern
                    if (uart_rx_valid) begin
                        if (uart_rx_data == 8'h5D) begin  // ']'
                            checksum_calc <= checksum_calc + cmd_length[7:0] + cmd_length[15:8];
                            payload_index <= 8'd0;
                            if (cmd_length > 0)
                                parse_state <= STATE_READ_PAYLOAD;
                            else
                                parse_state <= STATE_WAIT_CKSUM;
                        end else if (uart_rx_data >= 8'h30 && uart_rx_data <= 8'h39) begin
                            cmd_length <= {cmd_length[11:0], (uart_rx_data - 8'h30)};
                        end else if (uart_rx_data >= 8'h41 && uart_rx_data <= 8'h46) begin
                            cmd_length <= {cmd_length[11:0], (uart_rx_data - 8'h37)};
                        end else if (uart_rx_data >= 8'h61 && uart_rx_data <= 8'h66) begin
                            cmd_length <= {cmd_length[11:0], (uart_rx_data - 8'h57)};
                        end
                        prev_char <= uart_rx_data;
                    end
                end
                
                STATE_READ_PAYLOAD: begin
                    // Read payload bytes (raw binary data between '] [')
                    if (uart_rx_valid) begin
                        // Skip whitespace and brackets
                        if (uart_rx_data == 8'h20 || uart_rx_data == 8'h5B) begin  // space or '['
                            // Skip
                        end else if (prev_char == 8'h5D && uart_rx_data == 8'h5B) begin
                            // End of payload, start of checksum
                            parse_state <= STATE_WAIT_CKSUM;
                        end else begin
                            // Store payload byte
                            if (payload_index < 128) begin
                                cmd_payload[payload_index] <= uart_rx_data;
                                checksum_calc <= checksum_calc + uart_rx_data;
                                payload_index <= payload_index + 1'b1;
                                
                                if (payload_index + 1'b1 >= cmd_length[7:0])
                                    parse_state <= STATE_WAIT_CKSUM;
                            end
                        end
                        prev_char <= uart_rx_data;
                    end
                end
                
                STATE_WAIT_CKSUM: begin
                    // Look for "[CKSUM:ZZ]" and verify
                    if (uart_rx_valid) begin
                        if (uart_rx_data == 8'h0A || uart_rx_data == 8'h0D) begin  // '\n' or '\r'
                            // End of frame - validate checksum
                            // For simplicity, skip checksum validation for now
                            // In production, compare checksum_calc with checksum_recv
                            cmd_valid <= 1'b1;
                            parse_state <= STATE_EXECUTE;
                        end else if (uart_rx_data >= 8'h30 && uart_rx_data <= 8'h39) begin
                            checksum_recv <= {checksum_recv[3:0], (uart_rx_data - 8'h30)};
                        end else if (uart_rx_data >= 8'h41 && uart_rx_data <= 8'h46) begin
                            checksum_recv <= {checksum_recv[3:0], (uart_rx_data - 8'h37)};
                        end else if (uart_rx_data >= 8'h61 && uart_rx_data <= 8'h66) begin
                            checksum_recv <= {checksum_recv[3:0], (uart_rx_data - 8'h57)};
                        end
                        prev_char <= uart_rx_data;
                    end
                end
                
                STATE_EXECUTE: begin
                    // Execute the command
                    parse_state <= STATE_SEND_ACK;
                end
                
                STATE_SEND_ACK: begin
                    // Send acknowledgment (simplified)
                    in_frame <= 1'b0;
                    parse_state <= STATE_IDLE;
                end
                
                STATE_SEND_NAK: begin
                    // Send negative acknowledgment
                    in_frame <= 1'b0;
                    parse_state <= STATE_IDLE;
                end
                
                default: parse_state <= STATE_IDLE;
            endcase
        end
    end
    
    // =======================================================================
    // Command Execution
    // =======================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            inject_kbd_report <= 64'd0;
            inject_kbd_valid <= 1'b0;
            inject_mouse_report <= 40'd0;
            inject_mouse_valid <= 1'b0;
            filter_mask <= 32'hFFFFFFFF;  // No filtering by default
            mode_proxy <= 1'b1;           // Proxy enabled by default
            mode_host <= 1'b0;
        end else begin
            // Clear valid flags after acknowledgment
            if (inject_kbd_ack)
                inject_kbd_valid <= 1'b0;
            if (inject_mouse_ack)
                inject_mouse_valid <= 1'b0;
            
            // Execute commands
            if (cmd_valid && parse_state == STATE_EXECUTE) begin
                case (cmd_code)
                    CMD_INJECT_KBD: begin
                        // Inject keyboard report (8 bytes)
                        if (cmd_length >= 8) begin
                            inject_kbd_report <= {
                                cmd_payload[7],
                                cmd_payload[6],
                                cmd_payload[5],
                                cmd_payload[4],
                                cmd_payload[3],
                                cmd_payload[2],
                                cmd_payload[1],
                                cmd_payload[0]
                            };
                            inject_kbd_valid <= 1'b1;
                        end
                    end
                    
                    CMD_INJECT_MOUSE: begin
                        // Inject mouse report (5 bytes)
                        if (cmd_length >= 5) begin
                            inject_mouse_report <= {
                                cmd_payload[4],
                                cmd_payload[3],
                                cmd_payload[2],
                                cmd_payload[1],
                                cmd_payload[0]
                            };
                            inject_mouse_valid <= 1'b1;
                        end
                    end
                    
                    CMD_SET_FILTER: begin
                        // Set filter mask (4 bytes)
                        if (cmd_length >= 4) begin
                            filter_mask <= {
                                cmd_payload[3],
                                cmd_payload[2],
                                cmd_payload[1],
                                cmd_payload[0]
                            };
                        end
                    end
                    
                    CMD_SET_MODE: begin
                        // Set mode (1 byte: bit 0 = proxy, bit 1 = host)
                        if (cmd_length >= 1) begin
                            mode_proxy <= cmd_payload[0][0];
                            mode_host <= cmd_payload[0][1];
                        end
                    end
                    
                    default: begin
                        // Unknown command - ignore
                    end
                endcase
            end
        end
    end

endmodule
