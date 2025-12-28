///////////////////////////////////////////////////////////////////////////////
// File: usb_sof_generator.v
// Description: USB Start-of-Frame (SOF) Generator
//
// Generates SOF packets every 1ms (Full-Speed) or 125us (High-Speed).
// Maintains frame number counter and generates SOF tokens.
//
// Based on USB 2.0 Specification Section 8.4.3
///////////////////////////////////////////////////////////////////////////////

module usb_sof_generator (
    // Clock and Reset
    input  wire        clk,                 // System clock (60MHz)
    input  wire        rst_n,               // Active low reset
    
    // Control
    input  wire        enable,              // Enable SOF generation
    input  wire [1:0]  speed,               // 01=FS (1ms), 10=HS (125us)
    
    // SOF Output
    output reg         sof_trigger,         // SOF packet should be sent
    output reg  [10:0] frame_number,        // 11-bit frame counter
    
    // Token Generator Interface
    output reg         token_start,
    output reg  [1:0]  token_type,
    output reg  [10:0] token_frame,
    input  wire        token_ready,
    input  wire        token_done
);

    // Speed constants
    localparam SPEED_FULL = 2'b01;
    localparam SPEED_HIGH = 2'b10;
    
    // Token type
    localparam TOKEN_SOF = 2'b10;
    
    // Timing constants (60MHz clock cycles)
    // Full-Speed: 1ms = 60,000 cycles
    // High-Speed: 125us = 7,500 cycles
    localparam FS_INTERVAL = 32'd60000;
    localparam HS_INTERVAL = 32'd7500;
    
    reg [31:0] timer;
    reg [31:0] interval;
    
    // State machine
    localparam STATE_IDLE      = 2'd0;
    localparam STATE_TRIGGER   = 2'd1;
    localparam STATE_SEND_SOF  = 2'd2;
    localparam STATE_WAIT_DONE = 2'd3;
    
    reg [1:0] state;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            timer <= 32'd0;
            frame_number <= 11'd0;
            sof_trigger <= 1'b0;
            token_start <= 1'b0;
            token_type <= 2'd0;
            token_frame <= 11'd0;
            interval <= FS_INTERVAL;
        end else begin
            // Default outputs
            sof_trigger <= 1'b0;
            token_start <= 1'b0;
            
            // Update interval based on speed
            if (speed == SPEED_HIGH)
                interval <= HS_INTERVAL;
            else
                interval <= FS_INTERVAL;
            
            if (!enable) begin
                state <= STATE_IDLE;
                timer <= 32'd0;
            end else begin
                case (state)
                    STATE_IDLE: begin
                        timer <= timer + 1'b1;
                        
                        if (timer >= interval) begin
                            timer <= 32'd0;
                            state <= STATE_TRIGGER;
                        end
                    end
                    
                    STATE_TRIGGER: begin
                        sof_trigger <= 1'b1;
                        state <= STATE_SEND_SOF;
                    end
                    
                    STATE_SEND_SOF: begin
                        if (token_ready) begin
                            token_start <= 1'b1;
                            token_type <= TOKEN_SOF;
                            token_frame <= frame_number;
                            state <= STATE_WAIT_DONE;
                        end
                    end
                    
                    STATE_WAIT_DONE: begin
                        if (token_done) begin
                            // Increment frame number (wraps at 2047)
                            if (frame_number == 11'd2047)
                                frame_number <= 11'd0;
                            else
                                frame_number <= frame_number + 1'b1;
                            
                            state <= STATE_IDLE;
                        end
                    end
                    
                    default: state <= STATE_IDLE;
                endcase
            end
        end
    end

endmodule
