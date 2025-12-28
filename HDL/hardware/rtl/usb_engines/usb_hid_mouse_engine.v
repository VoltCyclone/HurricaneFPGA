///////////////////////////////////////////////////////////////////////////////
// File: usb_hid_mouse_engine.v
// Description: USB HID Mouse Host Engine
//
// This module implements a USB host for HID mice supporting both Boot Protocol
// and Report Protocol. It polls the mouse's interrupt endpoint at the specified
// interval and extracts mouse reports.
//
// Supports both Full-Speed (1ms polling, up to 1kHz) and High-Speed (125μs
// polling, up to 8kHz) devices. The polling rate is automatically determined
// from the device's bInterval value.
//
// HID Boot Protocol Mouse Report Format (3-5 bytes):
//   Byte 0: Button states (bit 0=left, 1=right, 2=middle)
//   Byte 1: X movement delta (-127 to +127)
//   Byte 2: Y movement delta (-127 to +127)
//   Byte 3: Wheel delta (optional)
//   Byte 4: AC Pan (optional)
//
// HID Report Protocol: Variable-length reports up to max_packet_size bytes.
//   For gaming mice, this can include extra buttons, precision sensors, etc.
//   Reports are passed through without parsing.
//
// Target: Lattice ECP5 on Cynthion device
///////////////////////////////////////////////////////////////////////////////

module usb_hid_mouse_engine (
    // Clock and Reset
    input  wire        clk,                     // System clock (60 MHz)
    input  wire        rst_n,                   // Active low reset
    
    // Control Interface
    input  wire        enable,                  // Enable mouse polling
    input  wire [6:0]  device_addr,             // Mouse device address
    input  wire [3:0]  endpoint,                // Interrupt endpoint number
    input  wire [10:0] max_packet_size,         // Max packet size for endpoint
    input  wire [7:0]  poll_interval,           // Polling interval (bInterval)
    input  wire [1:0]  device_speed,            // Device speed (00=LS, 01=FS, 10=HS)
    
    // Mouse Report Output
    output reg  [511:0] report_data,            // Mouse report (up to 64 bytes)
    output reg         report_valid,            // New report available (pulse)
    output reg  [6:0]  report_length,           // Actual report length (3-64 bytes)
    
    // Decoded Mouse Data (for convenience)
    output reg  [7:0]  button_state,            // Button states
    output reg  signed [7:0]  delta_x,          // X movement delta
    output reg  signed [7:0]  delta_y,          // Y movement delta
    output reg  signed [7:0]  wheel_delta,      // Wheel scroll delta
    
    // Status
    output reg         active,                  // Actively polling
    output reg         error,                   // Error occurred
    output reg  [7:0]  error_code,              // Error code
    
    // Transaction Engine Interface
    output reg         trans_start,             // Start transaction
    input  wire        trans_done,              // Transaction complete
    input  wire [2:0]  trans_result,            // Transaction result (ACK/NAK/STALL/etc)
    output reg  [6:0]  trans_addr,              // Transaction address
    output reg  [3:0]  trans_endp,              // Transaction endpoint
    output reg         trans_data_pid,          // Data PID toggle (0=DATA0, 1=DATA1)
    input  wire [7:0]  trans_data_out,          // Received data
    input  wire        trans_data_out_valid,    // Data valid
    output wire        trans_data_out_ready     // Ready for data
);

    // Transaction result codes
    localparam RESULT_ACK       = 3'd1;
    localparam RESULT_NAK       = 3'd2;
    localparam RESULT_STALL     = 3'd3;
    localparam RESULT_TIMEOUT   = 3'd4;
    localparam RESULT_CRC_ERROR = 3'd5;
    
    // Error codes
    localparam ERR_NONE         = 8'h00;
    localparam ERR_NAK_TIMEOUT  = 8'h01;  // Too many NAKs
    localparam ERR_STALL        = 8'h02;  // Endpoint stalled
    localparam ERR_CRC          = 8'h03;  // CRC error
    localparam ERR_TIMEOUT      = 8'h04;  // Transaction timeout
    
    // State machine
    localparam STATE_IDLE       = 3'd0;
    localparam STATE_WAIT_POLL  = 3'd1;
    localparam STATE_START_IN   = 3'd2;
    localparam STATE_WAIT_IN    = 3'd3;
    localparam STATE_PROCESS    = 3'd4;
    localparam STATE_ERROR      = 3'd5;
    
    reg [2:0]  state;
    reg [2:0]  next_state;
    
    // Polling interval timer (counts in milliseconds)
    reg [31:0] poll_timer;          // Poll interval counter
    reg [15:0] ms_counter;          // 1ms tick counter (60000 @ 60MHz)
    reg        ms_tick;             // 1ms tick
    
    // Data PID toggle tracking
    reg        current_data_pid;    // Current DATA0/DATA1 toggle
    
    // Retry and timeout counters
    reg [7:0]  nak_count;           // NAK retry counter
    reg [7:0]  max_nak_retries;     // Maximum NAK retries before error
    
    // Report reception buffer (up to 64 bytes)
    reg [7:0]  report_buffer [63:0];
    reg [6:0]  report_byte_count;   // Bytes received (0-64)
    reg        receiving_report;    // Currently receiving report
    
    // Watchdog timer for stuck states
    reg [23:0] watchdog_counter;
    reg        watchdog_timeout;
    
    // Constants
    localparam MS_TICK_COUNT = 16'd60000;      // 60MHz / 1000 = 60000 cycles per 1ms
    localparam US125_TICK_COUNT = 16'd7500;    // 60MHz / 8000 = 7500 cycles per 125μs
    localparam MAX_NAK_RETRIES = 8'd100;       // Allow 100 NAKs before error
    localparam WATCHDOG_TIMEOUT = 24'd6000000; // 100ms @ 60MHz
    
    // Speed definitions
    localparam SPEED_LOW = 2'b00;
    localparam SPEED_FULL = 2'b01;
    localparam SPEED_HIGH = 2'b10;
    
    // Tick generator - 1ms for Full-Speed, 125μs for High-Speed
    wire [15:0] tick_count_target = (device_speed == SPEED_HIGH) ? US125_TICK_COUNT : MS_TICK_COUNT;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ms_counter <= 16'd0;
            ms_tick <= 1'b0;
        end else begin
            if (ms_counter >= tick_count_target - 1) begin
                ms_counter <= 16'd0;
                ms_tick <= 1'b1;
            end else begin
                ms_counter <= ms_counter + 1'b1;
                ms_tick <= 1'b0;
            end
        end
    end
    
    // Polling interval timer
    // For Full-Speed: poll_interval is in ms (bInterval directly)
    // For High-Speed: poll_interval is bInterval, actual interval = 2^(bInterval-1) * 125μs
    wire [7:0] effective_interval = (device_speed == SPEED_HIGH) ? 
        (8'd1 << (poll_interval - 1)) : poll_interval;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            poll_timer <= 32'd0;
        end else if (!enable) begin
            poll_timer <= 32'd0;
        end else if (state == STATE_IDLE || state == STATE_PROCESS) begin
            poll_timer <= 32'd0;
        end else if (ms_tick && poll_timer < {24'd0, effective_interval}) begin
            poll_timer <= poll_timer + 1'b1;
        end
    end
    
    // Watchdog timer
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            watchdog_counter <= 24'd0;
            watchdog_timeout <= 1'b0;
        end else if (state == STATE_IDLE) begin
            watchdog_counter <= 24'd0;
            watchdog_timeout <= 1'b0;
        end else if (watchdog_counter >= WATCHDOG_TIMEOUT) begin
            watchdog_timeout <= 1'b1;
        end else begin
            watchdog_counter <= watchdog_counter + 1'b1;
        end
    end
    
    // State machine - combinational next state logic
    always @(*) begin
        next_state = state;
        
        case (state)
            STATE_IDLE: begin
                if (enable)
                    next_state = STATE_WAIT_POLL;
            end
            
            STATE_WAIT_POLL: begin
                if (!enable)
                    next_state = STATE_IDLE;
                else if (poll_timer >= {24'd0, poll_interval})
                    next_state = STATE_START_IN;
            end
            
            STATE_START_IN: begin
                next_state = STATE_WAIT_IN;
            end
            
            STATE_WAIT_IN: begin
                if (!enable)
                    next_state = STATE_IDLE;
                else if (trans_done)
                    next_state = STATE_PROCESS;
                else if (watchdog_timeout)
                    next_state = STATE_ERROR;
            end
            
            STATE_PROCESS: begin
                if (!enable)
                    next_state = STATE_IDLE;
                else if (error)
                    next_state = STATE_ERROR;
                else
                    next_state = STATE_WAIT_POLL;
            end
            
            STATE_ERROR: begin
                if (!enable)
                    next_state = STATE_IDLE;
            end
            
            default: next_state = STATE_IDLE;
        endcase
    end
    
    // State machine - sequential state update
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= STATE_IDLE;
        else
            state <= next_state;
    end
    
    // Main control logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            trans_start <= 1'b0;
            trans_addr <= 7'd0;
            trans_endp <= 4'd0;
            trans_data_pid <= 1'b0;
            current_data_pid <= 1'b0;
            nak_count <= 8'd0;
            max_nak_retries <= MAX_NAK_RETRIES;
            report_byte_count <= 7'd0;
            receiving_report <= 1'b0;
            report_valid <= 1'b0;
            report_data <= 512'd0;
            report_length <= 7'd0;
            button_state <= 8'd0;
            delta_x <= 8'sd0;
            delta_y <= 8'sd0;
            wheel_delta <= 8'sd0;
            active <= 1'b0;
            error <= 1'b0;
            error_code <= ERR_NONE;
        end else begin
            // Default: clear pulses
            trans_start <= 1'b0;
            report_valid <= 1'b0;
            
            case (state)
                STATE_IDLE: begin
                    active <= 1'b0;
                    error <= 1'b0;
                    error_code <= ERR_NONE;
                    nak_count <= 8'd0;
                    current_data_pid <= 1'b0;  // Start with DATA0
                    receiving_report <= 1'b0;
                    report_byte_count <= 7'd0;
                end
                
                STATE_WAIT_POLL: begin
                    active <= 1'b1;
                    // Just waiting for poll interval to expire
                end
                
                STATE_START_IN: begin
                    // Start IN transaction to poll mouse
                    trans_start <= 1'b1;
                    trans_addr <= device_addr;
                    trans_endp <= endpoint;
                    trans_data_pid <= current_data_pid;
                    receiving_report <= 1'b1;
                    report_byte_count <= 7'd0;
                end
                
                STATE_WAIT_IN: begin
                    // Wait for transaction to complete
                    // Data reception handled separately
                end
                
                STATE_PROCESS: begin
                    // Process transaction result
                    if (trans_result == RESULT_ACK) begin
                        // Success - toggle DATA PID for next transaction
                        current_data_pid <= ~current_data_pid;
                        nak_count <= 8'd0;
                        
                        // Output report if we received data (minimum 3 bytes for boot protocol)
                        if (report_byte_count >= 7'd3) begin
                            report_valid <= 1'b1;
                            report_length <= report_byte_count;
                            
                            // Pack report data (up to 64 bytes into 512-bit vector)
                            integer i;
                            for (i = 0; i < 64; i = i + 1) begin
                                if (i < report_byte_count)
                                    report_data[i*8 +: 8] <= report_buffer[i];
                                else
                                    report_data[i*8 +: 8] <= 8'd0;
                            end
                            
                            // Decode basic boot protocol fields (for backward compatibility)
                            button_state <= report_buffer[0];
                            delta_x <= $signed(report_buffer[1]);
                            delta_y <= $signed(report_buffer[2]);
                            wheel_delta <= (report_byte_count > 7'd3) ? $signed(report_buffer[3]) : 8'sd0;
                        end
                    end
                    else if (trans_result == RESULT_NAK) begin
                        // NAK - device not ready, retry
                        if (nak_count >= max_nak_retries) begin
                            error <= 1'b1;
                            error_code <= ERR_NAK_TIMEOUT;
                        end else begin
                            nak_count <= nak_count + 1'b1;
                        end
                    end
                    else if (trans_result == RESULT_STALL) begin
                        // STALL - endpoint error
                        error <= 1'b1;
                        error_code <= ERR_STALL;
                    end
                    else if (trans_result == RESULT_CRC_ERROR) begin
                        // CRC error
                        error <= 1'b1;
                        error_code <= ERR_CRC;
                    end
                    else if (trans_result == RESULT_TIMEOUT) begin
                        // Timeout
                        error <= 1'b1;
                        error_code <= ERR_TIMEOUT;
                    end
                    
                    receiving_report <= 1'b0;
                end
                
                STATE_ERROR: begin
                    active <= 1'b0;
                    // Stay in error state until disabled
                end
            endcase
        end
    end
    
    // Report data reception
    integer j;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (j = 0; j < 64; j = j + 1)
                report_buffer[j] <= 8'd0;
        end else if (receiving_report && trans_data_out_valid) begin
            // Store received bytes in buffer (up to 64 bytes or max_packet_size)
            if (report_byte_count < max_packet_size[6:0] && report_byte_count < 7'd64) begin
                report_buffer[report_byte_count] <= trans_data_out;
                report_byte_count <= report_byte_count + 1'b1;
            end
        end else if (state == STATE_IDLE || state == STATE_START_IN) begin
            report_byte_count <= 7'd0;
        end
    end
    
    // Always ready to accept data
    assign trans_data_out_ready = 1'b1;
    
endmodule
