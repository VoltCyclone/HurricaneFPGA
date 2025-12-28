///////////////////////////////////////////////////////////////////////////////
// File: usb_descriptor_forwarder.v
// Description: USB HID Descriptor Forwarder to SAMD51
//
// This module monitors USB traffic for GET_DESCRIPTOR requests/responses
// targeting HID Report Descriptors (type 0x22). When detected, it forwards
// the descriptor data to the SAMD51 via UART for automatic parsing.
//
// Flow:
//   1. Monitor SETUP packets for GET_DESCRIPTOR (HID Report Descriptor)
//   2. Capture the following IN DATA packets
//   3. Forward to SAMD51 with framing: [DESC:ADDR:IF] {hex_data}
//
// Target: Lattice ECP5 on Cynthion device
///////////////////////////////////////////////////////////////////////////////

module usb_descriptor_forwarder (
    // Clock and Reset
    input  wire        clk,
    input  wire        rst_n,
    
    // USB Monitor Interface (from usb_monitor or packet_proxy)
    input  wire [7:0]  usb_pid,              // USB PID
    input  wire [7:0]  usb_data,             // USB data byte
    input  wire        usb_data_valid,       // Data valid strobe
    input  wire        usb_packet_end,       // Packet complete
    input  wire [6:0]  usb_device_addr,      // Current device address
    input  wire [3:0]  usb_endpoint,         // Current endpoint
    
    // UART TX Interface (to SAMD51)
    output reg  [7:0]  uart_tx_data,
    output reg         uart_tx_valid,
    input  wire        uart_tx_ready,
    
    // Status/Debug
    output reg         descriptor_forwarding, // Currently forwarding descriptor
    output reg  [15:0] descriptor_bytes_sent  // Total bytes forwarded
);

    // USB PIDs
    localparam PID_SETUP = 4'b1101;
    localparam PID_DATA0 = 4'b0011;
    localparam PID_DATA1 = 4'b1011;
    localparam PID_ACK   = 4'b0010;
    
    // USB Request Types
    localparam REQ_GET_DESCRIPTOR = 8'h06;
    localparam DESC_TYPE_HID_REPORT = 8'h22;
    
    // FSM States
    localparam STATE_IDLE          = 4'd0;
    localparam STATE_CAPTURE_SETUP = 4'd1;
    localparam STATE_WAIT_DATA     = 4'd2;
    localparam STATE_CAPTURE_DESC  = 4'd3;
    localparam STATE_SEND_HEADER   = 4'd4;
    localparam STATE_SEND_DATA     = 4'd5;
    localparam STATE_SEND_FOOTER   = 4'd6;
    
    reg [3:0] state;
    reg [3:0] next_state;
    
    // SETUP packet buffer (packed 64-bit register)
    reg [63:0] setup_packet;
    reg [2:0] setup_index;
    wire [7:0] setup_byte0 = setup_packet[7:0];
    wire [7:0] setup_byte1 = setup_packet[15:8];
    wire [7:0] setup_byte2 = setup_packet[23:16];
    wire [7:0] setup_byte3 = setup_packet[31:24];
    wire [7:0] setup_byte4 = setup_packet[39:32];
    wire [7:0] setup_byte5 = setup_packet[47:40];
    wire [7:0] setup_byte6 = setup_packet[55:48];
    wire [7:0] setup_byte7 = setup_packet[63:56];
    reg       setup_complete;
    
    // Descriptor capture (reduced from 1024 to 256 bytes with block RAM attribute)
    (* syn_ramstyle = "block_ram" *) reg [7:0] desc_buffer [0:255];
    reg [7:0] desc_write_ptr;
    reg [7:0] desc_read_ptr;
    reg [7:0] desc_read_data;    // Registered read for block RAM inference
    reg [7:0] desc_length;
    reg [6:0]  desc_device_addr;
    reg [3:0]  desc_interface;
    reg        desc_capture_active;
    reg        desc_ready_to_send;
    
    // Memory write signals for BRAM inference
    reg        desc_write_enable;
    reg [7:0]  desc_write_addr_sig;
    reg [7:0]  desc_write_data_sig;
    
    // UART transmit (packed 160-bit register for 20-byte header)
    reg [159:0] tx_header;
    reg [4:0] tx_header_index;
    reg       tx_sending_header;
    reg       tx_sending_data;
    reg       tx_sending_footer;
    
    // =======================================================================
    // SETUP Packet Capture
    // =======================================================================
    
    integer i;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            setup_index <= 3'd0;
            setup_complete <= 1'b0;
            setup_packet <= 64'd0;
        end else begin
            if (usb_data_valid && usb_pid[3:0] == PID_SETUP) begin
                // Capture SETUP packet data using shift register
                if (setup_index < 4'd8) begin  // Fixed: 4-bit literal for 8
                    setup_packet <= {usb_data, setup_packet[63:8]};
                    setup_index <= setup_index + 1;
                end
            end else if (usb_packet_end && usb_pid[3:0] == PID_SETUP) begin
                setup_complete <= (setup_index == 4'd8);  // Fixed: 4-bit literal
                setup_index <= 3'd0;
            end else if (state == STATE_IDLE) begin
                setup_complete <= 1'b0;
            end
        end
    end
    
    // Check if SETUP is GET_DESCRIPTOR for HID Report Descriptor
    wire is_get_hid_descriptor;
    assign is_get_hid_descriptor = setup_complete &&
                                   (setup_byte1 == REQ_GET_DESCRIPTOR) &&
                                   (setup_byte3 == DESC_TYPE_HID_REPORT);
    
    // Extract interface number from wIndex
    wire [3:0] setup_interface;
    assign setup_interface = setup_byte4[3:0];
    
    // =======================================================================
    // Descriptor Capture State Machine
    // =======================================================================
    
    // CRITICAL: Dual-port BRAM inference pattern
    // Read and write in same always block with separate ports
    always @(posedge clk) begin
        if (desc_write_enable)
            desc_buffer[desc_write_addr_sig] <= desc_write_data_sig;
        desc_read_data <= desc_buffer[desc_read_ptr];
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            desc_write_ptr <= 11'd0;
            desc_read_ptr <= 11'd0;
            desc_length <= 11'd0;
            desc_device_addr <= 7'd0;
            desc_interface <= 4'd0;
            desc_capture_active <= 1'b0;
            desc_ready_to_send <= 1'b0;
            descriptor_forwarding <= 1'b0;
            descriptor_bytes_sent <= 16'd0;
            desc_write_enable <= 1'b0;
            desc_write_addr_sig <= 8'd0;
            desc_write_data_sig <= 8'd0;
        end else begin
            // Default: disable write
            desc_write_enable <= 1'b0;
            case (state)
                STATE_IDLE: begin
                    if (is_get_hid_descriptor) begin
                        // Start capturing HID descriptor
                        desc_device_addr <= usb_device_addr;
                        desc_interface <= setup_interface;
                        desc_write_ptr <= 11'd0;
                        desc_capture_active <= 1'b1;
                        desc_ready_to_send <= 1'b0;
                        state <= STATE_WAIT_DATA;
                    end
                end
                
                STATE_WAIT_DATA: begin
                    // Wait for DATA0/DATA1 packet with descriptor
                    if (usb_data_valid && 
                        (usb_pid[3:0] == PID_DATA0 || usb_pid[3:0] == PID_DATA1)) begin
                        // Start capturing descriptor bytes
                        state <= STATE_CAPTURE_DESC;
                    end
                end
                
                STATE_CAPTURE_DESC: begin
                    if (usb_data_valid) begin
                        // Store descriptor byte
                        if (desc_write_ptr < 9'd256) begin  // Fixed: 9-bit literal for 256
                            desc_write_enable <= 1'b1;
                            desc_write_addr_sig <= desc_write_ptr;
                            desc_write_data_sig <= usb_data;
                            desc_write_ptr <= desc_write_ptr + 1;
                        end
                    end
                    
                    if (usb_packet_end) begin
                        // Descriptor packet complete
                        desc_length <= desc_write_ptr;
                        desc_capture_active <= 1'b0;
                        desc_ready_to_send <= 1'b1;
                        desc_read_ptr <= 11'd0;
                        state <= STATE_SEND_HEADER;
                    end
                end
                
                STATE_SEND_HEADER: begin
                    // Send header: [DESC:AA:II]{
                    if (uart_tx_ready) begin
                        if (tx_header_index == 0) begin
                            // Build header
                            build_header();
                            tx_header_index <= 5'd1;
                            uart_tx_data <= tx_header[0];
                            uart_tx_valid <= 1'b1;
                            descriptor_forwarding <= 1'b1;
                        end else if (tx_header_index < 12) begin
                            uart_tx_data <= tx_header[tx_header_index];
                            uart_tx_valid <= 1'b1;
                            tx_header_index <= tx_header_index + 1;
                        end else begin
                            uart_tx_valid <= 1'b0;
                            tx_header_index <= 5'd0;
                            state <= STATE_SEND_DATA;
                        end
                    end
                end
                
                STATE_SEND_DATA: begin
                    // Send descriptor data as hex: AA,BB,CC,...
                    if (uart_tx_ready) begin
                        if (desc_read_ptr < desc_length) begin
                            // Send byte as two hex digits + comma (using registered read data)
                            if (tx_header_index == 0) begin
                                // Send high nibble
                                uart_tx_data <= nibble_to_hex(desc_read_data[7:4]);
                                uart_tx_valid <= 1'b1;
                                tx_header_index <= 5'd1;
                            end else if (tx_header_index == 1) begin
                                // Send low nibble
                                uart_tx_data <= nibble_to_hex(desc_read_data[3:0]);
                                uart_tx_valid <= 1'b1;
                                tx_header_index <= 5'd2;
                            end else if (tx_header_index == 2) begin
                                // Send comma (unless last byte)
                                if (desc_read_ptr < desc_length - 1) begin
                                    uart_tx_data <= 8'h2C;  // ','
                                    uart_tx_valid <= 1'b1;
                                end else begin
                                    uart_tx_valid <= 1'b0;
                                end
                                tx_header_index <= 5'd0;
                                desc_read_ptr <= desc_read_ptr + 1;
                                descriptor_bytes_sent <= descriptor_bytes_sent + 1;
                            end
                        end else begin
                            uart_tx_valid <= 1'b0;
                            state <= STATE_SEND_FOOTER;
                        end
                    end
                end
                
                STATE_SEND_FOOTER: begin
                    // Send footer: }\n
                    if (uart_tx_ready) begin
                        if (tx_header_index == 0) begin
                            uart_tx_data <= 8'h7D;  // '}'
                            uart_tx_valid <= 1'b1;
                            tx_header_index <= 5'd1;
                        end else if (tx_header_index == 1) begin
                            uart_tx_data <= 8'h0A;  // '\n'
                            uart_tx_valid <= 1'b1;
                            tx_header_index <= 5'd2;
                        end else begin
                            uart_tx_valid <= 1'b0;
                            tx_header_index <= 5'd0;
                            desc_ready_to_send <= 1'b0;
                            descriptor_forwarding <= 1'b0;
                            state <= STATE_IDLE;
                        end
                    end
                end
                
                default: state <= STATE_IDLE;
            endcase
        end
    end
    
    // =======================================================================
    // Helper Tasks and Functions
    // =======================================================================
    
    // Build UART header: [DESC:AA:II]{
    task build_header;
        begin
            tx_header[0]  = 8'h5B;  // '['
            tx_header[1]  = 8'h44;  // 'D'
            tx_header[2]  = 8'h45;  // 'E'
            tx_header[3]  = 8'h53;  // 'S'
            tx_header[4]  = 8'h43;  // 'C'
            tx_header[5]  = 8'h3A;  // ':'
            tx_header[6]  = nibble_to_hex(desc_device_addr[6:3]);  // Address high
            tx_header[7]  = nibble_to_hex({1'b0, desc_device_addr[2:0]});  // Address low
            tx_header[8]  = 8'h3A;  // ':'
            tx_header[9]  = nibble_to_hex(desc_interface);  // Interface
            tx_header[10] = 8'h5D;  // ']'
            tx_header[11] = 8'h7B;  // '{'
        end
    endtask
    
    // Convert nibble to hex ASCII
    function [7:0] nibble_to_hex;
        input [3:0] nibble;
        begin
            if (nibble < 10)
                nibble_to_hex = 8'h30 + nibble;       // '0'-'9'
            else
                nibble_to_hex = 8'h61 + (nibble - 10);  // 'a'-'f'
        end
    endfunction

endmodule
