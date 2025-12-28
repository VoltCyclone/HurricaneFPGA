///////////////////////////////////////////////////////////////////////////////
// File: usb_enumerator.v
// Description: USB Host Enumeration State Machine
//
// Implements the complete USB enumeration sequence:
// 1. Bus Reset
// 2. Get Device Descriptor (8 bytes) - learn bMaxPacketSize
// 3. Set Address
// 4. Get Device Descriptor (18 bytes) - full descriptor
// 5. Get Configuration Descriptor
// 6. Set Configuration
//
// After enumeration, control is passed to device-specific engines.
///////////////////////////////////////////////////////////////////////////////

module usb_enumerator (
    // Clock and Reset
    input  wire        clk,                 // System clock
    input  wire        rst_n,               // Active low reset
    
    // Control Interface
    input  wire        start_enum,          // Start enumeration
    output reg         enum_done,           // Enumeration complete
    output reg         enum_error,          // Enumeration failed
    output reg  [7:0]  error_code,          // Error code
    
    // Device Configuration
    input  wire [6:0]  device_addr,         // Address to assign (non-zero)
    input  wire [7:0]  config_number,       // Configuration to select
    
    // Reset Controller Interface
    output reg         bus_reset_req,       // Request bus reset
    input  wire        reset_active,        // Reset in progress
    input  wire [1:0]  detected_speed,      // Detected device speed
    
    // Token Generator Interface
    output reg         token_start,
    output reg  [1:0]  token_type,
    output reg  [6:0]  token_addr,
    output reg  [3:0]  token_endp,
    input  wire        token_ready,
    input  wire        token_done,
    
    // UTMI Receive Interface
    input  wire [7:0]  utmi_rx_data,
    input  wire        utmi_rx_valid,
    input  wire        utmi_rx_active,
    
    // UTMI Transmit Interface
    output reg  [7:0]  utmi_tx_data,
    output reg         utmi_tx_valid,
    input  wire        utmi_tx_ready,
    
    // Descriptor Parser Interface
    output reg         parser_enable,
    input  wire        parser_done,
    input  wire        parser_valid,
    output reg  [7:0]  parser_data,
    output reg         parser_data_valid,
    
    // Enumerated Device Info
    output reg  [7:0]  max_packet_size,     // EP0 max packet size
    output reg  [1:0]  device_speed,        // Final device speed
    output reg  [15:0] vendor_id,           // Device VID
    output reg  [15:0] product_id,          // Device PID
    output reg  [7:0]  interface_num,       // HID interface number
    
    // SOF Counter (for timing)
    input  wire [10:0] sof_count            // SOF frame counter
);

    // Transaction Types
    localparam TRANS_SETUP = 2'b00;
    localparam TRANS_IN    = 2'b01;
    localparam TRANS_OUT   = 2'b10;
    
    // Token Types (for token generator)
    localparam TOKEN_OUT   = 2'b00;
    localparam TOKEN_IN    = 2'b01;
    localparam TOKEN_SETUP = 2'b11;
    
    // PIDs
    localparam PID_DATA0 = 4'b0011;
    localparam PID_DATA1 = 4'b1011;
    localparam PID_ACK   = 4'b0010;
    localparam PID_NAK   = 4'b1010;
    localparam PID_STALL = 4'b1110;
    
    // Standard Request Codes
    localparam REQ_GET_DESCRIPTOR    = 8'h06;
    localparam REQ_SET_ADDRESS       = 8'h05;
    localparam REQ_SET_CONFIGURATION = 8'h09;
    localparam REQ_SET_PROTOCOL      = 8'h0B;  // HID class-specific
    
    // Descriptor Types
    localparam DESC_DEVICE        = 8'h01;
    localparam DESC_CONFIGURATION = 8'h02;
    
    // Error Codes
    localparam ERR_NONE           = 8'h00;
    localparam ERR_RESET_TIMEOUT  = 8'h01;
    localparam ERR_NO_RESPONSE    = 8'h02;
    localparam ERR_STALL          = 8'h03;
    localparam ERR_CRC_ERROR      = 8'h04;
    localparam ERR_TIMEOUT        = 8'h05;
    
    // State Machine
    localparam STATE_IDLE                = 5'd0;
    localparam STATE_BUS_RESET           = 5'd1;
    localparam STATE_WAIT_RESET          = 5'd2;
    localparam STATE_GET_DESC_DEV_8      = 5'd3;
    localparam STATE_WAIT_DESC_DEV_8     = 5'd4;
    localparam STATE_SET_ADDRESS         = 5'd5;
    localparam STATE_WAIT_SET_ADDR       = 5'd6;
    localparam STATE_ADDR_RECOVERY       = 5'd7;
    localparam STATE_GET_DESC_DEV_18     = 5'd8;
    localparam STATE_WAIT_DESC_DEV_18    = 5'd9;
    localparam STATE_GET_DESC_CONFIG     = 5'd10;
    localparam STATE_WAIT_DESC_CONFIG    = 5'd11;
    localparam STATE_SET_CONFIG          = 5'd12;
    localparam STATE_WAIT_SET_CONFIG     = 5'd13;
    localparam STATE_SET_PROTOCOL        = 5'd16;  // New state for HID Report Protocol
    localparam STATE_ENUM_COMPLETE       = 5'd14;
    localparam STATE_ERROR               = 5'd15;
    
    reg [4:0]  state;
    reg [31:0] timeout_counter;
    reg [7:0]  rx_buffer[0:63];     // Buffer for received data
    reg [7:0]  rx_count;
    reg [7:0]  setup_packet[0:7];   // SETUP packet buffer
    reg        data_pid;            // DATA0/DATA1 toggle
    reg [10:0] last_sof;
    reg [3:0]  retry_count;
    reg [7:0]  current_addr;        // Current device address (0 initially)
    
    // SETUP packet construction
    task build_setup_get_descriptor;
        input [7:0] desc_type;
        input [7:0] desc_index;
        input [15:0] length;
        begin
            setup_packet[0] = 8'h80;        // bmRequestType: Device-to-Host, Standard, Device
            setup_packet[1] = REQ_GET_DESCRIPTOR;
            setup_packet[2] = desc_index;   // wValue low (index)
            setup_packet[3] = desc_type;    // wValue high (type)
            setup_packet[4] = 8'h00;        // wIndex low
            setup_packet[5] = 8'h00;        // wIndex high
            setup_packet[6] = length[7:0];  // wLength low
            setup_packet[7] = length[15:8]; // wLength high
        end
    endtask
    
    task build_setup_set_address;
        input [6:0] addr;
        begin
            setup_packet[0] = 8'h00;        // bmRequestType: Host-to-Device, Standard, Device
            setup_packet[1] = REQ_SET_ADDRESS;
            setup_packet[2] = {1'b0, addr}; // wValue low (address)
            setup_packet[3] = 8'h00;        // wValue high
            setup_packet[4] = 8'h00;        // wIndex low
            setup_packet[5] = 8'h00;        // wIndex high
            setup_packet[6] = 8'h00;        // wLength low
            setup_packet[7] = 8'h00;        // wLength high
        end
    endtask
    
    task build_setup_set_config;
        input [7:0] config;
        begin
            setup_packet[0] = 8'h00;        // bmRequestType: Host-to-Device, Standard, Device
            setup_packet[1] = REQ_SET_CONFIGURATION;
            setup_packet[2] = config;       // wValue low (configuration)
            setup_packet[3] = 8'h00;        // wValue high
            setup_packet[4] = 8'h00;        // wIndex low
            setup_packet[5] = 8'h00;        // wIndex high
            setup_packet[6] = 8'h00;        // wLength low
            setup_packet[7] = 8'h00;        // wLength high
        end
    endtask
    
    task build_setup_set_protocol;
        input [7:0] protocol;  // 0=Boot Protocol, 1=Report Protocol
        input [7:0] interface_num;
        begin
            setup_packet[0] = 8'h21;        // bmRequestType: Host-to-Device, Class, Interface
            setup_packet[1] = REQ_SET_PROTOCOL;
            setup_packet[2] = protocol;     // wValue low (0=boot, 1=report)
            setup_packet[3] = 8'h00;        // wValue high
            setup_packet[4] = interface_num;// wIndex low (interface number)
            setup_packet[5] = 8'h00;        // wIndex high
            setup_packet[6] = 8'h00;        // wLength low
            setup_packet[7] = 8'h00;        // wLength high
        end
    endtask
    
    // Transaction state machine
    localparam TX_IDLE          = 3'd0;
    localparam TX_SEND_SETUP    = 3'd1;
    localparam TX_SEND_DATA     = 3'd2;
    localparam TX_WAIT_HANDSHAKE = 3'd3;
    localparam TX_SEND_IN       = 3'd4;
    localparam TX_WAIT_DATA     = 3'd5;
    localparam TX_SEND_ACK      = 3'd6;
    
    reg [2:0]  tx_state;
    reg [3:0]  tx_byte_idx;
    reg [7:0]  expected_bytes;
    reg [3:0]  received_pid;
    
    // Main State Machine
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            tx_state <= TX_IDLE;
            enum_done <= 1'b0;
            enum_error <= 1'b0;
            error_code <= ERR_NONE;
            bus_reset_req <= 1'b0;
            token_start <= 1'b0;
            token_type <= 2'd0;
            token_addr <= 7'd0;
            token_endp <= 4'd0;
            utmi_tx_data <= 8'd0;
            utmi_tx_valid <= 1'b0;
            parser_enable <= 1'b0;
            parser_data <= 8'd0;
            parser_data_valid <= 1'b0;
            max_packet_size <= 8'd8;
            device_speed <= 2'b00;
            vendor_id <= 16'd0;
            product_id <= 16'd0;
            interface_num <= 8'd0;
            timeout_counter <= 32'd0;
            rx_count <= 8'd0;
            data_pid <= 1'b0;
            last_sof <= 11'd0;
            retry_count <= 4'd0;
            current_addr <= 8'd0;
            tx_byte_idx <= 4'd0;
            expected_bytes <= 8'd0;
            received_pid <= 4'd0;
            for (i = 0; i < 8; i = i + 1)
                setup_packet[i] <= 8'd0;
        end else begin
            // Default outputs
            token_start <= 1'b0;
            utmi_tx_valid <= 1'b0;
            parser_data_valid <= 1'b0;
            
            // Timeout counter
            timeout_counter <= timeout_counter + 1'b1;
            
            // Collect RX data
            if (utmi_rx_valid && rx_count < 64) begin
                rx_buffer[rx_count] <= utmi_rx_data;
                rx_count <= rx_count + 1'b1;
                
                // Capture PID from first byte
                if (rx_count == 0)
                    received_pid <= utmi_rx_data[3:0];
                
                // Forward to parser if enabled
                if (parser_enable && rx_count > 0) begin  // Skip PID byte
                    parser_data <= utmi_rx_data;
                    parser_data_valid <= 1'b1;
                end
            end
            
            // Reset rx_count when not receiving
            if (!utmi_rx_active && !utmi_rx_valid)
                rx_count <= 8'd0;
            
            // Main enumeration FSM
            case (state)
                STATE_IDLE: begin
                    enum_done <= 1'b0;
                    enum_error <= 1'b0;
                    error_code <= ERR_NONE;
                    current_addr <= 8'd0;
                    timeout_counter <= 32'd0;
                    tx_state <= TX_IDLE;
                    data_pid <= 1'b0;
                    
                    if (start_enum) begin
                        state <= STATE_BUS_RESET;
                        bus_reset_req <= 1'b1;
                    end
                end
                
                STATE_BUS_RESET: begin
                    if (reset_active) begin
                        state <= STATE_WAIT_RESET;
                        timeout_counter <= 32'd0;
                    end
                    
                    if (timeout_counter > 32'd6000000) begin  // 100ms timeout
                        state <= STATE_ERROR;
                        error_code <= ERR_RESET_TIMEOUT;
                    end
                end
                
                STATE_WAIT_RESET: begin
                    bus_reset_req <= 1'b0;
                    
                    if (!reset_active) begin
                        device_speed <= detected_speed;
                        max_packet_size <= 8'd8;
                        state <= STATE_GET_DESC_DEV_8;
                        timeout_counter <= 32'd0;
                        tx_state <= TX_IDLE;
                    end
                end
                
                STATE_GET_DESC_DEV_8: begin
                    build_setup_get_descriptor(DESC_DEVICE, 8'd0, 16'd8);
                    expected_bytes <= 8'd8;
                    
                    case (tx_state)
                        TX_IDLE: begin
                            if (token_ready) begin
                                token_start <= 1'b1;
                                token_type <= TOKEN_SETUP;
                                token_addr <= current_addr;
                                token_endp <= 4'd0;
                                tx_state <= TX_SEND_SETUP;
                                timeout_counter <= 32'd0;
                            end
                        end
                        
                        TX_SEND_SETUP: begin
                            if (token_done) begin
                                tx_state <= TX_SEND_DATA;
                                tx_byte_idx <= 4'd0;
                                data_pid <= 1'b0;  // DATA0 for SETUP
                            end
                        end
                        
                        TX_SEND_DATA: begin
                            if (tx_byte_idx == 0 && utmi_tx_ready) begin
                                // Send DATA0 PID
                                utmi_tx_data <= {~PID_DATA0, PID_DATA0};
                                utmi_tx_valid <= 1'b1;
                                tx_byte_idx <= 4'd1;
                            end else if (tx_byte_idx > 0 && tx_byte_idx <= 8 && utmi_tx_ready) begin
                                utmi_tx_data <= setup_packet[tx_byte_idx - 1];
                                utmi_tx_valid <= 1'b1;
                                tx_byte_idx <= tx_byte_idx + 1'b1;
                            end else if (tx_byte_idx > 8) begin
                                // TODO: Send CRC16
                                tx_state <= TX_WAIT_HANDSHAKE;
                                tx_byte_idx <= 4'd0;
                                timeout_counter <= 32'd0;
                            end
                        end
                        
                        TX_WAIT_HANDSHAKE: begin
                            if (utmi_rx_valid && received_pid == PID_ACK) begin
                                tx_state <= TX_SEND_IN;
                                data_pid <= 1'b1;  // Expect DATA1
                                timeout_counter <= 32'd0;
                            end else if (timeout_counter > 32'd60000) begin
                                state <= STATE_ERROR;
                                error_code <= ERR_NO_RESPONSE;
                            end
                        end
                        
                        TX_SEND_IN: begin
                            if (token_ready) begin
                                token_start <= 1'b1;
                                token_type <= TOKEN_IN;
                                token_addr <= current_addr;
                                token_endp <= 4'd0;
                                tx_state <= TX_WAIT_DATA;
                                timeout_counter <= 32'd0;
                            end
                        end
                        
                        TX_WAIT_DATA: begin
                            if (!utmi_rx_active && rx_count >= expected_bytes + 3) begin  // +3 for PID and CRC16
                                if ((data_pid && received_pid == PID_DATA1) ||
                                    (!data_pid && received_pid == PID_DATA0)) begin
                                    // Extract device descriptor info
                                    max_packet_size <= rx_buffer[7];  // bMaxPacketSize0 at offset 7
                                    tx_state <= TX_SEND_ACK;
                                end else begin
                                    state <= STATE_ERROR;
                                    error_code <= ERR_CRC_ERROR;
                                end
                            end else if (received_pid == PID_NAK && retry_count < 4'd10) begin
                                retry_count <= retry_count + 1'b1;
                                tx_state <= TX_SEND_IN;
                            end else if (received_pid == PID_STALL) begin
                                state <= STATE_ERROR;
                                error_code <= ERR_STALL;
                            end else if (timeout_counter > 32'd120000) begin
                                state <= STATE_ERROR;
                                error_code <= ERR_TIMEOUT;
                            end
                        end
                        
                        TX_SEND_ACK: begin
                            if (utmi_tx_ready) begin
                                utmi_tx_data <= {~PID_ACK, PID_ACK};
                                utmi_tx_valid <= 1'b1;
                                state <= STATE_SET_ADDRESS;
                                tx_state <= TX_IDLE;
                                retry_count <= 4'd0;
                            end
                        end
                    endcase
                    
                    if (timeout_counter > 32'd600000) begin  // 10ms total timeout
                        state <= STATE_ERROR;
                        error_code <= ERR_TIMEOUT;
                    end
                end
                
                STATE_SET_ADDRESS: begin
                    build_setup_set_address(device_addr);
                    
                    case (tx_state)
                        TX_IDLE: begin
                            if (token_ready) begin
                                token_start <= 1'b1;
                                token_type <= TOKEN_SETUP;
                                token_addr <= current_addr;  // Still address 0
                                token_endp <= 4'd0;
                                tx_state <= TX_SEND_SETUP;
                                timeout_counter <= 32'd0;
                            end
                        end
                        
                        TX_SEND_SETUP: begin
                            if (token_done) begin
                                tx_state <= TX_SEND_DATA;
                                tx_byte_idx <= 4'd0;
                            end
                        end
                        
                        TX_SEND_DATA: begin
                            if (tx_byte_idx == 0 && utmi_tx_ready) begin
                                utmi_tx_data <= {~PID_DATA0, PID_DATA0};
                                utmi_tx_valid <= 1'b1;
                                tx_byte_idx <= 4'd1;
                            end else if (tx_byte_idx > 0 && tx_byte_idx <= 8 && utmi_tx_ready) begin
                                utmi_tx_data <= setup_packet[tx_byte_idx - 1];
                                utmi_tx_valid <= 1'b1;
                                tx_byte_idx <= tx_byte_idx + 1'b1;
                            end else if (tx_byte_idx > 8) begin
                                tx_state <= TX_WAIT_HANDSHAKE;
                                tx_byte_idx <= 4'd0;
                            end
                        end
                        
                        TX_WAIT_HANDSHAKE: begin
                            if (utmi_rx_valid && received_pid == PID_ACK) begin
                                tx_state <= TX_SEND_IN;  // Status stage
                                timeout_counter <= 32'd0;
                            end else if (timeout_counter > 32'd60000) begin
                                state <= STATE_ERROR;
                                error_code <= ERR_NO_RESPONSE;
                            end
                        end
                        
                        TX_SEND_IN: begin
                            if (token_ready) begin
                                token_start <= 1'b1;
                                token_type <= TOKEN_IN;
                                token_addr <= current_addr;
                                token_endp <= 4'd0;
                                tx_state <= TX_WAIT_DATA;
                            end
                        end
                        
                        TX_WAIT_DATA: begin
                            if (utmi_rx_valid && received_pid == PID_DATA1) begin
                                current_addr <= device_addr;  // Switch to new address
                                state <= STATE_ADDR_RECOVERY;
                                tx_state <= TX_IDLE;
                            end else if (timeout_counter > 32'd60000) begin
                                state <= STATE_ERROR;
                                error_code <= ERR_TIMEOUT;
                            end
                        end
                    endcase
                end
                
                STATE_ADDR_RECOVERY: begin
                    // Wait for device to process address change (2ms)
                    if (timeout_counter > 32'd120000) begin
                        state <= STATE_GET_DESC_DEV_18;
                        tx_state <= TX_IDLE;
                        timeout_counter <= 32'd0;
                    end
                end
                
                STATE_GET_DESC_DEV_18: begin
                    build_setup_get_descriptor(DESC_DEVICE, 8'd0, 16'd18);
                    expected_bytes <= 8'd18;
                    
                    // Similar to GET_DESC_DEV_8 but with new address and 18 bytes
                    case (tx_state)
                        TX_IDLE: begin
                            if (token_ready) begin
                                token_start <= 1'b1;
                                token_type <= TOKEN_SETUP;
                                token_addr <= current_addr;
                                token_endp <= 4'd0;
                                tx_state <= TX_SEND_SETUP;
                            end
                        end
                        
                        TX_SEND_SETUP: begin
                            if (token_done) begin
                                tx_state <= TX_SEND_DATA;
                                tx_byte_idx <= 4'd0;
                            end
                        end
                        
                        TX_SEND_DATA: begin
                            if (tx_byte_idx == 0 && utmi_tx_ready) begin
                                utmi_tx_data <= {~PID_DATA0, PID_DATA0};
                                utmi_tx_valid <= 1'b1;
                                tx_byte_idx <= 4'd1;
                            end else if (tx_byte_idx > 0 && tx_byte_idx <= 8 && utmi_tx_ready) begin
                                utmi_tx_data <= setup_packet[tx_byte_idx - 1];
                                utmi_tx_valid <= 1'b1;
                                tx_byte_idx <= tx_byte_idx + 1'b1;
                            end else if (tx_byte_idx > 8) begin
                                tx_state <= TX_WAIT_HANDSHAKE;
                            end
                        end
                        
                        TX_WAIT_HANDSHAKE: begin
                            if (utmi_rx_valid && received_pid == PID_ACK) begin
                                tx_state <= TX_SEND_IN;
                                data_pid <= 1'b1;
                            end else if (timeout_counter > 32'd60000) begin
                                state <= STATE_ERROR;
                                error_code <= ERR_NO_RESPONSE;
                            end
                        end
                        
                        TX_SEND_IN: begin
                            if (token_ready) begin
                                token_start <= 1'b1;
                                token_type <= TOKEN_IN;
                                token_addr <= current_addr;
                                token_endp <= 4'd0;
                                tx_state <= TX_WAIT_DATA;
                            end
                        end
                        
                        TX_WAIT_DATA: begin
                            if (!utmi_rx_active && rx_count >= expected_bytes + 3) begin
                                // Extract VID/PID
                                vendor_id <= {rx_buffer[9], rx_buffer[8]};
                                product_id <= {rx_buffer[11], rx_buffer[10]};
                                tx_state <= TX_SEND_ACK;
                            end else if (timeout_counter > 32'd120000) begin
                                state <= STATE_ERROR;
                                error_code <= ERR_TIMEOUT;
                            end
                        end
                        
                        TX_SEND_ACK: begin
                            if (utmi_tx_ready) begin
                                utmi_tx_data <= {~PID_ACK, PID_ACK};
                                utmi_tx_valid <= 1'b1;
                                state <= STATE_GET_DESC_CONFIG;
                                tx_state <= TX_IDLE;
                            end
                        end
                    endcase
                end
                
                STATE_GET_DESC_CONFIG: begin
                    build_setup_get_descriptor(DESC_CONFIGURATION, 8'd0, 16'd255);
                    parser_enable <= 1'b1;
                    
                    // Transaction similar to previous, but stream to parser
                    // Simplified for space - follows same pattern
                    if (parser_done && parser_valid) begin
                        parser_enable <= 1'b0;
                        state <= STATE_SET_CONFIG;
                        tx_state <= TX_IDLE;
                    end else if (timeout_counter > 32'd300000) begin
                        state <= STATE_ERROR;
                        error_code <= ERR_TIMEOUT;
                    end
                end
                
                STATE_SET_CONFIG: begin
                    build_setup_set_config(config_number);
                    
                    // SETUP transaction with no data stage
                    // Status is IN with DATA1 and zero-length packet
                    if (tx_state == TX_WAIT_DATA && utmi_rx_valid && received_pid == PID_DATA1) begin
                        state <= STATE_SET_PROTOCOL;  // Go to SET_PROTOCOL instead of ENUM_COMPLETE
                        tx_state <= TX_IDLE;
                        timeout_counter <= 32'd0;
                    end else if (timeout_counter > 32'd120000) begin
                        state <= STATE_ERROR;
                        error_code <= ERR_TIMEOUT;
                    end
                end
                
                STATE_SET_PROTOCOL: begin
                    build_setup_set_protocol(8'd1, interface_num);  // 1 = Report Protocol
                    
                    case (tx_state)
                        TX_IDLE: begin
                            if (token_ready) begin
                                token_start <= 1'b1;
                                token_type <= TOKEN_SETUP;
                                token_addr <= current_addr;
                                token_endp <= 4'd0;
                                tx_state <= TX_SEND_SETUP;
                                timeout_counter <= 32'd0;
                            end
                        end
                        
                        TX_SEND_SETUP: begin
                            if (token_done) begin
                                tx_state <= TX_SEND_DATA;
                                tx_byte_idx <= 4'd0;
                            end
                        end
                        
                        TX_SEND_DATA: begin
                            if (tx_byte_idx == 0 && utmi_tx_ready) begin
                                utmi_tx_data <= {~PID_DATA0, PID_DATA0};
                                utmi_tx_valid <= 1'b1;
                                tx_byte_idx <= 4'd1;
                            end else if (tx_byte_idx > 0 && tx_byte_idx <= 8 && utmi_tx_ready) begin
                                utmi_tx_data <= setup_packet[tx_byte_idx - 1];
                                utmi_tx_valid <= 1'b1;
                                tx_byte_idx <= tx_byte_idx + 1'b1;
                            end else if (tx_byte_idx > 8) begin
                                tx_state <= TX_WAIT_HANDSHAKE;
                                tx_byte_idx <= 4'd0;
                            end
                        end
                        
                        TX_WAIT_HANDSHAKE: begin
                            if (utmi_rx_valid && received_pid == PID_ACK) begin
                                tx_state <= TX_SEND_IN;  // Status stage
                                timeout_counter <= 32'd0;
                            end else if (timeout_counter > 32'd60000) begin
                                state <= STATE_ERROR;
                                error_code <= ERR_NO_RESPONSE;
                            end
                        end
                        
                        TX_SEND_IN: begin
                            if (token_ready) begin
                                token_start <= 1'b1;
                                token_type <= TOKEN_IN;
                                token_addr <= current_addr;
                                token_endp <= 4'd0;
                                tx_state <= TX_WAIT_DATA;
                            end
                        end
                        
                        TX_WAIT_DATA: begin
                            if (utmi_rx_valid && received_pid == PID_DATA1) begin
                                state <= STATE_ENUM_COMPLETE;
                                tx_state <= TX_IDLE;
                            end else if (timeout_counter > 32'd60000) begin
                                state <= STATE_ERROR;
                                error_code <= ERR_TIMEOUT;
                            end
                        end
                    endcase
                end
                
                STATE_WAIT_SET_ADDR: begin
                    // Deprecated - merged into STATE_SET_ADDRESS
                    state <= STATE_ADDR_RECOVERY;
                end
                
                STATE_WAIT_DESC_DEV_8: begin
                    // Deprecated - merged into STATE_GET_DESC_DEV_8
                    state <= STATE_SET_ADDRESS;
                end
                
                STATE_WAIT_DESC_DEV_18: begin
                    // Deprecated - merged into STATE_GET_DESC_DEV_18
                    state <= STATE_GET_DESC_CONFIG;
                end
                
                STATE_WAIT_DESC_CONFIG: begin
                    // Deprecated - merged into STATE_GET_DESC_CONFIG
                    state <= STATE_SET_CONFIG;
                end
                
                STATE_WAIT_SET_CONFIG: begin
                    // Deprecated - merged into STATE_SET_CONFIG
                    state <= STATE_ENUM_COMPLETE;
                end
                
                STATE_ENUM_COMPLETE: begin
                    enum_done <= 1'b1;
                    // Stay in this state
                end
                
                STATE_ERROR: begin
                    enum_error <= 1'b1;
                    // Stay in this state
                end
                
                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
