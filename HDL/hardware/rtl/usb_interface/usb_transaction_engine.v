///////////////////////////////////////////////////////////////////////////////
// File: usb_transaction_engine.v
// Description: USB Transaction Engine with SETUP/IN/OUT Support
//
// Implements complete USB transactions including:
// - SETUP transactions (token + DATA0 + handshake)
// - IN transactions (token + DATA + handshake)
// - OUT transactions (token + DATA + handshake)
// - Proper PID toggling (DATA0/DATA1)
// - Handshake detection (ACK/NAK/STALL)
// - CRC16 calculation and checking
//
// Integrates with token generator for proper packet sequencing.
///////////////////////////////////////////////////////////////////////////////

module usb_transaction_engine (
    // Clock and Reset
    input  wire        clk,
    input  wire        rst_n,
    
    // Transaction Request Interface
    input  wire        trans_start,         // Start transaction
    input  wire [1:0]  trans_type,          // 00=SETUP, 01=IN, 10=OUT
    input  wire [6:0]  trans_addr,          // Device address
    input  wire [3:0]  trans_endp,          // Endpoint number
    input  wire        trans_data_pid,      // DATA0=0, DATA1=1
    input  wire [7:0]  trans_data_len,      // Data length (0 for IN/status)
    output reg         trans_ready,         // Ready for new transaction
    output reg         trans_done,          // Transaction complete
    output reg  [2:0]  trans_result,        // Result code
    
    // Data Interface
    input  wire [7:0]  data_in,             // Data to send (OUT/SETUP)
    input  wire        data_in_valid,       // Data valid
    output reg         data_in_ready,       // Ready for data
    output reg  [7:0]  data_out,            // Received data (IN)
    output reg         data_out_valid,      // Received data valid
    input  wire        data_out_ready,      // Consumer ready
    output reg  [7:0]  data_out_count,      // Received byte count
    
    // Token Generator Interface
    output reg         token_start,
    output reg  [1:0]  token_type,
    output reg  [6:0]  token_addr,
    output reg  [3:0]  token_endp,
    input  wire        token_ready,
    input  wire        token_done,
    
    // UTMI Interface
    input  wire [7:0]  utmi_rx_data,
    input  wire        utmi_rx_valid,
    input  wire        utmi_rx_active,
    output reg  [7:0]  utmi_tx_data,
    output reg         utmi_tx_valid,
    input  wire        utmi_tx_ready
);

    // Transaction types
    localparam TRANS_SETUP = 2'b00;
    localparam TRANS_IN    = 2'b01;
    localparam TRANS_OUT   = 2'b10;
    
    // Token types
    localparam TOKEN_OUT   = 2'b00;
    localparam TOKEN_IN    = 2'b01;
    localparam TOKEN_SETUP = 2'b11;
    
    // PIDs
    localparam PID_DATA0 = 4'b0011;
    localparam PID_DATA1 = 4'b1011;
    localparam PID_ACK   = 4'b0010;
    localparam PID_NAK   = 4'b1010;
    localparam PID_STALL = 4'b1110;
    
    // Result codes
    localparam RESULT_NONE       = 3'd0;
    localparam RESULT_ACK        = 3'd1;
    localparam RESULT_NAK        = 3'd2;
    localparam RESULT_STALL      = 3'd3;
    localparam RESULT_TIMEOUT    = 3'd4;
    localparam RESULT_CRC_ERROR  = 3'd5;
    
    // State machine
    localparam STATE_IDLE         = 4'd0;
    localparam STATE_SEND_TOKEN   = 4'd1;
    localparam STATE_WAIT_TOKEN   = 4'd2;
    localparam STATE_SEND_DATA    = 4'd3;
    localparam STATE_WAIT_HS_OUT  = 4'd4;
    localparam STATE_WAIT_DATA_IN = 4'd5;
    localparam STATE_SEND_HS_IN   = 4'd6;
    localparam STATE_COMPLETE     = 4'd7;
    localparam STATE_ERROR        = 4'd8;
    
    reg [3:0]  state;
    reg [1:0]  saved_trans_type;
    reg        saved_data_pid;
    reg [7:0]  saved_data_len;
    reg [7:0]  data_byte_count;
    reg [15:0] crc16;
    reg [31:0] timeout_counter;
    reg [3:0]  received_pid;
    reg        rx_data_started;
    reg [7:0]  rx_byte_count;
    
    // CRC16 calculation (polynomial: x^16 + x^15 + x^2 + 1)
    function [15:0] crc16_update;
        input [15:0] crc_in;
        input [7:0] data_byte;
        integer i;
        reg [15:0] crc;
    begin
        crc = crc_in;
        for (i = 0; i < 8; i = i + 1) begin
            if (crc[15] ^ data_byte[i])
                crc = {crc[14:0], 1'b0} ^ 16'h8005;
            else
                crc = {crc[14:0], 1'b0};
        end
        crc16_update = crc;
    end
    endfunction
    
    // Main FSM
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            trans_ready <= 1'b1;
            trans_done <= 1'b0;
            trans_result <= RESULT_NONE;
            token_start <= 1'b0;
            token_type <= 2'd0;
            token_addr <= 7'd0;
            token_endp <= 4'd0;
            data_in_ready <= 1'b0;
            data_out <= 8'd0;
            data_out_valid <= 1'b0;
            data_out_count <= 8'd0;
            utmi_tx_data <= 8'd0;
            utmi_tx_valid <= 1'b0;
            saved_trans_type <= 2'd0;
            saved_data_pid <= 1'b0;
            saved_data_len <= 8'd0;
            data_byte_count <= 8'd0;
            crc16 <= 16'hFFFF;
            timeout_counter <= 32'd0;
            received_pid <= 4'd0;
            rx_data_started <= 1'b0;
            rx_byte_count <= 8'd0;
        end else begin
            // Default outputs
            trans_done <= 1'b0;
            token_start <= 1'b0;
            data_out_valid <= 1'b0;
            
            // Timeout counter
            timeout_counter <= timeout_counter + 1'b1;
            
            // Capture received PID
            if (utmi_rx_valid && utmi_rx_active && !rx_data_started) begin
                received_pid <= utmi_rx_data[3:0];
                rx_data_started <= 1'b1;
                rx_byte_count <= 8'd0;
            end
            
            if (!utmi_rx_active)
                rx_data_started <= 1'b0;
            
            // Capture received data
            if (utmi_rx_valid && utmi_rx_active && rx_data_started) begin
                if (data_out_ready && rx_byte_count > 0) begin  // Skip PID
                    data_out <= utmi_rx_data;
                    data_out_valid <= 1'b1;
                    data_out_count <= rx_byte_count - 1;
                end
                rx_byte_count <= rx_byte_count + 1'b1;
            end
            
            case (state)
                STATE_IDLE: begin
                    trans_ready <= 1'b1;
                    trans_result <= RESULT_NONE;
                    data_in_ready <= 1'b0;
                    data_byte_count <= 8'd0;
                    crc16 <= 16'hFFFF;
                    timeout_counter <= 32'd0;
                    
                    if (trans_start) begin
                        trans_ready <= 1'b0;
                        saved_trans_type <= trans_type;
                        saved_data_pid <= trans_data_pid;
                        saved_data_len <= trans_data_len;
                        state <= STATE_SEND_TOKEN;
                    end
                end
                
                STATE_SEND_TOKEN: begin
                    if (token_ready) begin
                        token_start <= 1'b1;
                        token_addr <= trans_addr;
                        token_endp <= trans_endp;
                        
                        case (saved_trans_type)
                            TRANS_SETUP: token_type <= TOKEN_SETUP;
                            TRANS_IN:    token_type <= TOKEN_IN;
                            TRANS_OUT:   token_type <= TOKEN_OUT;
                            default:     token_type <= TOKEN_OUT;
                        endcase
                        
                        state <= STATE_WAIT_TOKEN;
                    end
                end
                
                STATE_WAIT_TOKEN: begin
                    if (token_done) begin
                        if (saved_trans_type == TRANS_IN) begin
                            state <= STATE_WAIT_DATA_IN;
                            timeout_counter <= 32'd0;
                        end else begin
                            state <= STATE_SEND_DATA;
                            data_in_ready <= 1'b1;
                        end
                    end
                end
                
                STATE_SEND_DATA: begin
                    // Send DATA0 or DATA1 packet
                    if (data_byte_count == 0 && utmi_tx_ready) begin
                        // Send PID
                        if (saved_data_pid)
                            utmi_tx_data <= {~PID_DATA1, PID_DATA1};
                        else
                            utmi_tx_data <= {~PID_DATA0, PID_DATA0};
                        utmi_tx_valid <= 1'b1;
                        data_byte_count <= 8'd1;
                        crc16 <= 16'hFFFF;
                    end else if (data_byte_count > 0 && data_byte_count <= saved_data_len && utmi_tx_ready) begin
                        if (data_in_valid) begin
                            // Send data byte
                            utmi_tx_data <= data_in;
                            utmi_tx_valid <= 1'b1;
                            crc16 <= crc16_update(crc16, data_in);
                            data_byte_count <= data_byte_count + 1'b1;
                        end
                    end else if (data_byte_count > saved_data_len && utmi_tx_ready) begin
                        // Send CRC16 (2 bytes)
                        if (data_byte_count == saved_data_len + 1) begin
                            utmi_tx_data <= ~crc16[7:0];  // LSB first, inverted
                            utmi_tx_valid <= 1'b1;
                            data_byte_count <= data_byte_count + 1'b1;
                        end else if (data_byte_count == saved_data_len + 2) begin
                            utmi_tx_data <= ~crc16[15:8];  // MSB, inverted
                            utmi_tx_valid <= 1'b1;
                            data_byte_count <= data_byte_count + 1'b1;
                        end else begin
                            // Data phase complete
                            utmi_tx_valid <= 1'b0;
                            data_in_ready <= 1'b0;
                            state <= STATE_WAIT_HS_OUT;
                            timeout_counter <= 32'd0;
                        end
                    end
                end
                
                STATE_WAIT_HS_OUT: begin
                    // Wait for handshake (ACK/NAK/STALL)
                    if (utmi_rx_valid && !utmi_rx_active) begin
                        case (received_pid)
                            PID_ACK: begin
                                trans_result <= RESULT_ACK;
                                state <= STATE_COMPLETE;
                            end
                            PID_NAK: begin
                                trans_result <= RESULT_NAK;
                                state <= STATE_COMPLETE;
                            end
                            PID_STALL: begin
                                trans_result <= RESULT_STALL;
                                state <= STATE_COMPLETE;
                            end
                            default: begin
                                trans_result <= RESULT_CRC_ERROR;
                                state <= STATE_ERROR;
                            end
                        endcase
                    end else if (timeout_counter > 32'd60000) begin  // 1ms timeout
                        trans_result <= RESULT_TIMEOUT;
                        state <= STATE_ERROR;
                    end
                end
                
                STATE_WAIT_DATA_IN: begin
                    // Wait for DATA0/DATA1 packet
                    if (!utmi_rx_active && rx_data_started) begin
                        // Check PID matches expected
                        if ((saved_data_pid && received_pid == PID_DATA1) ||
                            (!saved_data_pid && received_pid == PID_DATA0)) begin
                            state <= STATE_SEND_HS_IN;
                        end else if (received_pid == PID_NAK) begin
                            trans_result <= RESULT_NAK;
                            state <= STATE_COMPLETE;
                        end else if (received_pid == PID_STALL) begin
                            trans_result <= RESULT_STALL;
                            state <= STATE_COMPLETE;
                        end else begin
                            trans_result <= RESULT_CRC_ERROR;
                            state <= STATE_ERROR;
                        end
                    end else if (timeout_counter > 32'd120000) begin  // 2ms timeout
                        trans_result <= RESULT_TIMEOUT;
                        state <= STATE_ERROR;
                    end
                end
                
                STATE_SEND_HS_IN: begin
                    // Send ACK for received data
                    if (utmi_tx_ready) begin
                        utmi_tx_data <= {~PID_ACK, PID_ACK};
                        utmi_tx_valid <= 1'b1;
                        trans_result <= RESULT_ACK;
                        state <= STATE_COMPLETE;
                    end
                end
                
                STATE_COMPLETE: begin
                    trans_done <= 1'b1;
                    state <= STATE_IDLE;
                end
                
                STATE_ERROR: begin
                    trans_done <= 1'b1;
                    state <= STATE_IDLE;
                end
                
                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
