///////////////////////////////////////////////////////////////////////////////
// File: usb_reset_controller.v
// Description: USB Host Reset Controller with Speed Detection
//
// Implements USB bus reset sequence with high-speed chirp negotiation
// and automatic speed detection (Full-Speed 12Mbit or High-Speed 480Mbit).
//
// Based on USB 2.0 Specification Section 7.1.7.5 (Reset Signaling)
///////////////////////////////////////////////////////////////////////////////

module usb_reset_controller (
    // Clock and Reset
    input  wire        clk,                 // 60MHz system clock
    input  wire        rst_n,               // Active low reset
    
    // Control Interface
    input  wire        bus_reset_req,       // Request bus reset
    output reg         reset_active,        // Reset FSM is active
    output reg  [1:0]  detected_speed,      // 00=UNKNOWN, 01=FULL, 10=HIGH
    
    // PHY Control Outputs
    output reg  [1:0]  phy_op_mode,         // Operating mode (00=normal, 01=non-driving)
    output reg  [1:0]  phy_xcvr_select,     // Speed selection (00=HS, 01=FS)
    output reg         phy_term_select,     // Termination (0=HS, 1=FS/LS)
    
    // PHY Status Inputs
    input  wire [1:0]  phy_line_state,      // D+/D- line state
    
    // UTMI Transmit Interface (for chirp generation)
    output reg  [7:0]  utmi_tx_data,        // Transmit data
    output reg         utmi_tx_valid,       // Transmit valid
    input  wire        utmi_tx_ready        // Transmit ready
);

    // Speed encoding
    localparam SPEED_UNKNOWN = 2'b00;
    localparam SPEED_FULL    = 2'b01;
    localparam SPEED_HIGH    = 2'b10;
    
    // Line state encoding
    localparam LINE_STATE_SE0 = 2'b00;  // Single-Ended Zero (reset/disconnect)
    localparam LINE_STATE_J   = 2'b01;  // J state (idle for FS/LS)
    localparam LINE_STATE_K   = 2'b10;  // K state (chirp signaling)
    localparam LINE_STATE_SE1 = 2'b11;  // Single-Ended One (error)
    
    // PHY Operating Mode
    localparam OP_MODE_NORMAL      = 2'b00;
    localparam OP_MODE_NON_DRIVING = 2'b01;
    
    // Timing Constants (in 60MHz clock cycles)
    // These values are based on USB 2.0 spec timings
    localparam SETTLE_TIME          = 6000;      // ~100us - device connection settle
    localparam MIN_RESET_TIME       = 600000;    // ~10ms - minimum reset duration
    localparam MAX_RESET_TIME       = 3000000;   // ~50ms - maximum reset duration
    localparam MIN_RESET_CHIRP      = 3000;      // ~50us - minimum before chirp check
    localparam CHIRP_FILTER_CYCLES  = 30000;     // ~500us - chirp K detection filter
    localparam CHIRP_DURATION       = 3000;      // ~50us - host chirp K/J duration
    localparam POST_RESET_RECOVERY  = 60000;     // ~1ms - recovery time after reset
    
    // State Machine
    localparam STATE_DISCONNECTED   = 4'd0;
    localparam STATE_WAIT_CONNECT   = 4'd1;
    localparam STATE_BUS_RESET      = 4'd2;
    localparam STATE_WAIT_CHIRP_K   = 4'd3;
    localparam STATE_CHIRP_K_FILTER = 4'd4;
    localparam STATE_HOST_CHIRP_K   = 4'd5;
    localparam STATE_HOST_CHIRP_J   = 4'd6;
    localparam STATE_WAIT_HS_IDLE   = 4'd7;
    localparam STATE_FS_IDLE        = 4'd8;
    localparam STATE_HS_IDLE        = 4'd9;
    localparam STATE_RECOVERY       = 4'd10;
    
    reg [3:0]  state;
    reg [3:0]  next_state;
    reg [31:0] timer;
    reg [7:0]  chirp_count;
    
    // State machine - combinational next state logic
    always @(*) begin
        next_state = state;
        
        case (state)
            STATE_DISCONNECTED: begin
                if (phy_line_state == LINE_STATE_J)
                    next_state = STATE_WAIT_CONNECT;
            end
            
            STATE_WAIT_CONNECT: begin
                if (phy_line_state != LINE_STATE_J)
                    next_state = STATE_DISCONNECTED;
                else if (timer >= SETTLE_TIME)
                    next_state = STATE_BUS_RESET;
            end
            
            STATE_BUS_RESET: begin
                if (timer >= MIN_RESET_CHIRP && phy_line_state == LINE_STATE_K)
                    next_state = STATE_WAIT_CHIRP_K;
                else if (timer >= MIN_RESET_TIME)
                    next_state = STATE_FS_IDLE;
            end
            
            STATE_WAIT_CHIRP_K: begin
                if (phy_line_state == LINE_STATE_K)
                    next_state = STATE_CHIRP_K_FILTER;
                else if (timer >= MIN_RESET_TIME)
                    next_state = STATE_FS_IDLE;
            end
            
            STATE_CHIRP_K_FILTER: begin
                if (phy_line_state != LINE_STATE_K)
                    next_state = STATE_BUS_RESET;
                else if (timer >= CHIRP_FILTER_CYCLES)
                    next_state = STATE_HOST_CHIRP_K;
            end
            
            STATE_HOST_CHIRP_K: begin
                if (timer >= CHIRP_DURATION)
                    next_state = STATE_HOST_CHIRP_J;
            end
            
            STATE_HOST_CHIRP_J: begin
                if (timer >= CHIRP_DURATION) begin
                    if (chirp_count >= 3)  // Send 3 pairs of K-J chirps
                        next_state = STATE_WAIT_HS_IDLE;
                    else
                        next_state = STATE_HOST_CHIRP_K;
                end
            end
            
            STATE_WAIT_HS_IDLE: begin
                if (phy_line_state == LINE_STATE_J)
                    next_state = STATE_RECOVERY;
                else if (timer >= 6000)  // Timeout after 100us
                    next_state = STATE_FS_IDLE;
            end
            
            STATE_RECOVERY: begin
                if (timer >= POST_RESET_RECOVERY)
                    next_state = STATE_HS_IDLE;
            end
            
            STATE_FS_IDLE: begin
                if (bus_reset_req)
                    next_state = STATE_BUS_RESET;
            end
            
            STATE_HS_IDLE: begin
                if (bus_reset_req)
                    next_state = STATE_BUS_RESET;
            end
            
            default: next_state = STATE_DISCONNECTED;
        endcase
    end
    
    // State machine - sequential logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_DISCONNECTED;
            timer <= 32'd0;
            chirp_count <= 8'd0;
            detected_speed <= SPEED_UNKNOWN;
            reset_active <= 1'b0;
            phy_op_mode <= OP_MODE_NORMAL;
            phy_xcvr_select <= 2'b01;  // Start with FS
            phy_term_select <= 1'b1;   // FS termination
            utmi_tx_data <= 8'd0;
            utmi_tx_valid <= 1'b0;
        end else begin
            state <= next_state;
            
            // Default outputs
            utmi_tx_valid <= 1'b0;
            
            // Timer management
            if (state != next_state)
                timer <= 32'd0;
            else
                timer <= timer + 1'b1;
            
            // State-specific logic
            case (state)
                STATE_DISCONNECTED: begin
                    reset_active <= 1'b0;
                    detected_speed <= SPEED_UNKNOWN;
                    phy_op_mode <= OP_MODE_NORMAL;
                    phy_xcvr_select <= 2'b01;  // FS
                    phy_term_select <= 1'b1;
                    chirp_count <= 8'd0;
                end
                
                STATE_WAIT_CONNECT: begin
                    reset_active <= 1'b0;
                end
                
                STATE_BUS_RESET: begin
                    reset_active <= 1'b1;
                    // Drive SE0 (reset condition)
                    phy_op_mode <= OP_MODE_NORMAL;
                    phy_xcvr_select <= 2'b01;  // FS during reset
                    phy_term_select <= 1'b1;
                    // Transmit SE0 by sending K repeatedly
                    utmi_tx_data <= 8'h00;
                    utmi_tx_valid <= 1'b1;
                end
                
                STATE_WAIT_CHIRP_K: begin
                    reset_active <= 1'b1;
                    // Stop driving, wait for device chirp
                    phy_op_mode <= OP_MODE_NON_DRIVING;
                end
                
                STATE_CHIRP_K_FILTER: begin
                    reset_active <= 1'b1;
                    // Continue non-driving mode
                    phy_op_mode <= OP_MODE_NON_DRIVING;
                end
                
                STATE_HOST_CHIRP_K: begin
                    reset_active <= 1'b1;
                    // Send host chirp K
                    phy_op_mode <= OP_MODE_NORMAL;
                    phy_xcvr_select <= 2'b00;  // Switch to HS
                    phy_term_select <= 1'b0;   // HS termination
                    utmi_tx_data <= 8'hAA;     // Chirp K pattern
                    utmi_tx_valid <= 1'b1;
                    
                    if (next_state != state)
                        chirp_count <= chirp_count + 1'b1;
                end
                
                STATE_HOST_CHIRP_J: begin
                    reset_active <= 1'b1;
                    // Send host chirp J
                    utmi_tx_data <= 8'h55;     // Chirp J pattern
                    utmi_tx_valid <= 1'b1;
                end
                
                STATE_WAIT_HS_IDLE: begin
                    reset_active <= 1'b1;
                    phy_op_mode <= OP_MODE_NON_DRIVING;
                    phy_xcvr_select <= 2'b00;  // HS
                    phy_term_select <= 1'b0;
                end
                
                STATE_RECOVERY: begin
                    reset_active <= 1'b1;
                    phy_op_mode <= OP_MODE_NORMAL;
                    detected_speed <= SPEED_HIGH;
                end
                
                STATE_FS_IDLE: begin
                    reset_active <= 1'b0;
                    detected_speed <= SPEED_FULL;
                    phy_op_mode <= OP_MODE_NORMAL;
                    phy_xcvr_select <= 2'b01;  // FS
                    phy_term_select <= 1'b1;
                end
                
                STATE_HS_IDLE: begin
                    reset_active <= 1'b0;
                    detected_speed <= SPEED_HIGH;
                    phy_op_mode <= OP_MODE_NORMAL;
                    phy_xcvr_select <= 2'b00;  // HS
                    phy_term_select <= 1'b0;
                end
                
                default: begin
                    reset_active <= 1'b0;
                    detected_speed <= SPEED_UNKNOWN;
                end
            endcase
        end
    end

endmodule
