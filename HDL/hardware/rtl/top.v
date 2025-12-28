///////////////////////////////////////////////////////////////////////////////
// File: top.v
// Description: Top-level module for Cynthion USB Transparent Proxy
//
// This module is the top-level integration for the Cynthion USB sniffer,
// connecting all components and providing the main interfaces.
//
// Target: Lattice ECP5 on Cynthion device
///////////////////////////////////////////////////////////////////////////////

module top (
    // Clock and Reset
    input  wire        clk_60mhz,       // 60MHz input clock
    input  wire        reset_n,         // Active low reset
    
    // USB PHY 0 - CONTROL (Internal MCU Access)
    inout  wire        usb0_dp,         // USB D+ (bidirectional)
    inout  wire        usb0_dn,         // USB D- (bidirectional)
    output wire        usb0_pullup,     // USB pullup control
    
    // USB PHY 1 - TARGET A/C (Shared PHY)
    inout  wire        usb1_dp,         // USB D+ (bidirectional)
    inout  wire        usb1_dn,         // USB D- (bidirectional)
    output wire        usb1_pullup,     // USB pullup control
    
    // USB PHY 2 - TARGET B (Dedicated)
    inout  wire        usb2_dp,         // USB D+ (bidirectional)
    inout  wire        usb2_dn,         // USB D- (bidirectional)
    output wire        usb2_pullup,     // USB pullup control
    
    // UART0 to SAMD51 (USB CDC-ACM bridge)
    input  wire        uart0_rx,        // UART receive from SAMD51
    output wire        uart0_tx,        // UART transmit to SAMD51
    
    // Status LEDs (Cynthion has 6 FPGA LEDs: 0-5)
    output wire [5:0]  led,             // Status LEDs
    
    // Debug Interface
    output wire [3:0]  debug            // Debug signals
);

    // Clock generation
    wire        clk;                // System clock (60 MHz)
    wire        clk_120mhz;         // 120MHz clock for fast path
    wire        clk_240mhz;         // 240MHz clock for PHY
    wire        pll_locked;         // PLL lock indicator
    wire        rst_n;              // Global reset (active low)
    
    // Output enable signals for USB PHYs
    wire usb0_dp_oe;        // USB0 D+ output enable
    wire usb0_dn_oe;        // USB0 D- output enable
    wire usb1_dp_oe;        // USB1 D+ output enable
    wire usb1_dn_oe;        // USB1 D- output enable
    wire usb2_dp_oe;        // USB2 D+ output enable
    wire usb2_dn_oe;        // USB2 D- output enable
    
    // USB PHY signals for the three interfaces
    // PHY 0 - Control
    wire [1:0]  phy0_line_state;    // USB0 line state
    wire [7:0]  phy0_rx_data;       // USB0 received data
    wire        phy0_rx_valid;      // USB0 data valid
    wire        phy0_rx_active;     // USB0 receiving
    wire        phy0_rx_error;      // USB0 error
    wire [7:0]  phy0_tx_data;       // USB0 transmit data
    wire        phy0_tx_valid;      // USB0 transmit valid
    wire        phy0_tx_ready;      // USB0 ready for transmit
    wire [1:0]  phy0_tx_op_mode;    // USB0 operation mode
    
    // PHY 1 - Target A/C
    wire [1:0]  phy1_line_state;    // USB1 line state
    wire [7:0]  phy1_rx_data;       // USB1 received data
    wire        phy1_rx_valid;      // USB1 data valid
    wire        phy1_rx_active;     // USB1 receiving
    wire        phy1_rx_error;      // USB1 error
    wire [7:0]  phy1_tx_data;       // USB1 transmit data
    wire        phy1_tx_valid;      // USB1 transmit valid
    wire        phy1_tx_ready;      // USB1 ready for transmit
    wire [1:0]  phy1_tx_op_mode;    // USB1 operation mode
    
    // PHY 2 - Target B
    wire [1:0]  phy2_line_state;    // USB2 line state
    wire [7:0]  phy2_rx_data;       // USB2 received data
    wire        phy2_rx_valid;      // USB2 data valid
    wire        phy2_rx_active;     // USB2 receiving
    wire        phy2_rx_error;      // USB2 error
    wire [7:0]  phy2_tx_data;       // USB2 transmit data
    wire        phy2_tx_valid;      // USB2 transmit valid
    wire        phy2_tx_ready;      // USB2 ready for transmit
    wire [1:0]  phy2_tx_op_mode;    // USB2 operation mode
    
    // PHY configuration
    wire [1:0]  phy0_speed_ctrl;    // USB0 speed select
    wire [1:0]  phy1_speed_ctrl;    // USB1 speed select
    wire [1:0]  phy2_speed_ctrl;    // USB2 speed select
    wire        phy0_reset;         // USB0 PHY reset
    wire        phy1_reset;         // USB1 PHY reset
    wire        phy2_reset;         // USB2 PHY reset
    
    // Protocol handler signals
    // Host side protocol
    wire [7:0]  host_decoded_data;  // Decoded data from host
    wire        host_decoded_valid; // Host data valid
    wire        host_decoded_sop;   // Start of host packet
    wire        host_decoded_eop;   // End of host packet
    wire [3:0]  host_pid;           // Host packet ID
    wire [6:0]  host_dev_addr;      // Device address from host
    wire [3:0]  host_endp;          // Endpoint from host
    wire        host_crc_valid;     // Host CRC valid
    
    // Device side protocol
    wire [7:0]  device_decoded_data;// Decoded data from device
    wire        device_decoded_valid;// Device data valid
    wire        device_decoded_sop; // Start of device packet
    wire        device_decoded_eop; // End of device packet
    wire [3:0]  device_pid;         // Device packet ID
    wire        device_crc_valid;   // Device CRC valid
    
    // Control protocol signals
    wire [7:0]  host_tx_data;       // Data to transmit to host
    wire        host_tx_valid;      // Data valid for host
    wire        host_tx_sop;        // Start of packet to host
    wire        host_tx_eop;        // End of packet to host
    wire [3:0]  host_tx_pid;        // PID to send to host
    
    wire [7:0]  device_tx_data;     // Data to transmit to device
    wire        device_tx_valid;    // Data valid for device
    wire        device_tx_sop;      // Start of packet to device
    wire        device_tx_eop;      // End of packet to device
    wire [3:0]  device_tx_pid;      // PID to send to device
    
    // Packet proxy signals
    wire [7:0]  packet_data;        // Packet data
    wire        packet_valid;       // Packet valid
    wire        packet_sop;         // Packet start
    wire        packet_eop;         // Packet end
    wire [3:0]  packet_pid;         // Packet ID
    wire        is_token_packet;    // Is token packet
    wire        is_data_packet;     // Is data packet
    
    // Buffer manager signals
    wire [7:0]  buffer_data;        // Data for buffer
    wire        buffer_valid;       // Buffer data valid
    wire [63:0] buffer_timestamp;   // Timestamp for buffer
    wire [7:0]  buffer_flags;       // Buffer flags
    wire        buffer_ready;       // Buffer ready
    wire [7:0]  read_data;          // Read data from buffer
    wire        read_valid;         // Read valid
    wire        read_req;           // Read request
    
    // Timestamp signals
    wire [63:0] timestamp;          // Current timestamp
    wire [31:0] timestamp_ms;       // Millisecond timestamp
    wire [15:0] sof_frame_num;      // SOF frame number
    wire        timestamp_valid;    // Timestamp valid
    
    // Control registers
    reg         proxy_enable;       // Enable proxy
    reg  [15:0] packet_filter_mask; // Packet filter
    reg         packet_filter_en;   // Enable filtering
    reg         modify_enable;      // Enable modification
    reg  [7:0]  modify_flags;       // Modification flags
    reg  [3:0]  resolution_ctrl;    // Timestamp resolution
    
    // Status signals
    wire        buffer_overflow;    // Buffer overflow
    wire        buffer_underflow;   // Buffer underflow
    wire [15:0] buffer_used;        // Buffer usage
    wire [31:0] packet_count;       // Packet count
    wire [15:0] error_count;        // Error counter
    
    // Control bus
    reg  [7:0]  control_reg_addr;   // Control register address
    reg  [7:0]  control_reg_data;   // Control register data
    reg         control_reg_write;  // Control register write
    
    // Debug interface signals
    wire [7:0]  debug_cmd;          // Debug command input
    wire        debug_cmd_valid;    // Debug command valid
    wire [7:0]  debug_resp;         // Debug response output
    wire        debug_resp_valid;   // Debug response valid
    wire [7:0]  debug_leds;         // Debug LED outputs
    wire [7:0]  debug_probe;        // Debug probe outputs
    wire        force_reset;        // Force system reset
    
    // UART0 interface signals (to SAMD51)
    wire [7:0]  uart_tx_data;       // UART transmit data
    wire        uart_tx_valid;      // UART transmit valid
    wire        uart_tx_ready;      // UART ready for data
    wire [7:0]  uart_rx_data;       // UART received data
    wire        uart_rx_valid;      // UART receive valid
    wire        uart_rx_ready;      // UART ready to accept
    wire        uart_tx_busy;       // UART transmitter busy
    wire        uart_rx_error;      // UART receiver error
    wire [7:0]  uart_tx_fifo_used;  // TX FIFO occupancy
    wire [7:0]  uart_rx_fifo_used;  // RX FIFO occupancy
    
    // PHY monitoring
    wire        event_valid;        // PHY event valid
    wire [7:0]  event_type;         // PHY event type
    wire [63:0] event_timestamp;    // PHY event timestamp
    
    // Connection status
    wire        host_conn_detect;   // Host connection detected
    wire [1:0]  host_conn_speed;    // Host connection speed
    wire        device_conn_detect; // Device connection detected
    wire [1:0]  device_conn_speed;  // Device connection speed
    
    // USB Host Mode Signals
    // Reset Controller
    wire        host_mode_enable;       // Enable USB host mode
    wire        bus_reset_req;          // Request bus reset
    wire        reset_active;           // Reset in progress
    wire [1:0]  detected_speed;         // Detected device speed (00=LS, 01=FS, 10=HS)
    wire        reset_done;             // Reset complete
    
    // Token Generator
    wire        token_start;            // Start token generation
    wire [1:0]  token_type;             // Token type (00=OUT, 01=IN, 10=SETUP, 11=SOF)
    wire [6:0]  token_addr;             // Device address
    wire [3:0]  token_endp;             // Endpoint number
    wire [7:0]  token_data_out;         // Token data to PHY
    wire        token_data_valid;       // Token data valid
    wire        token_ready;            // Token generator ready
    wire        token_done;             // Token generation complete
    
    // SOF Generator
    wire        sof_enable;             // Enable SOF generation
    wire        sof_trigger;            // SOF trigger output
    wire [10:0] sof_frame_number;       // Current frame number
    wire        sof_start;              // Start SOF packet
    wire [7:0]  sof_data_out;           // SOF data to PHY
    wire        sof_data_valid;         // SOF data valid
    wire        sof_done;               // SOF generation complete
    
    // Transaction Engine
    wire        trans_start;            // Start transaction
    wire [1:0]  trans_type;             // Transaction type (00=SETUP, 01=IN, 10=OUT)
    wire [6:0]  trans_addr;             // Transaction device address
    wire [3:0]  trans_endp;             // Transaction endpoint
    wire        trans_data_pid;         // Data PID (0=DATA0, 1=DATA1)
    wire [9:0]  trans_data_len;         // Data length
    wire [7:0]  trans_data_in;          // Data input for OUT/SETUP
    wire        trans_data_in_valid;    // Data input valid
    wire        trans_data_in_ready;    // Ready for data input
    wire [7:0]  trans_data_out;         // Data output for IN
    wire        trans_data_out_valid;   // Data output valid
    wire        trans_data_out_ready;   // Ready to accept data output
    wire        trans_done;             // Transaction complete
    wire [2:0]  trans_result;           // Transaction result (ACK/NAK/STALL/etc)
    
    // USB Enumerator
    wire        enum_start;             // Start enumeration
    wire        enum_done;              // Enumeration complete
    wire        enum_error;             // Enumeration error
    wire [7:0]  enum_error_code;        // Error code
    wire [6:0]  enum_device_addr;       // Assigned device address
    wire [7:0]  enum_config_num;        // Configuration number to select
    wire [15:0] enum_vendor_id;         // Device vendor ID
    wire [15:0] enum_product_id;        // Device product ID
    wire [7:0]  enum_max_packet_size;   // Max packet size for EP0
    wire [7:0]  enum_num_configs;       // Number of configurations
    wire [7:0]  enum_interface_num;     // HID interface number
    wire [7:0]  enum_config_desc_out;   // Config descriptor output
    wire        enum_config_desc_valid; // Config descriptor valid
    wire        enum_config_desc_done;  // Config descriptor complete
    
    // Descriptor Parser
    wire        parser_desc_in_valid;   // Descriptor input valid
    wire [7:0]  parser_desc_in;         // Descriptor input data
    wire        parser_desc_done;       // Parsing complete
    wire        parser_enable;          // Enable parser
    wire        parser_done;            // Parser done
    wire [7:0]  parser_num_endpoints;   // Number of endpoints found
    wire [6:0]  parser_ep_addr;         // Endpoint address
    wire [1:0]  parser_ep_type;         // Endpoint type
    wire [10:0] parser_ep_max_packet;   // Endpoint max packet size
    wire [7:0]  parser_ep_interval;     // Endpoint polling interval
    wire [7:0]  parser_iface_protocol;  // Interface protocol (0x01=kbd, 0x02=mouse)
    wire [7:0]  parser_iface_number;    // Interface number
    wire        parser_ep_valid;        // Endpoint info valid
    
    // HID Keyboard Engine
    wire        kbd_enable;             // Enable keyboard polling
    wire [6:0]  kbd_device_addr;        // Keyboard device address
    wire [3:0]  kbd_endpoint;           // Keyboard interrupt endpoint
    wire [10:0] kbd_max_packet_size;    // Endpoint max packet size
    wire [7:0]  kbd_poll_interval;      // Polling interval (ms)
    wire [511:0] kbd_report_data;       // Keyboard report (up to 64 bytes)
    wire        kbd_report_valid;       // New report available
    wire [6:0]  kbd_report_length;      // Actual report length
    wire        kbd_active;             // Keyboard actively polling
    wire        kbd_error;              // Keyboard error
    wire [7:0]  kbd_error_code;         // Error code
    
    // HID Mouse Engine
    wire        mouse_enable;           // Enable mouse polling
    wire [6:0]  mouse_device_addr;      // Mouse device address
    wire [3:0]  mouse_endpoint;         // Mouse interrupt endpoint
    wire [10:0] mouse_max_packet_size;  // Endpoint max packet size
    wire [7:0]  mouse_poll_interval;    // Polling interval (ms)
    wire [511:0] mouse_report_data;     // Mouse report (up to 64 bytes)
    wire        mouse_report_valid;     // New report available
    wire [6:0]  mouse_report_length;    // Actual report length
    wire [7:0]  mouse_button_state;     // Button states
    wire signed [7:0] mouse_delta_x;    // X movement
    
    // Disconnect Detector
    wire        disconnect_enable;      // Enable disconnect detection
    wire        device_connected;       // Device connection status
    wire        disconnect_detected;    // Disconnect event detected
    wire signed [7:0] mouse_delta_y;    // Y movement
    wire signed [7:0] mouse_wheel_delta; // Wheel scroll
    wire        mouse_active;           // Mouse actively polling
    wire        mouse_error;            // Mouse error
    wire [7:0]  mouse_error_code;       // Error code
    
    // USB Host Control Registers
    reg         host_mode_enable_reg;   // Host mode enable register
    reg         enum_start_reg;         // Start enumeration register
    reg  [6:0]  target_device_addr;     // Target device address for enumeration
    reg  [7:0]  target_config_num;      // Target configuration number
    
    // Reset logic
    reg [3:0]   reset_sync;         // Reset synchronizer
    wire        system_rst_n;       // System reset with debug force
    
    // PLL for clock generation
    pll_60_to_240 pll_inst (
        .clkin(clk_60mhz),
        .clkout0(clk),          // 60MHz
        .clkout1(clk_120mhz),   // 120MHz
        .clkout2(clk_240mhz),   // 240MHz
        .locked(pll_locked)
    );
    
    // Reset synchronization
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            reset_sync <= 4'b0000;
        end else begin
            reset_sync <= {reset_sync[2:0], 1'b1};
        end
    end
    
    // Global reset signal
    assign system_rst_n = reset_sync[3] & pll_locked;
    assign rst_n = system_rst_n & ~force_reset;  // Add debug forced reset
    
    // USB PHY 0 - CONTROL (Internal MCU Access)
    usb_phy_wrapper phy0 (
        .clk(clk),
        .clk_480mhz(clk_240mhz), // Using 240MHz as the nearest available
        .rst_n(rst_n),
        
        // PHY pins
        .usb_dp_i(usb0_dp),
        .usb_dn_i(usb0_dn),
        .usb_dp_o(usb0_dp),
        .usb_dn_o(usb0_dn),
        .usb_dp_oe(usb0_dp_oe),
        .usb_dn_oe(usb0_dn_oe),
        .usb_pullup_en(usb0_pullup),
        
        // UTMI interface
        .utmi_line_state(phy0_line_state),
        .utmi_rx_data(phy0_rx_data),
        .utmi_rx_valid(phy0_rx_valid),
        .utmi_rx_active(phy0_rx_active),
        .utmi_rx_error(phy0_rx_error),
        .utmi_tx_data(phy0_tx_data),
        .utmi_tx_valid(phy0_tx_valid),
        .utmi_tx_ready(phy0_tx_ready),
        .utmi_tx_op_mode(phy0_tx_op_mode),
        .utmi_xcvr_select(2'b01), // Default to full-speed
        .utmi_termselect(1'b1),
        .utmi_dppulldown(1'b0),
        .utmi_dmpulldown(1'b0),
        
        // PHY monitoring
        .phy_line_state(),
        .phy_rx_carrier(),
        .phy_rx_clock(),
        
        // Control
        .usb_speed_ctrl(phy0_speed_ctrl),
        .phy_reset(phy0_reset),
        .phy_status()
    );
    
    // USB PHY 1 - TARGET A/C (Shared PHY)
    usb_phy_wrapper phy1 (
        .clk(clk),
        .clk_480mhz(clk_240mhz),
        .rst_n(rst_n),
        
        // PHY pins
        .usb_dp_i(usb1_dp),
        .usb_dn_i(usb1_dn),
        .usb_dp_o(usb1_dp),
        .usb_dn_o(usb1_dn),
        .usb_dp_oe(usb1_dp_oe),
        .usb_dn_oe(usb1_dn_oe),
        .usb_pullup_en(usb1_pullup),
        
        // UTMI interface
        .utmi_line_state(phy1_line_state),
        .utmi_rx_data(phy1_rx_data),
        .utmi_rx_valid(phy1_rx_valid),
        .utmi_rx_active(phy1_rx_active),
        .utmi_rx_error(phy1_rx_error),
        .utmi_tx_data(phy1_tx_data),
        .utmi_tx_valid(phy1_tx_valid),
        .utmi_tx_ready(phy1_tx_ready),
        .utmi_tx_op_mode(phy1_tx_op_mode),
        .utmi_xcvr_select(2'b01),
        .utmi_termselect(1'b1),
        .utmi_dppulldown(1'b0),
        .utmi_dmpulldown(1'b0),
        
        // PHY monitoring
        .phy_line_state(),
        .phy_rx_carrier(),
        .phy_rx_clock(),
        
        // Control
        .usb_speed_ctrl(phy1_speed_ctrl),
        .phy_reset(phy1_reset),
        .phy_status()
    );
    
    // USB PHY 2 - TARGET B (Dedicated)
    usb_phy_wrapper phy2 (
        .clk(clk),
        .clk_480mhz(clk_240mhz),
        .rst_n(rst_n),
        
        // PHY pins
        .usb_dp_i(usb2_dp),
        .usb_dn_i(usb2_dn),
        .usb_dp_o(usb2_dp),
        .usb_dn_o(usb2_dn),
        .usb_dp_oe(usb2_dp_oe),
        .usb_dn_oe(usb2_dn_oe),
        .usb_pullup_en(usb2_pullup),
        
        // UTMI interface
        .utmi_line_state(phy2_line_state),
        .utmi_rx_data(phy2_rx_data),
        .utmi_rx_valid(phy2_rx_valid),
        .utmi_rx_active(phy2_rx_active),
        .utmi_rx_error(phy2_rx_error),
        .utmi_tx_data(phy2_tx_data),
        .utmi_tx_valid(phy2_tx_valid),
        .utmi_tx_ready(phy2_tx_ready),
        .utmi_tx_op_mode(phy2_tx_op_mode),
        .utmi_xcvr_select(2'b01),
        .utmi_termselect(1'b1),
        .utmi_dppulldown(1'b0),
        .utmi_dmpulldown(1'b0),
        
        // PHY monitoring
        .phy_line_state(),
        .phy_rx_carrier(),
        .phy_rx_clock(),
        
        // Control
        .usb_speed_ctrl(phy2_speed_ctrl),
        .phy_reset(phy2_reset),
        .phy_status()
    );
    
    // USB protocol handler for device side (PHY1)
    usb_protocol_handler device_protocol (
        .clk(clk),
        .rst_n(rst_n),
        
        // UTMI Interface
        .utmi_rx_data(phy1_rx_data),
        .utmi_rx_valid(phy1_rx_valid),
        .utmi_rx_active(phy1_rx_active),
        .utmi_rx_error(phy1_rx_error),
        .utmi_line_state(phy1_line_state),
        .utmi_tx_data(phy1_tx_data),
        .utmi_tx_valid(phy1_tx_valid),
        .utmi_tx_ready(phy1_tx_ready),
        .utmi_tx_op_mode(phy1_tx_op_mode),
        .utmi_xcvr_select(phy1_speed_ctrl),
        .utmi_termselect(),
        .utmi_dppulldown(),
        .utmi_dmpulldown(),
        
        // Protocol Interface
        .packet_data(device_decoded_data),
        .packet_valid(device_decoded_valid),
        .packet_sop(device_decoded_sop),
        .packet_eop(device_decoded_eop),
        .pid(device_pid),
        .dev_addr(),
        .endp(),
        .crc_valid(device_crc_valid),
        
        // Transmit Interface
        .tx_packet_data(device_tx_data),
        .tx_packet_valid(device_tx_valid),
        .tx_packet_sop(device_tx_sop),
        .tx_packet_eop(device_tx_eop),
        .tx_packet_ready(),
        .tx_pid(device_tx_pid),
        
        // Configuration
        .device_address(7'h01),  // Default device address
        .usb_speed(phy1_speed_ctrl),
        .conn_detect(device_conn_detect),
        .conn_speed(device_conn_speed),
        .reset_detect(),
        .suspend_detect(),
        .resume_detect()
    );
    
    // USB protocol handler for host side (PHY2)
    usb_protocol_handler host_protocol (
        .clk(clk),
        .rst_n(rst_n),
        
        // UTMI Interface
        .utmi_rx_data(phy2_rx_data),
        .utmi_rx_valid(phy2_rx_valid),
        .utmi_rx_active(phy2_rx_active),
        .utmi_rx_error(phy2_rx_error),
        .utmi_line_state(phy2_line_state),
        .utmi_tx_data(phy2_tx_data),
        .utmi_tx_valid(phy2_tx_valid),
        .utmi_tx_ready(phy2_tx_ready),
        .utmi_tx_op_mode(phy2_tx_op_mode),
        .utmi_xcvr_select(phy2_speed_ctrl),
        .utmi_termselect(),
        .utmi_dppulldown(),
        .utmi_dmpulldown(),
        
        // Protocol Interface
        .packet_data(host_decoded_data),
        .packet_valid(host_decoded_valid),
        .packet_sop(host_decoded_sop),
        .packet_eop(host_decoded_eop),
        .pid(host_pid),
        .dev_addr(host_dev_addr),
        .endp(host_endp),
        .crc_valid(host_crc_valid),
        
        // Transmit Interface
        .tx_packet_data(host_tx_data),
        .tx_packet_valid(host_tx_valid),
        .tx_packet_sop(host_tx_sop),
        .tx_packet_eop(host_tx_eop),
        .tx_packet_ready(),
        .tx_pid(host_tx_pid),
        
        // Configuration
        .device_address(7'h00),  // Host doesn't need a device address
        .usb_speed(phy2_speed_ctrl),
        .conn_detect(host_conn_detect),
        .conn_speed(host_conn_speed),
        .reset_detect(),
        .suspend_detect(),
        .resume_detect()
    );
    
    // =======================================================================
    // USB HOST MODE COMPONENTS
    // =======================================================================
    
    // USB Reset Controller - Handles bus reset with speed detection
    usb_reset_controller reset_ctrl (
        .clk(clk),
        .rst_n(rst_n),
        
        // Control Interface
        .bus_reset_req(bus_reset_req),
        .reset_active(reset_active),
        .detected_speed(detected_speed),
        .reset_done(reset_done),
        
        // UTMI Interface (connected to PHY2 for host operations)
        .utmi_line_state(phy2_line_state),
        .utmi_tx_data(phy2_tx_data),
        .utmi_tx_valid(phy2_tx_valid),
        .utmi_tx_ready(phy2_tx_ready),
        .utmi_tx_op_mode(phy2_tx_op_mode)
    );
    
    // USB Disconnect Detector - Monitors line state for device disconnect/connect
    usb_disconnect_detector disconnect_det (
        .clk(clk),
        .reset(~rst_n),
        
        // USB line state from PHY2 (host port)
        .line_state(phy2_line_state),
        
        // Configuration
        .enable(disconnect_enable),
        .high_speed(detected_speed == 2'b10),  // High-speed if detected_speed is 10
        
        // Status output
        .device_connected(device_connected),
        .disconnect_detected(disconnect_detected)
    );
    
    // USB Token Generator - Generates USB token packets
    usb_token_generator token_gen (
        .clk(clk),
        .rst_n(rst_n),
        
        // Control Interface
        .token_start(token_start),
        .token_type(token_type),
        .token_addr(token_addr),
        .token_endp(token_endp),
        .token_ready(token_ready),
        .token_done(token_done),
        
        // Output Interface
        .token_data(token_data_out),
        .token_valid(token_data_valid)
    );
    
    // USB SOF Generator - Generates Start-of-Frame packets
    usb_sof_generator sof_gen (
        .clk(clk),
        .rst_n(rst_n),
        
        // Control Interface
        .sof_enable(sof_enable),
        .usb_speed(detected_speed),
        
        // SOF Outputs
        .sof_trigger(sof_trigger),
        .frame_number(sof_frame_number),
        .sof_start(sof_start),
        .sof_data(sof_data_out),
        .sof_valid(sof_data_valid),
        .sof_done(sof_done)
    );
    
    // USB Transaction Engine - Handles SETUP/IN/OUT transactions
    usb_transaction_engine trans_engine (
        .clk(clk),
        .rst_n(rst_n),
        
        // Control Interface
        .trans_start(trans_start),
        .trans_type(trans_type),
        .trans_addr(trans_addr),
        .trans_endp(trans_endp),
        .trans_data_pid(trans_data_pid),
        .trans_data_len(trans_data_len),
        .trans_done(trans_done),
        .trans_result(trans_result),
        
        // Data Interfaces
        .data_in(trans_data_in),
        .data_in_valid(trans_data_in_valid),
        .data_in_ready(trans_data_in_ready),
        .data_out(trans_data_out),
        .data_out_valid(trans_data_out_valid),
        .data_out_ready(trans_data_out_ready),
        
        // UTMI Interface (connected to PHY2 for host operations)
        .utmi_rx_data(phy2_rx_data),
        .utmi_rx_valid(phy2_rx_valid),
        .utmi_rx_active(phy2_rx_active),
        .utmi_tx_data(phy2_tx_data),
        .utmi_tx_valid(phy2_tx_valid),
        .utmi_tx_ready(phy2_tx_ready),
        
        // Token Generator Interface
        .token_start(token_start),
        .token_type(token_type),
        .token_addr(token_addr),
        .token_endp(token_endp),
        .token_ready(token_ready),
        .token_done(token_done)
    );
    
    // USB Descriptor Parser - Parses configuration descriptors
    usb_descriptor_parser desc_parser (
        .clk(clk),
        .rst_n(rst_n),
        
        // Control Interface
        .enable(parser_enable),
        .done(parser_done),
        .valid(parser_ep_valid),
        
        // Descriptor Input Stream
        .desc_data(parser_desc_in),
        .desc_valid(parser_desc_in_valid),
        .desc_ready(),  // Not used
        
        // Filter Configuration
        .filter_class(8'h03),              // HID class
        .filter_subclass(8'hFF),           // Any subclass
        .filter_protocol(8'hFF),           // Any protocol
        .filter_transfer_type(2'b11),      // Interrupt transfer
        .filter_direction(1'b1),           // IN endpoint
        
        // Extracted Endpoint Information
        .endp_number(parser_ep_addr[3:0]),
        .endp_direction(),                 // Always IN for our filter
        .endp_type(parser_ep_type),
        .endp_max_packet(parser_ep_max_packet),
        .endp_interval(parser_ep_interval),
        .iface_protocol_out(parser_iface_protocol),
        .iface_number_out(parser_iface_number)
    );
    
    // USB Enumerator - Orchestrates device enumeration
    usb_enumerator enumerator (
        .clk(clk),
        .rst_n(rst_n),
        
        // Control Interface
        .start_enum(enum_start),
        .enum_done(enum_done),
        .enum_error(enum_error),
        .error_code(enum_error_code),
        
        // Configuration
        .device_addr(enum_device_addr),
        .config_number(enum_config_num),
        
        // Reset Controller Interface
        .bus_reset_req(bus_reset_req),
        .reset_active(reset_active),
        .detected_speed(detected_speed),
        
        // Token Generator Interface
        .token_start(token_start),
        .token_type(token_type),
        .token_addr(token_addr),
        .token_endp(token_endp),
        .token_ready(token_ready),
        .token_done(token_done),
        
        // UTMI Interfaces
        .utmi_rx_data(phy2_rx_data),
        .utmi_rx_valid(phy2_rx_valid),
        .utmi_rx_active(phy2_rx_active),
        .utmi_tx_data(phy2_tx_data),
        .utmi_tx_valid(phy2_tx_valid),
        .utmi_tx_ready(phy2_tx_ready),
        
        // Descriptor Parser Interface
        .parser_enable(parser_enable),
        .parser_done(parser_done),
        .parser_valid(parser_ep_valid),
        .parser_data(parser_desc_in),
        .parser_data_valid(parser_desc_in_valid),
        
        // Device Information Outputs
        .max_packet_size(enum_max_packet_size),
        .device_speed(),
        .vendor_id(enum_vendor_id),
        .product_id(enum_product_id),
        .interface_num(enum_interface_num),
        
        // SOF Counter
        .sof_count(sof_frame_num[10:0])
    );
    
    // Connect descriptor parser to enumerator output
    assign parser_desc_in = enum_config_desc_out;
    assign parser_desc_in_valid = enum_config_desc_valid;
    assign parser_desc_done = enum_config_desc_done;
    
    // USB HID Keyboard Engine - Polls keyboard interrupt endpoint
    usb_hid_keyboard_engine kbd_engine (
        .clk(clk),
        .rst_n(rst_n),
        
        // Control Interface
        .enable(kbd_enable),
        .enumerated(enum_done),
        
        // Device Information (from enumerator/parser)
        .device_addr(kbd_device_addr),
        .endp_number(kbd_endpoint),
        .max_packet_size(kbd_max_packet_size[7:0]),
        .device_speed(2'b01),  // Full speed
        .poll_interval(kbd_poll_interval),
        
        // Token Generator Interface  
        .token_start(token_start),
        .token_type(token_type),
        .token_addr(token_addr),
        .token_endp(token_endp),
        .token_ready(token_ready),
        .token_done(token_done),
        
        // UTMI Receive Interface
        .utmi_rx_data(phy2_rx_data),
        .utmi_rx_valid(phy2_rx_valid),
        .utmi_rx_active(phy2_rx_active),
        .utmi_rx_pid(phy2_rx_pid),
        
        // SOF Interface
        .sof_trigger(sof_trigger),
        .frame_number(sof_frame_num[10:0]),
        
        // Keyboard Report Output
        .report_valid(kbd_report_valid),
        .report_data(kbd_report_data),
        .report_length(kbd_report_length),
        
        // Decoded Boot Protocol Fields (backward compatibility)
        .report_modifiers(),  // Can connect if needed
        .report_key0(),
        .report_key1(),
        .report_key2(),
        .report_key3(),
        .report_key4(),
        .report_key5(),
        
        // Status
        .status(),
        .poll_count()
    );
    
    // USB HID Mouse Engine - Polls mouse interrupt endpoint
    usb_hid_mouse_engine mouse_engine (
        .clk(clk),
        .rst_n(rst_n),
        
        // Control Interface
        .enable(mouse_enable),
        .device_addr(mouse_device_addr),
        .endpoint(mouse_endpoint),
        .max_packet_size(mouse_max_packet_size),
        .poll_interval(mouse_poll_interval),
        .device_speed(detected_speed),
        
        // Mouse Report Output
        .report_data(mouse_report_data),
        .report_valid(mouse_report_valid),
        .report_length(mouse_report_length),
        
        // Decoded Mouse Data (boot protocol compatibility)
        .button_state(mouse_button_state),
        .delta_x(mouse_delta_x),
        .delta_y(mouse_delta_y),
        .wheel_delta(mouse_wheel_delta),
        
        // Status
        .active(mouse_active),
        .error(mouse_error),
        .error_code(mouse_error_code),
        
        // Transaction Engine Interface
        .trans_start(trans_start),
        .trans_done(trans_done),
        .trans_result(trans_result),
        .trans_addr(trans_addr),
        .trans_endp(trans_endp),
        .trans_data_pid(trans_data_pid),
        .trans_data_out(trans_data_out),
        .trans_data_out_valid(trans_data_out_valid),
        .trans_data_out_ready(trans_data_out_ready)
    );
    
    // =======================================================================
    // END USB HOST MODE COMPONENTS
    // =======================================================================
    
    // USB monitor/proxy logic
    usb_monitor monitor (
        .clk(clk),
        .clk_120mhz(clk_120mhz),
        .rst_n(rst_n),
        
        // Host Side Interface
        .host_rx_data(host_decoded_data),
        .host_rx_valid(host_decoded_valid),
        .host_rx_sop(host_decoded_sop),
        .host_rx_eop(host_decoded_eop),
        .host_rx_pid(host_pid),
        .host_rx_dev_addr(host_dev_addr),
        .host_rx_endp(host_endp),
        .host_rx_crc_valid(host_crc_valid),
        .host_tx_data(host_tx_data),
        .host_tx_valid(host_tx_valid),
        .host_tx_sop(host_tx_sop),
        .host_tx_eop(host_tx_eop),
        .host_tx_pid(host_tx_pid),
        
        // Device Side Interface
        .device_rx_data(device_decoded_data),
        .device_rx_valid(device_decoded_valid),
        .device_rx_sop(device_decoded_sop),
        .device_rx_eop(device_decoded_eop),
        .device_rx_pid(device_pid),
        .device_rx_crc_valid(device_crc_valid),
        .device_tx_data(device_tx_data),
        .device_tx_valid(device_tx_valid),
        .device_tx_sop(device_tx_sop),
        .device_tx_eop(device_tx_eop),
        .device_tx_pid(device_tx_pid),
        
        // Buffer Manager Interface
        .buffer_data(buffer_data),
        .buffer_valid(buffer_valid),
        .buffer_timestamp(buffer_timestamp),
        .buffer_flags(buffer_flags),
        .buffer_ready(buffer_ready),
        
        // Timestamp Interface
        .timestamp(timestamp),
        
        // PHY State Monitor Interface
        .host_line_state(phy2_line_state),
        .device_line_state(phy1_line_state),
        .event_valid(event_valid),
        .event_type(event_type),
        
        // Control Interface
        .control_reg_addr(control_reg_addr),
        .control_reg_data(control_reg_data),
        .control_reg_write(control_reg_write),
        .status_register(),
        
        // Configuration
        .proxy_enable(proxy_enable),
        .packet_filter_en(packet_filter_en),
        .packet_filter_mask(packet_filter_mask),
        .modify_enable(modify_enable),
        .addr_translate_en(8'h00),  // Changed from 1'b0 to 8-bit value
        .addr_translate_from(7'h00),
        .addr_translate_to(7'h00)
    );
    
    // Packet forwarding with inspection
    packet_proxy proxy (
        .clk(clk),
        .clk_120mhz(clk_120mhz),
        .rst_n(rst_n),
        
        // Host Controller Interface
        .host_rx_data(host_decoded_data),
        .host_rx_valid(host_decoded_valid),
        .host_rx_sop(host_decoded_sop),
        .host_rx_eop(host_decoded_eop),
        .host_tx_data(),
        .host_tx_valid(),
        .host_tx_sop(),
        .host_tx_eop(),
        
        // Device Controller Interface
        .device_rx_data(device_decoded_data),
        .device_rx_valid(device_decoded_valid),
        .device_rx_sop(device_decoded_sop),
        .device_rx_eop(device_decoded_eop),
        .device_tx_data(),
        .device_tx_valid(),
        .device_tx_sop(),
        .device_tx_eop(),
        
        // Buffer Manager Interface
        .buffer_data(packet_data),
        .buffer_valid(packet_valid),
        .buffer_timestamp(timestamp),
        .buffer_flags(),
        .buffer_ready(buffer_ready),
        
        // Timestamp Generator Interface
        .timestamp(timestamp),
        
        // Protocol Identification
        .packet_pid(packet_pid),
        .is_token_packet(is_token_packet),
        .is_data_packet(is_data_packet),
        .device_addr(),
        .endpoint_num(),
        
        // Control Interface
        .control_reg_addr(control_reg_addr),
        .control_reg_data(control_reg_data),
        .control_reg_write(control_reg_write),
        
        // Configuration
        .enable_proxy(proxy_enable),
        .enable_logging(1'b1),
        .enable_filtering(packet_filter_en),
        .packet_filter(packet_filter_mask),
        .enable_modify(modify_enable),
        .modify_flags(modify_flags)
    );
    
    // Ring buffer implementation
    buffer_manager buffer (
        .clk(clk),
        .rst_n(rst_n),
        
        // Write Interface
        .write_data(buffer_data),
        .write_valid(buffer_valid),
        .write_timestamp(buffer_timestamp),
        .write_flags(buffer_flags),
        .write_ready(buffer_ready),
        
        // Read Interface
        .read_data(read_data),
        .read_valid(read_valid),
        .read_req(read_req),
        .read_timestamp(),
        .read_flags(),
        .read_packet_start(),
        .read_packet_end(),
        
        // Control Interface
        .buffer_clear(1'b0),
        .high_watermark(16'h7000),  // 28KB high watermark
        .low_watermark(16'h1000),   // 4KB low watermark
        
        // Status Interface
        .buffer_used(buffer_used),
        .buffer_free(),
        .buffer_empty(),
        .buffer_full(),
        .buffer_overflow(buffer_overflow),
        .buffer_underflow(buffer_underflow),
        .packet_count(packet_count),
        
        // Configuration
        .enable_overflow_protection(1'b1),
        .buffer_mode(2'b01)  // Separate buffers for each direction
    );
    
    // Timestamp generator
    timestamp_generator timestamper (
        .clk(clk),
        .clk_high(clk_240mhz),
        .rst_n(rst_n),
        
        // Timestamp Outputs
        .timestamp(timestamp),
        .timestamp_ms(timestamp_ms),
        .sof_frame_num(sof_frame_num),
        
        // Synchronization
        .sync_enable(1'b0),
        .sync_pulse(1'b0),
        .sync_value(64'h0),
        
        // USB Frame Sync
        .sof_detected(host_pid == 4'b0101),  // SOF PID
        .sof_frame_num_in(11'h000),  // From SOF packet
        
        // Configuration
        .resolution_ctrl(resolution_ctrl),  // Configurable resolution
        .counter_enable(1'b1),
        .reset_counter(1'b0),
        
        // Status
        .timestamp_valid(timestamp_valid),
        .timestamp_rate()
    );
    
    // Initial configuration (would normally come from control interface)
    initial begin
        proxy_enable = 1'b1;
        packet_filter_mask = 16'h0000;  // No filtering initially
        packet_filter_en = 1'b0;
        modify_enable = 1'b0;
        modify_flags = 8'h00;
        resolution_ctrl = 4'h0;  // Full 60MHz resolution
        
        // USB Host Mode Configuration
        host_mode_enable_reg = 1'b0;  // Start with host mode disabled
        enum_start_reg = 1'b0;
        target_device_addr = 7'd1;    // Assign address 1 to enumerated device
        target_config_num = 8'd1;     // Select first configuration
    end
    
    // USB Host Mode Control Logic
    assign host_mode_enable = host_mode_enable_reg;
    assign enum_start = enum_start_reg;
    assign enum_device_addr = target_device_addr;
    assign enum_config_num = target_config_num;
    assign sof_enable = host_mode_enable & enum_done;  // Enable SOF after enumeration
    assign disconnect_enable = host_mode_enable;       // Enable disconnect detection when host mode active
    
    // Auto-reset and re-enumeration on disconnect
    reg prev_disconnect;
    reg auto_enum_trigger;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_disconnect <= 1'b0;
            auto_enum_trigger <= 1'b0;
        end else begin
            prev_disconnect <= disconnect_detected;
            
            // Trigger enumeration when device connects (after disconnect or initial connect)
            if (device_connected && !prev_disconnect && host_mode_enable && !enum_done) begin
                auto_enum_trigger <= 1'b1;
            end else if (enum_done || !device_connected) begin
                auto_enum_trigger <= 1'b0;
            end
        end
    end
    
    // Automatic keyboard and mouse engine startup after enumeration
    reg kbd_enable_reg;
    reg [6:0] kbd_addr_reg;
    reg [3:0] kbd_endp_reg;
    reg [10:0] kbd_max_pkt_reg;
    reg [7:0] kbd_interval_reg;
    
    reg mouse_enable_reg;
    reg [6:0] mouse_addr_reg;
    reg [3:0] mouse_endp_reg;
    reg [10:0] mouse_max_pkt_reg;
    reg [7:0] mouse_interval_reg;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            kbd_enable_reg <= 1'b0;
            kbd_addr_reg <= 7'd0;
            kbd_endp_reg <= 4'd0;
            kbd_max_pkt_reg <= 11'd0;
            kbd_interval_reg <= 8'd0;
            mouse_enable_reg <= 1'b0;
            mouse_addr_reg <= 7'd0;
            mouse_endp_reg <= 4'd0;
            mouse_max_pkt_reg <= 11'd0;
            mouse_interval_reg <= 8'd0;
        end else begin
            // When enumeration completes and we find an endpoint, enable the appropriate engine
            if (enum_done && parser_ep_valid) begin
                // Check protocol: 0x01 = keyboard, 0x02 = mouse
                if (parser_iface_protocol == 8'h01) begin
                    // Keyboard detected
                    kbd_enable_reg <= 1'b1;
                    kbd_addr_reg <= enum_device_addr;
                    kbd_endp_reg <= parser_ep_addr[3:0];
                    kbd_max_pkt_reg <= parser_ep_max_packet;
                    kbd_interval_reg <= parser_ep_interval;
                end
                else if (parser_iface_protocol == 8'h02) begin
                    // Mouse detected
                    mouse_enable_reg <= 1'b1;
                    mouse_addr_reg <= enum_device_addr;
                    mouse_endp_reg <= parser_ep_addr[3:0];
                    mouse_max_pkt_reg <= parser_ep_max_packet;
                    mouse_interval_reg <= parser_ep_interval;
                end
            end
            // Disable on reset, enumeration start, or disconnect
            else if (enum_start_reg || bus_reset_req || disconnect_detected) begin
                kbd_enable_reg <= 1'b0;
                mouse_enable_reg <= 1'b0;
            end
        end
    end
    
    assign kbd_enable = kbd_enable_reg;
    assign kbd_device_addr = kbd_addr_reg;
    assign kbd_endpoint = kbd_endp_reg;
    assign kbd_max_packet_size = kbd_max_pkt_reg;
    assign kbd_poll_interval = kbd_interval_reg;
    
    assign mouse_enable = mouse_enable_reg;
    assign mouse_device_addr = mouse_addr_reg;
    assign mouse_endpoint = mouse_endp_reg;
    assign mouse_max_packet_size = mouse_max_pkt_reg;
    assign mouse_poll_interval = mouse_interval_reg;
    
    // =======================================================================
    // UART0 Interface to SAMD51 (USB CDC-ACM Bridge)
    // =======================================================================
    // This provides UART0→SAMD51→USB connectivity, eliminating the need for
    // external UART adapters. The SAMD51 Apollo firmware bridges this to
    // USB CDC-ACM, appearing as /dev/ttyACM0 (Linux) or COM port (Windows).
    
    // Injection interface signals
    wire [63:0] inject_kbd_report;
    wire        inject_kbd_valid;
    wire        inject_kbd_ack;
    wire [39:0] inject_mouse_report;
    wire        inject_mouse_valid;
    wire        inject_mouse_ack;
    wire [31:0] filter_mask;
    wire        mode_proxy_uart;
    wire        mode_host_uart;
    
    // Merged HID reports (after injection)
    wire [63:0] merged_kbd_report;
    wire        merged_kbd_valid;
    wire [39:0] merged_mouse_report;
    wire        merged_mouse_valid;
    
    uart_interface #(
        .CLK_FREQ(60_000_000),
        .BAUD_RATE(115200),
        .TX_FIFO_DEPTH(256),
        .RX_FIFO_DEPTH(256)
    ) uart0 (
        .clk(clk),
        .rst_n(rst_n),
        
        // Physical UART pins to SAMD51
        .uart_rx(uart0_rx),
        .uart_tx(uart0_tx),
        
        // Data interface
        .tx_data(uart_tx_data),
        .tx_valid(uart_tx_valid),
        .tx_ready(uart_tx_ready),
        
        .rx_data(uart_rx_data),
        .rx_valid(uart_rx_valid),
        .rx_ready(uart_rx_ready),
        
        // Status
        .tx_busy(uart_tx_busy),
        .rx_error(uart_rx_error),
        .tx_fifo_used(uart_tx_fifo_used),
        .rx_fifo_used(uart_rx_fifo_used)
    );
    
    // UART debug output generator
    // Automatically sends status updates via UART0→USB
    uart_debug_output uart_debug (
        .clk(clk),
        .rst_n(rst_n),
        
        // UART TX interface
        .uart_tx_data(uart_tx_data),
        .uart_tx_valid(uart_tx_valid),
        .uart_tx_ready(uart_tx_ready),
        
        // Status inputs for debug messages
        .proxy_enable(proxy_enable),
        .host_mode_enable(host_mode_enable),
        .enum_done(enum_done),
        .kbd_active(kbd_active),
        .mouse_active(mouse_active),
        .kbd_report_valid(kbd_report_valid),
        .mouse_report_valid(mouse_report_valid),
        .kbd_report_data(kbd_report_data),
        .mouse_report_data(mouse_report_data),
        .packet_count(packet_count),
        .error_count(error_count),
        .buffer_overflow(buffer_overflow)
    );
    
    // =======================================================================
    // UART Command Processor
    // =======================================================================
    // Parses commands from SAMD51 for HID report injection and control
    
    uart_command_processor cmd_processor (
        .clk(clk),
        .rst_n(rst_n),
        
        // UART RX interface
        .uart_rx_data(uart_rx_data),
        .uart_rx_valid(uart_rx_valid),
        .uart_rx_ready(uart_rx_ready),
        
        // UART TX interface (for responses - not used yet)
        .uart_tx_data(),  // Unused - debug output handles TX
        .uart_tx_valid(),
        .uart_tx_ready(1'b0),
        
        // Keyboard injection
        .inject_kbd_report(inject_kbd_report),
        .inject_kbd_valid(inject_kbd_valid),
        .inject_kbd_ack(inject_kbd_ack),
        
        // Mouse injection
        .inject_mouse_report(inject_mouse_report),
        .inject_mouse_valid(inject_mouse_valid),
        .inject_mouse_ack(inject_mouse_ack),
        
        // Control outputs
        .filter_mask(filter_mask),
        .mode_proxy(mode_proxy_uart),
        .mode_host(mode_host_uart)
    );
    
    // =======================================================================
    // USB Injection Multiplexer
    // =======================================================================
    // Merges real HID reports with injected reports from SAMD51
    
    usb_injection_mux injection_mux (
        .clk(clk),
        .rst_n(rst_n),
        
        // Real reports from USB host
        .host_kbd_report(kbd_report_data),
        .host_kbd_valid(kbd_report_valid),
        .host_mouse_report(mouse_report_data),
        .host_mouse_valid(mouse_report_valid),
        
        // Injected reports from SAMD51
        .inject_kbd_report(inject_kbd_report),
        .inject_kbd_valid(inject_kbd_valid),
        .inject_kbd_ack(inject_kbd_ack),
        .inject_mouse_report(inject_mouse_report),
        .inject_mouse_valid(inject_mouse_valid),
        .inject_mouse_ack(inject_mouse_ack),
        
        // Merged output (to USB device or monitoring)
        .out_kbd_report(merged_kbd_report),
        .out_kbd_valid(merged_kbd_valid),
        .out_mouse_report(merged_mouse_report),
        .out_mouse_valid(merged_mouse_valid)
    );
    
    // USB Host Mode Status LEDs (Cynthion has 6 FPGA LEDs: 0-5)
    // LED[5:3] = USB Host Status
    // LED[2:0] = Proxy/Monitor Status
    wire [5:0] status_leds;
    assign status_leds[5] = host_mode_enable & device_connected;    // Host mode + device connected
    assign status_leds[4] = enum_done;                              // Enumeration complete
    assign status_leds[3] = kbd_active || mouse_active;             // HID device active
    assign status_leds[2] = kbd_report_valid || mouse_report_valid; // New HID report
    assign status_leds[1] = proxy_enable;                           // Proxy active
    assign status_leds[0] = buffer_overflow;                        // Error indicator
    
    // Debug interface module
    debug_interface debug_if (
        .clk(clk),
        .rst_n(system_rst_n),
        
        // Debug Control Interface
        .debug_cmd(debug_cmd),
        .debug_cmd_valid(debug_cmd_valid),
        .debug_resp(debug_resp),
        .debug_resp_valid(debug_resp_valid),
        
        // Status Inputs
        .proxy_active(proxy_enable),
        .host_connected(host_conn_detect | enum_done),  // Host connected or enumeration done
        .device_connected(device_conn_detect),
        .host_speed(detected_speed),                     // Use detected speed from reset controller
        .device_speed(device_conn_speed),
        .buffer_overflow(buffer_overflow),
        .buffer_used(buffer_used),
        .packet_count(packet_count),
        .error_count(error_count),
        
        // Monitor Inputs
        .host_line_state(phy2_line_state),
        .device_line_state(phy1_line_state),
        .timestamp(timestamp),
        
        // Debug Outputs
        .debug_leds(debug_leds),
        .debug_probe(debug_probe),
        
        // Configuration Control
        .force_reset(force_reset),
        .debug_mode(),
        .trigger_config(),
        .loopback_enable()
    );
    
    // Status LEDs - output to hardware
    assign led = status_leds;
    
    // Debug outputs
    assign debug = debug_probe[3:0];  // Use the first 4 bits of debug probe
    
    // Debug interface now uses UART0→USB instead of direct USB PHY0 access
    // This provides cleaner host integration through SAMD51 CDC-ACM bridge
    assign debug_cmd = uart_rx_data;
    assign debug_cmd_valid = uart_rx_valid;
    // Debug response is handled by uart_debug_output module
    
    // Error counter
    reg [15:0] internal_error_count;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            internal_error_count <= 16'd0;
        else if (host_decoded_valid && !host_crc_valid && host_decoded_eop)
            internal_error_count <= internal_error_count + 1'b1;
        else if (device_decoded_valid && !device_crc_valid && device_decoded_eop)
            internal_error_count <= internal_error_count + 1'b1;
    end
    assign error_count = internal_error_count;
    
endmodule

// PLL module definition - moved outside the top module to fix syntax error
module pll_60_to_240 (
    input  wire clkin,     // 60 MHz input clock
    output wire clkout0,   // 60 MHz output clock
    output wire clkout1,   // 120 MHz output clock
    output wire clkout2,   // 240 MHz output clock
    output wire locked     // PLL locked indicator
);
    // PLL would be implemented with platform-specific primitives
    // For ECP5, this would use the EHXPLLL primitive
    
    // Placeholder for simulation
    assign clkout0 = clkin;
    assign clkout1 = clkin;  // Would normally be 120 MHz
    assign clkout2 = clkin;  // Would normally be 240 MHz
    assign locked = 1'b1;    // Always locked for this placeholder
endmodule