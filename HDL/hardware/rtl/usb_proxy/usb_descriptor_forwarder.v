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
    
    // SETUP packet buffer (8 bytes)
    reg [7:0] setup_packet [0:7];
    reg [2:0] setup_index;
    reg       setup_complete;
    
    // Descriptor capture
    reg [7:0]  desc_buffer [0:1023];  // Max 1KB descriptor
    reg [10:0] desc_write_ptr;
    reg [10:0] desc_read_ptr;
    reg [10:0] desc_length;
    reg [6:0]  desc_device_addr;
    reg [3:0]  desc_interface;
    reg        desc_capture_active;
    reg        desc_ready_to_send;
    
    // UART transmit
    reg [7:0] tx_header [0:19];  // "[DESC:AA:II]{"
    reg [4:0] tx_header_index;
    reg       tx_sending_header;
    reg       tx_sending_data;
    reg       tx_sending_footer;
    
    // =======================================================================
    // SETUP Packet Capture
    // =======================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            setup_index <= 3'd0;
            setup_complete <= 1'b0;
            integer i;
            for (i = 0; i < 8; i = i + 1)
                setup_packet[i] <= 8'd0;
        end else begin
            if (usb_data_valid && usb_pid[3:0] == PID_SETUP) begin
                // Capture SETUP packet data
                if (setup_index < 8) begin
                    setup_packet[setup_index] <= usb_data;
                    setup_index <= setup_index + 1;
                end
            end else if (usb_packet_end && usb_pid[3:0] == PID_SETUP) begin
                setup_complete <= (setup_index == 8);
                setup_index <= 3'd0;
            end else if (state == STATE_IDLE) begin
                setup_complete <= 1'b0;
            end
        end
    end
    
    // Check if SETUP is GET_DESCRIPTOR for HID Report Descriptor
    wire is_get_hid_descriptor;
    assign is_get_hid_descriptor = setup_complete &&
                                   (setup_packet[1] == REQ_GET_DESCRIPTOR) &&
                                   (setup_packet[3] == DESC_TYPE_HID_REPORT);
    
    // Extract interface number from wIndex
    wire [3:0] setup_interface;
    assign setup_interface = setup_packet[4][3:0];
    
    // =======================================================================
    // Descriptor Capture State Machine
    // =======================================================================
    
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
        end else begin
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
                        if (desc_write_ptr < 1024) begin
                            desc_buffer[desc_write_ptr] <= usb_data;
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
                            // Send byte as two hex digits + comma
                            if (tx_header_index == 0) begin
                                // Send high nibble
                                uart_tx_data <= nibble_to_hex(desc_buffer[desc_read_ptr][7:4]);
                                uart_tx_valid <= 1'b1;
                                tx_header_index <= 5'd1;
                            end else if (tx_header_index == 1) begin
                                // Send low nibble
                                uart_tx_data <= nibble_to_hex(desc_buffer[desc_read_ptr][3:0]);
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
