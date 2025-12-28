///////////////////////////////////////////////////////////////////////////////
// File: usb_hid_mouse_engine.v (FIXED VERSION)
// Description: USB HID Mouse Host Engine
//
// FIXES APPLIED:
// - CRITICAL: Fixed multiple drivers on report_byte_count
//   - Moved all report_byte_count management into report reception block
//   - Removed from main control block
// - Fixed type mismatch (4'd8 -> 7'd8)
// - Added overflow protection for shift calculation
//
// Implements USB host for HID mice supporting both Boot Protocol and Report Protocol.
// Polls the mouse's interrupt endpoint at the specified interval.
///////////////////////////////////////////////////////////////////////////////

module usb_hid_mouse_engine (
    // Clock and Reset
    input  wire        clk,
    input  wire        rst_n,
    
    // Control Interface
    input  wire        enable,
    input  wire [6:0]  device_addr,
    input  wire [3:0]  endpoint,
    input  wire [10:0] max_packet_size,
    input  wire [7:0]  poll_interval,
    input  wire [1:0]  device_speed,
    
    // Mouse Report Output
    output reg  [39:0] report_data,
    output reg         report_valid,
    output reg  [6:0]  report_length,
    
    // Decoded Mouse Data
    output reg  [7:0]  button_state,
    output reg  signed [7:0]  delta_x,
    output reg  signed [7:0]  delta_y,
    output reg  signed [7:0]  wheel_delta,
    
    // Status
    output reg         active,
    output reg         error,
    output reg  [7:0]  error_code,
    
    // Transaction Engine Interface
    output reg         trans_start,
    input  wire        trans_done,
    input  wire [2:0]  trans_result,
    output reg  [6:0]  trans_addr,
    output reg  [3:0]  trans_endp,
    output reg         trans_data_pid,
    input  wire [7:0]  trans_data_out,
    input  wire        trans_data_out_valid,
    output wire        trans_data_out_ready
);

    // Transaction result codes
    localparam RESULT_ACK       = 3'd1;
    localparam RESULT_NAK       = 3'd2;
    localparam RESULT_STALL     = 3'd3;
    localparam RESULT_TIMEOUT   = 3'd4;
    localparam RESULT_CRC_ERROR = 3'd5;
    
    // Error codes
    localparam ERR_NONE         = 8'h00;
    localparam ERR_NAK_TIMEOUT  = 8'h01;
    localparam ERR_STALL        = 8'h02;
    localparam ERR_CRC          = 8'h03;
    localparam ERR_TIMEOUT      = 8'h04;
    
    // State machine
    localparam STATE_IDLE       = 3'd0;
    localparam STATE_WAIT_POLL  = 3'd1;
    localparam STATE_START_IN   = 3'd2;
    localparam STATE_WAIT_IN    = 3'd3;
    localparam STATE_PROCESS    = 3'd4;
    localparam STATE_ERROR      = 3'd5;
    
    reg [2:0]  state;
    reg [2:0]  next_state;
    
    // Polling interval timer
    reg [31:0] poll_timer;
    reg [15:0] ms_counter;
    reg        ms_tick;
    
    // Data PID toggle tracking
    reg        current_data_pid;
    
    // Retry and timeout counters
    reg [7:0]  nak_count;
    reg [7:0]  max_nak_retries;
    
    // Report reception buffer
    reg [63:0] report_buffer;
    wire [7:0] report_byte0 = report_buffer[7:0];
    wire [7:0] report_byte1 = report_buffer[15:8];
    wire [7:0] report_byte2 = report_buffer[23:16];
    wire [7:0] report_byte3 = report_buffer[31:24];
    wire [7:0] report_byte4 = report_buffer[39:32];
    wire [7:0] report_byte5 = report_buffer[47:40];
    wire [7:0] report_byte6 = report_buffer[55:48];
    wire [7:0] report_byte7 = report_buffer[63:56];
    reg [6:0]  report_byte_count;
    reg        receiving_report;
    
    // Watchdog timer
    reg [23:0] watchdog_counter;
    reg        watchdog_timeout;
    
    integer i;
    
    // Constants
    localparam MS_TICK_COUNT = 16'd60000;
    localparam US125_TICK_COUNT = 16'd7500;
    localparam MAX_NAK_RETRIES = 8'd100;
    localparam WATCHDOG_TIMEOUT = 24'd6000000;
    
    // Speed definitions
    localparam SPEED_LOW = 2'b00;
    localparam SPEED_FULL = 2'b01;
    localparam SPEED_HIGH = 2'b10;
    
    // Tick generator
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
    // FIXED: Added overflow protection
    wire [7:0] effective_interval;
    
    generate
        if (1) begin : calc_interval
            reg [7:0] shift_amount;
            always @(*) begin
                if (device_speed == SPEED_HIGH) begin
                    // Limit shift to prevent overflow
                    if (poll_interval > 8'd8)
                        shift_amount = 8'd7;  // Max shift for 8-bit
                    else if (poll_interval == 8'd0)
                        shift_amount = 8'd0;
                    else
                        shift_amount = poll_interval - 1;
                end else begin
                    shift_amount = 8'd0;  // Not used for non-HS
                end
            end
            
            assign effective_interval = (device_speed == SPEED_HIGH) ? 
                (8'd1 << shift_amount) : poll_interval;
        end
    endgenerate
    
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
    
    // FIXED: Main control logic - removed report_byte_count assignments
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            trans_start <= 1'b0;
            trans_addr <= 7'd0;
            trans_endp <= 4'd0;
            trans_data_pid <= 1'b0;
            current_data_pid <= 1'b0;
            nak_count <= 8'd0;
            max_nak_retries <= MAX_NAK_RETRIES;
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
                    current_data_pid <= 1'b0;
                    receiving_report <= 1'b0;
                    // REMOVED: report_byte_count reset (now in reception block)
                end
                
                STATE_WAIT_POLL: begin
                    active <= 1'b1;
                end
                
                STATE_START_IN: begin
                    trans_start <= 1'b1;
                    trans_addr <= device_addr;
                    trans_endp <= endpoint;
                    trans_data_pid <= current_data_pid;
                    receiving_report <= 1'b1;
                    // REMOVED: report_byte_count reset (now in reception block)
                end
                
                STATE_WAIT_IN: begin
                    // Wait for transaction
                end
                
                STATE_PROCESS: begin
                    if (trans_result == RESULT_ACK) begin
                        current_data_pid <= ~current_data_pid;
                        nak_count <= 8'd0;
                        
                        if (report_byte_count >= 7'd3) begin
                            report_valid <= 1'b1;
                            report_length <= report_byte_count;
                            
                            // Pack report data (only 40 bits available)
                            report_data[7:0]   <= report_byte0;
                            report_data[15:8]  <= (report_byte_count > 7'd1) ? report_byte1 : 8'd0;
                            report_data[23:16] <= (report_byte_count > 7'd2) ? report_byte2 : 8'd0;
                            report_data[31:24] <= (report_byte_count > 7'd3) ? report_byte3 : 8'd0;
                            report_data[39:32] <= (report_byte_count > 7'd4) ? report_byte4 : 8'd0;
                            // Note: report_data is only 40 bits, removed invalid [63:40] and [511:64] assignments
                            
                            // Decode boot protocol fields
                            button_state <= report_byte0;
                            delta_x <= $signed(report_byte1);
                            delta_y <= $signed(report_byte2);
                            wheel_delta <= (report_byte_count > 7'd3) ? $signed(report_byte3) : 8'sd0;
                        end
                    end
                    else if (trans_result == RESULT_NAK) begin
                        if (nak_count >= max_nak_retries) begin
                            error <= 1'b1;
                            error_code <= ERR_NAK_TIMEOUT;
                        end else begin
                            nak_count <= nak_count + 1'b1;
                        end
                    end
                    else if (trans_result == RESULT_STALL) begin
                        error <= 1'b1;
                        error_code <= ERR_STALL;
                    end
                    else if (trans_result == RESULT_CRC_ERROR) begin
                        error <= 1'b1;
                        error_code <= ERR_CRC;
                    end
                    else if (trans_result == RESULT_TIMEOUT) begin
                        error <= 1'b1;
                        error_code <= ERR_TIMEOUT;
                    end
                    
                    receiving_report <= 1'b0;
                end
                
                STATE_ERROR: begin
                    active <= 1'b0;
                end
            endcase
        end
    end
    
    // FIXED: Report data reception - ALL report_byte_count management here
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            report_buffer <= 64'd0;
            report_byte_count <= 7'd0;
        end else begin
            // Clear count when starting new transaction
            if (state == STATE_IDLE || state == STATE_START_IN) begin
                report_byte_count <= 7'd0;
            // Receive data
            end else if (receiving_report && trans_data_out_valid && report_byte_count < 7'd8) begin
                report_buffer <= {trans_data_out, report_buffer[63:8]};
                report_byte_count <= report_byte_count + 1'b1;
            end
        end
    end
    
    // Always ready to accept data
    assign trans_data_out_ready = 1'b1;
    
endmodule