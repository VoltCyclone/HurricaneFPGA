///////////////////////////////////////////////////////////////////////////////
// File: uart_debug_output.v
// Description: UART Debug Output Module for Status Reporting
//
// This module automatically generates debug status messages and sends them
// via UART0 to the SAMD51 (which bridges to USB CDC-ACM). This provides
// real-time visibility into the proxy operation without needing external
// debug tools.
//
// Features:
// - Periodic status updates (1 Hz)
// - Event-triggered messages (enumeration, HID reports)
// - Human-readable ASCII format
// - HID report decoding for keyboards and mice
//
// Output Format Examples:
//   [STATUS] Proxy: ON, Host: ON, Enum: DONE, Packets: 1234
//   [HID-KBD] Modifiers: 0x02, Keys: [0x04, 0x00, 0x00, 0x00, 0x00, 0x00]
//   [HID-MOUSE] Buttons: 0x01, dX: +5, dY: -3, Wheel: 0
//
// Target: Lattice ECP5 on Cynthion device
///////////////////////////////////////////////////////////////////////////////

module uart_debug_output (
    // Clock and Reset
    input  wire        clk,                 // System clock
    input  wire        rst_n,               // Active low reset
    
    // UART TX Interface
    output reg  [7:0]  uart_tx_data,        // UART transmit data
    output reg         uart_tx_valid,       // UART transmit valid
    input  wire        uart_tx_ready,       // UART ready for data
    
    // Status Inputs
    input  wire        proxy_enable,        // Proxy enabled
    input  wire        host_mode_enable,    // Host mode enabled
    input  wire        enum_done,           // Enumeration complete
    input  wire        kbd_active,          // Keyboard active
    input  wire        mouse_active,        // Mouse active
    input  wire        kbd_report_valid,    // Keyboard report available
    input  wire        mouse_report_valid,  // Mouse report available
    input  wire [63:0] kbd_report_data,     // Keyboard report (8 bytes)
    input  wire [39:0] mouse_report_data,   // Mouse report (5 bytes)
    input  wire [31:0] packet_count,        // Packet counter
    input  wire [15:0] error_count,         // Error counter
    input  wire        buffer_overflow      // Buffer overflow flag
);

    // Message buffer (with block RAM attribute for better synthesis)
    (* syn_ramstyle = "block_ram" *) reg [7:0] msg_buffer [255:0];
    reg [7:0] msg_buffer_out;  // Registered read for block RAM
    reg [7:0] msg_length;
    reg [7:0] msg_index;
    reg       msg_sending;
    
    // Memory write signals for BRAM inference
    reg        msg_write_enable;
    reg [7:0]  msg_write_addr;
    reg [7:0]  msg_write_data;
    
    // Timers
    reg [31:0] status_timer;        // 1 Hz status update timer
    localparam STATUS_PERIOD = 60_000_000;  // 1 second at 60MHz
    
    // Edge detection for HID reports
    reg kbd_report_valid_d;
    reg mouse_report_valid_d;
    wire kbd_report_edge = kbd_report_valid && !kbd_report_valid_d;
    wire mouse_report_edge = mouse_report_valid && !mouse_report_valid_d;
    
    // State machine
    localparam IDLE            = 3'd0;
    localparam SEND_STATUS     = 3'd1;
    localparam SEND_KBD_REPORT = 3'd2;
    localparam SEND_MOUSE_REPORT = 3'd3;
    localparam SENDING         = 3'd4;
    
    reg [2:0] state;
    reg [2:0] next_state;
    
    // Hex to ASCII conversion
    function [7:0] hex_to_ascii;
        input [3:0] hex;
        begin
            hex_to_ascii = (hex < 10) ? (8'h30 + hex) : (8'h41 + hex - 10);
        end
    endfunction
    
    // CRITICAL: Dual-port BRAM inference pattern
    // Read and write in same always block with separate ports
    always @(posedge clk) begin
        if (msg_write_enable)
            msg_buffer[msg_write_addr] <= msg_write_data;
        msg_buffer_out <= msg_buffer[msg_index];
    end

    // Message builders
    task build_status_message;
        integer i;
        begin
            i = 0;
            
            // "[STATUS] "
            msg_buffer[i] = 8'h5B; i = i + 1;  // '['
            msg_buffer[i] = 8'h53; i = i + 1;  // 'S'
            msg_buffer[i] = 8'h54; i = i + 1;  // 'T'
            msg_buffer[i] = 8'h41; i = i + 1;  // 'A'
            msg_buffer[i] = 8'h54; i = i + 1;  // 'T'
            msg_buffer[i] = 8'h55; i = i + 1;  // 'U'
            msg_buffer[i] = 8'h53; i = i + 1;  // 'S'
            msg_buffer[i] = 8'h5D; i = i + 1;  // ']'
            msg_buffer[i] = 8'h20; i = i + 1;  // ' '
            
            // "Proxy: "
            msg_buffer[i] = 8'h50; i = i + 1;  // 'P'
            msg_buffer[i] = 8'h72; i = i + 1;  // 'r'
            msg_buffer[i] = 8'h6F; i = i + 1;  // 'o'
            msg_buffer[i] = 8'h78; i = i + 1;  // 'x'
            msg_buffer[i] = 8'h79; i = i + 1;  // 'y'
            msg_buffer[i] = 8'h3A; i = i + 1;  // ':'
            msg_buffer[i] = 8'h20; i = i + 1;  // ' '
            
            // ON/OFF
            if (proxy_enable) begin
                msg_buffer[i] = 8'h4F; i = i + 1;  // 'O'
                msg_buffer[i] = 8'h4E; i = i + 1;  // 'N'
            end else begin
                msg_buffer[i] = 8'h4F; i = i + 1;  // 'O'
                msg_buffer[i] = 8'h46; i = i + 1;  // 'F'
                msg_buffer[i] = 8'h46; i = i + 1;  // 'F'
            end
            
            msg_buffer[i] = 8'h2C; i = i + 1;  // ','
            msg_buffer[i] = 8'h20; i = i + 1;  // ' '
            
            // "Host: "
            msg_buffer[i] = 8'h48; i = i + 1;  // 'H'
            msg_buffer[i] = 8'h6F; i = i + 1;  // 'o'
            msg_buffer[i] = 8'h73; i = i + 1;  // 's'
            msg_buffer[i] = 8'h74; i = i + 1;  // 't'
            msg_buffer[i] = 8'h3A; i = i + 1;  // ':'
            msg_buffer[i] = 8'h20; i = i + 1;  // ' '
            
            // ON/OFF
            if (host_mode_enable) begin
                msg_buffer[i] = 8'h4F; i = i + 1;  // 'O'
                msg_buffer[i] = 8'h4E; i = i + 1;  // 'N'
            end else begin
                msg_buffer[i] = 8'h4F; i = i + 1;  // 'O'
                msg_buffer[i] = 8'h46; i = i + 1;  // 'F'
                msg_buffer[i] = 8'h46; i = i + 1;  // 'F'
            end
            
            msg_buffer[i] = 8'h2C; i = i + 1;  // ','
            msg_buffer[i] = 8'h20; i = i + 1;  // ' '
            
            // "Enum: DONE/WAIT"
            msg_buffer[i] = 8'h45; i = i + 1;  // 'E'
            msg_buffer[i] = 8'h6E; i = i + 1;  // 'n'
            msg_buffer[i] = 8'h75; i = i + 1;  // 'u'
            msg_buffer[i] = 8'h6D; i = i + 1;  // 'm'
            msg_buffer[i] = 8'h3A; i = i + 1;  // ':'
            msg_buffer[i] = 8'h20; i = i + 1;  // ' '
            
            if (enum_done) begin
                msg_buffer[i] = 8'h44; i = i + 1;  // 'D'
                msg_buffer[i] = 8'h4F; i = i + 1;  // 'O'
                msg_buffer[i] = 8'h4E; i = i + 1;  // 'N'
                msg_buffer[i] = 8'h45; i = i + 1;  // 'E'
            end else begin
                msg_buffer[i] = 8'h57; i = i + 1;  // 'W'
                msg_buffer[i] = 8'h41; i = i + 1;  // 'A'
                msg_buffer[i] = 8'h49; i = i + 1;  // 'I'
                msg_buffer[i] = 8'h54; i = i + 1;  // 'T'
            end
            
            // "\r\n"
            msg_buffer[i] = 8'h0D; i = i + 1;  // CR
            msg_buffer[i] = 8'h0A; i = i + 1;  // LF
            
            msg_length = i[7:0];
        end
    endtask
    
    task build_kbd_report_message;
        integer i;
        integer j;
        begin
            i = 0;
            
            // "[HID-KBD] "
            msg_buffer[i] = 8'h5B; i = i + 1;  // '['
            msg_buffer[i] = 8'h48; i = i + 1;  // 'H'
            msg_buffer[i] = 8'h49; i = i + 1;  // 'I'
            msg_buffer[i] = 8'h44; i = i + 1;  // 'D'
            msg_buffer[i] = 8'h2D; i = i + 1;  // '-'
            msg_buffer[i] = 8'h4B; i = i + 1;  // 'K'
            msg_buffer[i] = 8'h42; i = i + 1;  // 'B'
            msg_buffer[i] = 8'h44; i = i + 1;  // 'D'
            msg_buffer[i] = 8'h5D; i = i + 1;  // ']'
            msg_buffer[i] = 8'h20; i = i + 1;  // ' '
            
            // "Mod: 0xXX"
            msg_buffer[i] = 8'h4D; i = i + 1;  // 'M'
            msg_buffer[i] = 8'h6F; i = i + 1;  // 'o'
            msg_buffer[i] = 8'h64; i = i + 1;  // 'd'
            msg_buffer[i] = 8'h3A; i = i + 1;  // ':'
            msg_buffer[i] = 8'h20; i = i + 1;  // ' '
            msg_buffer[i] = 8'h30; i = i + 1;  // '0'
            msg_buffer[i] = 8'h78; i = i + 1;  // 'x'
            msg_buffer[i] = hex_to_ascii(kbd_report_data[7:4]); i = i + 1;
            msg_buffer[i] = hex_to_ascii(kbd_report_data[3:0]); i = i + 1;
            
            // " Keys: ["
            msg_buffer[i] = 8'h20; i = i + 1;  // ' '
            msg_buffer[i] = 8'h4B; i = i + 1;  // 'K'
            msg_buffer[i] = 8'h65; i = i + 1;  // 'e'
            msg_buffer[i] = 8'h79; i = i + 1;  // 'y'
            msg_buffer[i] = 8'h73; i = i + 1;  // 's'
            msg_buffer[i] = 8'h3A; i = i + 1;  // ':'
            msg_buffer[i] = 8'h20; i = i + 1;  // ' '
            msg_buffer[i] = 8'h5B; i = i + 1;  // '['
            
            // Print first 3 keycodes (enough for most cases)
            for (j = 0; j < 3; j = j + 1) begin
                msg_buffer[i] = 8'h30; i = i + 1;  // '0'
                msg_buffer[i] = 8'h78; i = i + 1;  // 'x'
                msg_buffer[i] = hex_to_ascii(kbd_report_data[23-j*8 -: 4]); i = i + 1;
                msg_buffer[i] = hex_to_ascii(kbd_report_data[19-j*8 -: 4]); i = i + 1;
                if (j < 2) begin
                    msg_buffer[i] = 8'h2C; i = i + 1;  // ','
                    msg_buffer[i] = 8'h20; i = i + 1;  // ' '
                end
            end
            
            // "]\r\n"
            msg_buffer[i] = 8'h5D; i = i + 1;  // ']'
            msg_buffer[i] = 8'h0D; i = i + 1;  // CR
            msg_buffer[i] = 8'h0A; i = i + 1;  // LF
            
            msg_length = i[7:0];
        end
    endtask
    
    task build_mouse_report_message;
        integer i;
        begin
            i = 0;
            
            // "[HID-MOUSE] "
            msg_buffer[i] = 8'h5B; i = i + 1;  // '['
            msg_buffer[i] = 8'h48; i = i + 1;  // 'H'
            msg_buffer[i] = 8'h49; i = i + 1;  // 'I'
            msg_buffer[i] = 8'h44; i = i + 1;  // 'D'
            msg_buffer[i] = 8'h2D; i = i + 1;  // '-'
            msg_buffer[i] = 8'h4D; i = i + 1;  // 'M'
            msg_buffer[i] = 8'h4F; i = i + 1;  // 'O'
            msg_buffer[i] = 8'h55; i = i + 1;  // 'U'
            msg_buffer[i] = 8'h53; i = i + 1;  // 'S'
            msg_buffer[i] = 8'h45; i = i + 1;  // 'E'
            msg_buffer[i] = 8'h5D; i = i + 1;  // ']'
            msg_buffer[i] = 8'h20; i = i + 1;  // ' '
            
            // "Btn: 0xXX"
            msg_buffer[i] = 8'h42; i = i + 1;  // 'B'
            msg_buffer[i] = 8'h74; i = i + 1;  // 't'
            msg_buffer[i] = 8'h6E; i = i + 1;  // 'n'
            msg_buffer[i] = 8'h3A; i = i + 1;  // ':'
            msg_buffer[i] = 8'h20; i = i + 1;  // ' '
            msg_buffer[i] = 8'h30; i = i + 1;  // '0'
            msg_buffer[i] = 8'h78; i = i + 1;  // 'x'
            msg_buffer[i] = hex_to_ascii(mouse_report_data[7:4]); i = i + 1;
            msg_buffer[i] = hex_to_ascii(mouse_report_data[3:0]); i = i + 1;
            
            // " dX: 0xXX"
            msg_buffer[i] = 8'h20; i = i + 1;  // ' '
            msg_buffer[i] = 8'h64; i = i + 1;  // 'd'
            msg_buffer[i] = 8'h58; i = i + 1;  // 'X'
            msg_buffer[i] = 8'h3A; i = i + 1;  // ':'
            msg_buffer[i] = 8'h20; i = i + 1;  // ' '
            msg_buffer[i] = 8'h30; i = i + 1;  // '0'
            msg_buffer[i] = 8'h78; i = i + 1;  // 'x'
            msg_buffer[i] = hex_to_ascii(mouse_report_data[15:12]); i = i + 1;
            msg_buffer[i] = hex_to_ascii(mouse_report_data[11:8]); i = i + 1;
            
            // " dY: 0xXX"
            msg_buffer[i] = 8'h20; i = i + 1;  // ' '
            msg_buffer[i] = 8'h64; i = i + 1;  // 'd'
            msg_buffer[i] = 8'h59; i = i + 1;  // 'Y'
            msg_buffer[i] = 8'h3A; i = i + 1;  // ':'
            msg_buffer[i] = 8'h20; i = i + 1;  // ' '
            msg_buffer[i] = 8'h30; i = i + 1;  // '0'
            msg_buffer[i] = 8'h78; i = i + 1;  // 'x'
            msg_buffer[i] = hex_to_ascii(mouse_report_data[23:20]); i = i + 1;
            msg_buffer[i] = hex_to_ascii(mouse_report_data[19:16]); i = i + 1;
            
            // "\r\n"
            msg_buffer[i] = 8'h0D; i = i + 1;  // CR
            msg_buffer[i] = 8'h0A; i = i + 1;  // LF
            
            msg_length = i[7:0];
        end
    endtask
    
    // Main state machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            status_timer <= 0;
            kbd_report_valid_d <= 1'b0;
            mouse_report_valid_d <= 1'b0;
            msg_sending <= 1'b0;
            msg_index <= 0;
            uart_tx_valid <= 1'b0;
            uart_tx_data <= 8'h00;
        end else begin
            // Edge detection
            kbd_report_valid_d <= kbd_report_valid;
            mouse_report_valid_d <= mouse_report_valid;
            
            // Timer
            if (status_timer < STATUS_PERIOD - 1)
                status_timer <= status_timer + 1;
            else
                status_timer <= 0;
            
            case (state)
                IDLE: begin
                    // Priority: HID reports > periodic status
                    if (kbd_report_edge) begin
                        build_kbd_report_message();
                        state <= SENDING;
                        msg_index <= 0;
                    end else if (mouse_report_edge) begin
                        build_mouse_report_message();
                        state <= SENDING;
                        msg_index <= 0;
                    end else if (status_timer == 0) begin
                        build_status_message();
                        state <= SENDING;
                        msg_index <= 0;
                    end
                end
                
                SENDING: begin
                    if (msg_index < msg_length) begin
                        if (uart_tx_ready && !uart_tx_valid) begin
                            uart_tx_data <= msg_buffer_out;  // Use registered read
                            uart_tx_valid <= 1'b1;
                            msg_index <= msg_index + 1;
                        end else if (uart_tx_valid) begin
                            uart_tx_valid <= 1'b0;
                        end
                    end else begin
                        uart_tx_valid <= 1'b0;
                        state <= IDLE;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule
