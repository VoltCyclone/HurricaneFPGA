///////////////////////////////////////////////////////////////////////////////
// File: usb_token_generator.v
// Description: USB Token Packet Generator
//
// Generates USB token packets (OUT, IN, SOF, SETUP) with proper PID encoding
// and CRC5 calculation. Based on USB 2.0 Specification Section 8.4.
///////////////////////////////////////////////////////////////////////////////

module usb_token_generator (
    // Clock and Reset
    input  wire        clk,                 // System clock
    input  wire        rst_n,               // Active low reset
    
    // Token Request Interface
    input  wire        token_start,         // Start token generation
    input  wire [1:0]  token_type,          // Token type (00=OUT, 01=IN, 10=SOF, 11=SETUP)
    input  wire [6:0]  token_addr,          // Device address (7 bits)
    input  wire [3:0]  token_endp,          // Endpoint number (4 bits)
    input  wire [10:0] token_frame,         // Frame number for SOF (11 bits)
    output reg         token_ready,         // Ready for new token
    output reg         token_done,          // Token transmission complete
    
    // UTMI Transmit Interface
    output reg  [7:0]  utmi_tx_data,        // Transmit data
    output reg         utmi_tx_valid,       // Transmit valid
    input  wire        utmi_tx_ready        // Transmit ready
);

    // Token Types
    localparam TOKEN_OUT   = 2'b00;
    localparam TOKEN_IN    = 2'b01;
    localparam TOKEN_SOF   = 2'b10;
    localparam TOKEN_SETUP = 2'b11;
    
    // PID values (4-bit PID in lower nibble, inverted in upper nibble)
    localparam PID_OUT   = 8'b0001_1110;  // 0x1E
    localparam PID_IN    = 8'b1001_0110;  // 0x96
    localparam PID_SOF   = 8'b0101_1010;  // 0x5A
    localparam PID_SETUP = 8'b1101_0010;  // 0x2D
    
    // State Machine
    localparam STATE_IDLE      = 3'd0;
    localparam STATE_SEND_PID  = 3'd1;
    localparam STATE_SEND_BYTE0 = 3'd2;
    localparam STATE_SEND_BYTE1 = 3'd3;
    localparam STATE_DONE      = 3'd4;
    
    reg [2:0]  state;
    reg [1:0]  saved_token_type;
    reg [10:0] token_data;      // 11 bits for address+endpoint or frame
    reg [4:0]  crc5;
    
    // CRC5 calculation function
    function [4:0] calc_crc5;
        input [10:0] data;
        reg [4:0] crc;
        integer i;
        begin
            crc = 5'b11111;  // Initial value
            for (i = 0; i < 11; i = i + 1) begin
                if (crc[4] ^ data[i])
                    crc = {crc[3:0], 1'b0} ^ 5'b00101;  // Polynomial: x^5 + x^2 + 1
                else
                    crc = {crc[3:0], 1'b0};
            end
            calc_crc5 = ~crc;  // Invert for final CRC5
        end
    endfunction
    
    // State Machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            token_ready <= 1'b1;
            token_done <= 1'b0;
            utmi_tx_data <= 8'd0;
            utmi_tx_valid <= 1'b0;
            saved_token_type <= 2'd0;
            token_data <= 11'd0;
            crc5 <= 5'd0;
        end else begin
            // Default outputs
            token_done <= 1'b0;
            
            case (state)
                STATE_IDLE: begin
                    token_ready <= 1'b1;
                    utmi_tx_valid <= 1'b0;
                    
                    if (token_start) begin
                        token_ready <= 1'b0;
                        saved_token_type <= token_type;
                        
                        // Prepare token data based on type
                        if (token_type == TOKEN_SOF) begin
                            token_data <= token_frame;
                            crc5 <= calc_crc5(token_frame);
                        end else begin
                            // OUT, IN, SETUP - combine address and endpoint
                            token_data <= {token_endp, token_addr};
                            crc5 <= calc_crc5({token_endp, token_addr});
                        end
                        
                        state <= STATE_SEND_PID;
                    end
                end
                
                STATE_SEND_PID: begin
                    utmi_tx_valid <= 1'b1;
                    
                    // Send appropriate PID
                    case (saved_token_type)
                        TOKEN_OUT:   utmi_tx_data <= PID_OUT;
                        TOKEN_IN:    utmi_tx_data <= PID_IN;
                        TOKEN_SOF:   utmi_tx_data <= PID_SOF;
                        TOKEN_SETUP: utmi_tx_data <= PID_SETUP;
                        default:     utmi_tx_data <= PID_OUT;
                    endcase
                    
                    if (utmi_tx_ready) begin
                        state <= STATE_SEND_BYTE0;
                    end
                end
                
                STATE_SEND_BYTE0: begin
                    utmi_tx_valid <= 1'b1;
                    utmi_tx_data <= token_data[7:0];  // Lower 8 bits
                    
                    if (utmi_tx_ready) begin
                        state <= STATE_SEND_BYTE1;
                    end
                end
                
                STATE_SEND_BYTE1: begin
                    utmi_tx_valid <= 1'b1;
                    // Upper 3 bits of data + 5-bit CRC
                    utmi_tx_data <= {crc5, token_data[10:8]};
                    
                    if (utmi_tx_ready) begin
                        utmi_tx_valid <= 1'b0;
                        state <= STATE_DONE;
                    end
                end
                
                STATE_DONE: begin
                    token_done <= 1'b1;
                    state <= STATE_IDLE;
                end
                
                default: begin
                    state <= STATE_IDLE;
                end
            endcase
        end
    end

endmodule
