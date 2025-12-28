///////////////////////////////////////////////////////////////////////////////
// File: usb_hid_keyboard_engine.v
// Description: USB HID Keyboard Host Engine
//
// Polls a USB HID keyboard device for keypress data via interrupt endpoint.
// Supports both Boot Protocol (8 bytes) and Report Protocol (variable length).
// Supports both Full-Speed (1ms polling) and High-Speed (125μs polling) devices.
//
// Boot Protocol Keyboard Report Format (8 bytes):
// Byte 0: Modifier keys (Ctrl, Shift, Alt, GUI)
// Byte 1: Reserved (OEM)
// Bytes 2-7: Key codes (up to 6 simultaneous keys)
//
// Report Protocol: Variable-length reports up to max_packet_size bytes.
//   Reports are passed through without parsing for full gaming keyboard support.
///////////////////////////////////////////////////////////////////////////////

module usb_hid_keyboard_engine (
    // Clock and Reset
    input  wire        clk,                 // System clock
    input  wire        rst_n,               // Active low reset
    
    // Control Interface
    input  wire        enable,              // Enable keyboard polling
    input  wire        enumerated,          // Device enumerated successfully
    
    // Device Information (from enumerator)
    input  wire [6:0]  device_addr,         // Device address
    input  wire [3:0]  endp_number,         // Interrupt IN endpoint
    input  wire [7:0]  max_packet_size,     // Max packet size
    input  wire [1:0]  device_speed,        // Device speed
    input  wire [7:0]  poll_interval,       // Polling interval from bInterval (ms)
    
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
    input  wire [3:0]  utmi_rx_pid,         // Received PID
    
    // SOF Interface
    input  wire        sof_trigger,         // SOF event (1ms for FS, 125μs for HS)
    input  wire [10:0] frame_number,        // Frame/microframe number
    
    // Keyboard Report Output
    output reg         report_valid,        // New report available
    output reg  [511:0] report_data,        // Full report (up to 64 bytes)
    output reg  [6:0]  report_length,       // Actual report length
    
    // Decoded Boot Protocol Fields (for backward compatibility)
    output reg  [7:0]  report_modifiers,    // Modifier keys
    output reg  [7:0]  report_key0,         // Key code 0
    output reg  [7:0]  report_key1,         // Key code 1
    output reg  [7:0]  report_key2,         // Key code 2
    output reg  [7:0]  report_key3,         // Key code 3
    output reg  [7:0]  report_key4,         // Key code 4
    output reg  [7:0]  report_key5,         // Key code 5
    
    // Status
    output reg  [7:0]  status,              // Status register
    output reg  [15:0] poll_count           // Number of polls
);

    // Token types
    localparam TOKEN_IN = 2'b01;
    
    // PIDs
    localparam PID_DATA0 = 4'b0011;
    localparam PID_DATA1 = 4'b1011;
    localparam PID_ACK   = 4'b0010;
    localparam PID_NAK   = 4'b1010;
    localparam PID_STALL = 4'b1110;
    
    // State Machine
    localparam STATE_IDLE           = 3'd0;
    localparam STATE_WAIT_SOF       = 3'd1;
    localparam STATE_SEND_IN_TOKEN  = 3'd2;
    localparam STATE_WAIT_DATA      = 3'd3;
    localparam STATE_PROCESS_DATA   = 3'd4;
    localparam STATE_SEND_ACK       = 3'd5;
    localparam STATE_ERROR          = 3'd6;
    
    reg [2:0]  state;
    reg [7:0]  rx_buffer[0:63];     // Report buffer (up to 64 bytes)
    reg [6:0]  rx_count;            // Bytes received (0-64)
    reg        data_pid;            // DATA0/DATA1 toggle
    reg [10:0] last_frame;
    reg [7:0]  poll_counter;        // Counts frames until next poll (based on bInterval)
    reg [7:0]  effective_interval;  // Calculated effective polling interval
    reg [31:0] timeout_counter;
    reg [3:0]  error_count;
    reg [31:0] watchdog_counter;
    
    // Watchdog timeout: 3 seconds at 60MHz = 180,000,000 cycles
    localparam WATCHDOG_TIMEOUT = 32'd180000000;
    
    // Status bits
    localparam STATUS_ACTIVE     = 8'h01;
    localparam STATUS_ERROR      = 8'h02;
    localparam STATUS_STALL      = 8'h04;
    localparam STATUS_TIMEOUT    = 8'h08;
    localparam STATUS_ENUMERATED = 8'h10;
    
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            token_start <= 1'b0;
            token_type <= 2'd0;
            token_addr <= 7'd0;
            token_endp <= 4'd0;
            report_valid <= 1'b0;
            report_data <= 512'd0;
            report_length <= 7'd0;
            report_modifiers <= 8'd0;
            report_key0 <= 8'd0;
            report_key1 <= 8'd0;
            report_key2 <= 8'd0;
            report_key3 <= 8'd0;
            report_key4 <= 8'd0;
            report_key5 <= 8'd0;
            status <= 8'd0;
            poll_count <= 16'd0;
            rx_count <= 7'd0;
            data_pid <= 1'b0;
            last_frame <= 11'd0;
            poll_counter <= 8'd0;
            effective_interval <= 8'd1;
            timeout_counter <= 32'd0;
            error_count <= 4'd0;
            watchdog_counter <= 32'd0;
            for (i = 0; i < 64; i = i + 1)
                rx_buffer[i] <= 8'd0;
        end else begin
            // Default outputs
            token_start <= 1'b0;
            report_valid <= 1'b0;
            
            // Watchdog counter
            if (state != STATE_IDLE && enable && enumerated)
                watchdog_counter <= watchdog_counter + 1'b1;
            else
                watchdog_counter <= 32'd0;
            
            // Watchdog timeout - reset to idle on timeout
            if (watchdog_counter >= WATCHDOG_TIMEOUT) begin
                state <= STATE_IDLE;
                status <= STATUS_TIMEOUT;
                watchdog_counter <= 32'd0;
            end
            
            // Collect RX data (up to 64 bytes or max_packet_size)
            if (utmi_rx_valid && rx_count < max_packet_size[6:0] && rx_count < 7'd64) begin
                rx_buffer[rx_count] <= utmi_rx_data;
                rx_count <= rx_count + 1'b1;
            end
            
            // Timeout counter
            timeout_counter <= timeout_counter + 1'b1;
            
            case (state)
                STATE_IDLE: begin
                    status <= enumerated ? STATUS_ENUMERATED : 8'h00;
                    timeout_counter <= 32'd0;
                    error_count <= 4'd0;
                    
                    if (enable && enumerated) begin
                        state <= STATE_WAIT_SOF;
                        data_pid <= 1'b0;  // Start with DATA0
                    end
                end
                
                STATE_WAIT_SOF: begin
                    status <= STATUS_ACTIVE | STATUS_ENUMERATED;
                    
                    // Poll based on bInterval
                    // Full-Speed: poll_interval frames (1ms each)
                    // High-Speed: 2^(poll_interval-1) microframes (125μs each)
                    if (sof_trigger && frame_number != last_frame) begin
                        last_frame <= frame_number;
                        
                        // Calculate effective interval based on speed
                        if (device_speed == SPEED_HIGH)
                            effective_interval <= (8'd1 << (poll_interval - 1));
                        else
                            effective_interval <= poll_interval;
                        
                        if (poll_counter >= effective_interval - 1) begin
                            // Time to poll
                            poll_counter <= 8'd0;
                            rx_count <= 7'd0;
                            state <= STATE_SEND_IN_TOKEN;
                            timeout_counter <= 32'd0;
                            watchdog_counter <= 32'd0;  // Kick watchdog
                        end else begin
                            // Not yet time to poll, increment counter
                            poll_counter <= poll_counter + 1'b1;
                        end
                    end
                end
                        end else begin
                            // Not yet time to poll, increment counter
                            poll_counter <= poll_counter + 1'b1;
                        end
                    end
                end
                
                STATE_SEND_IN_TOKEN: begin
                    if (token_ready && !token_start) begin
                        token_start <= 1'b1;
                        token_type <= TOKEN_IN;
                        token_addr <= device_addr;
                        token_endp <= endp_number;
                        state <= STATE_WAIT_DATA;
                        timeout_counter <= 32'd0;
                    end
                end
                
                STATE_WAIT_DATA: begin
                    // Wait for DATA packet response
                    if (!utmi_rx_active && rx_count > 0) begin
                        // Check if we received correct PID
                        if ((data_pid == 1'b0 && utmi_rx_pid == PID_DATA0) ||
                            (data_pid == 1'b1 && utmi_rx_pid == PID_DATA1)) begin
                            state <= STATE_PROCESS_DATA;
                            watchdog_counter <= 32'd0;  // Kick watchdog
                        end else if (utmi_rx_pid == PID_NAK) begin
                            // Device not ready, try again next frame
                            state <= STATE_WAIT_SOF;
                            watchdog_counter <= 32'd0;  // Kick watchdog on NAK too
                        end else if (utmi_rx_pid == PID_STALL) begin
                            // Device stalled
                            status <= STATUS_STALL;
                            error_count <= error_count + 1'b1;
                            state <= STATE_ERROR;
                        end
                    end
                    
                    // Timeout after 10ms
                    if (timeout_counter > 32'd600000) begin
                        error_count <= error_count + 1'b1;
                        if (error_count >= 4'd10) begin
                            status <= STATUS_TIMEOUT;
                            state <= STATE_ERROR;
                        end else begin
                            state <= STATE_WAIT_SOF;
                        end
                    end
                end
                
                STATE_PROCESS_DATA: begin
                    // Extract keyboard report - pack full report and decode boot protocol fields
                    if (rx_count >= 7'd3) begin  // Minimum 3 bytes
                        // Pack full report data
                        integer j;
                        for (j = 0; j < 64; j = j + 1) begin
                            if (j < rx_count)
                                report_data[j*8 +: 8] <= rx_buffer[j];
                            else
                                report_data[j*8 +: 8] <= 8'd0;
                        end
                        report_length <= rx_count;
                        
                        // Decode boot protocol fields (if report is 8+ bytes)
                        if (rx_count >= 7'd8) begin
                            report_modifiers <= rx_buffer[0];
                            report_key0 <= rx_buffer[2];
                            report_key1 <= rx_buffer[3];
                            report_key2 <= rx_buffer[4];
                            report_key3 <= rx_buffer[5];
                            report_key4 <= rx_buffer[6];
                            report_key5 <= rx_buffer[7];
                        end else begin
                            // Shorter report - just pass through
                            report_modifiers <= rx_buffer[0];
                            report_key0 <= (rx_count > 7'd1) ? rx_buffer[1] : 8'd0;
                            report_key1 <= (rx_count > 7'd2) ? rx_buffer[2] : 8'd0;
                            report_key2 <= (rx_count > 7'd3) ? rx_buffer[3] : 8'd0;
                            report_key3 <= (rx_count > 7'd4) ? rx_buffer[4] : 8'd0;
                            report_key4 <= (rx_count > 7'd5) ? rx_buffer[5] : 8'd0;
                            report_key5 <= (rx_count > 7'd6) ? rx_buffer[6] : 8'd0;
                        end
                        
                        report_valid <= 1'b1;
                        
                        // Toggle DATA PID
                        data_pid <= ~data_pid;
                        
                        poll_count <= poll_count + 1'b1;
                    end
                    
                    state <= STATE_WAIT_SOF;
                end
                
                STATE_ERROR: begin
                    // Stay in error state until re-enabled
                    if (!enable) begin
                        state <= STATE_IDLE;
                    end
                end
                
                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
