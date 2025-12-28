///////////////////////////////////////////////////////////////////////////////
// File: usb_protocol_handler.v (FIXED VERSION)
// Description: USB Protocol Handler for transparent proxy implementation
//
// FIXES APPLIED:
// - CRITICAL: Merged two always blocks that both drove 'state' into ONE
// - Added proper RX/TX separation with is_transmitting flag
// - Removed unused tx_data_buffer
// - Improved state flow
//
// Target: Lattice ECP5 on Cynthion device
///////////////////////////////////////////////////////////////////////////////

module usb_protocol_handler (
    // Clock and Reset
    input  wire        clk,
    input  wire        rst_n,

    // UTMI Interface from PHY
    input  wire [7:0]  utmi_rx_data,
    input  wire        utmi_rx_valid,
    input  wire        utmi_rx_active,
    input  wire        utmi_rx_error,
    input  wire [1:0]  utmi_line_state,
    output reg  [7:0]  utmi_tx_data,
    output reg         utmi_tx_valid,
    input  wire        utmi_tx_ready,
    output reg  [1:0]  utmi_tx_op_mode,
    output reg  [1:0]  utmi_xcvr_select,
    output reg         utmi_termselect,
    output reg         utmi_dppulldown,
    output reg         utmi_dmpulldown,

    // Protocol Decoded Interface
    output reg  [7:0]  packet_data,
    output reg         packet_valid,
    output reg         packet_sop,
    output reg         packet_eop,
    output reg  [3:0]  pid,
    output reg  [6:0]  dev_addr,
    output reg  [3:0]  endp,
    output reg         crc_valid,
    
    // Protocol Control Interface
    input  wire [7:0]  tx_packet_data,
    input  wire        tx_packet_valid,
    input  wire        tx_packet_sop,
    input  wire        tx_packet_eop,
    output wire        tx_packet_ready,
    input  wire [3:0]  tx_pid,
    
    // Configuration and Status
    input  wire [6:0]  device_address,
    input  wire [1:0]  usb_speed,
    output reg         conn_detect,
    output reg  [1:0]  conn_speed,
    output reg         reset_detect,
    output reg         suspend_detect,
    output reg         resume_detect
);

    // PIDs
    localparam PID_OUT   = 4'b0001;
    localparam PID_IN    = 4'b1001;
    localparam PID_SETUP = 4'b1101;
    localparam PID_DATA0 = 4'b0011;
    localparam PID_DATA1 = 4'b1011;
    localparam PID_DATA2 = 4'b0111;
    localparam PID_MDATA = 4'b1111;
    localparam PID_ACK   = 4'b0010;
    localparam PID_NAK   = 4'b1010;
    localparam PID_STALL = 4'b1110;
    localparam PID_NYET  = 4'b0110;
    localparam PID_PRE   = 4'b1100;
    localparam PID_SOF   = 4'b0101;
    localparam PID_PING  = 4'b0100;
    localparam PID_SPLIT = 4'b1000;

    // COMBINED FSM states (RX and TX merged)
    localparam ST_IDLE       = 4'd0;
    localparam ST_RX_PID     = 4'd1;
    localparam ST_RX_TOKEN   = 4'd2;
    localparam ST_RX_DATA    = 4'd3;
    localparam ST_RX_CRC     = 4'd4;
    localparam ST_TX_PID     = 4'd5;
    localparam ST_TX_DATA    = 4'd6;
    localparam ST_TX_CRC     = 4'd7;
    localparam ST_TX_EOP     = 4'd8;
    localparam ST_WAIT_EOP   = 4'd9;
    
    // Internal registers
    reg [3:0]  state;
    reg        is_transmitting;      // ADDED: Track if in TX or RX mode
    reg [15:0] token_data;
    reg [15:0] crc16;
    reg [4:0]  crc5;
    reg [2:0]  byte_cnt;
    reg [3:0]  tx_byte_cnt;
    reg [3:0]  tx_length;
    reg [3:0]  tx_current_pid;       // ADDED: Store PID for TX state machine
    integer    i;
    
    // Line state monitoring
    reg [19:0] se0_counter;
    reg [23:0] idle_counter;
    
    // CRC5 polynomial
    function [4:0] crc5_update;
        input [4:0] crc_in;
        input data_bit;
        reg feedback;
    begin
        feedback = data_bit ^ crc_in[4];
        crc5_update = {crc_in[3:0], 1'b0};
        if (feedback) begin
            crc5_update = crc5_update ^ 5'b00101;
        end
    end
    endfunction
    
    // CRC16 polynomial
    function [15:0] crc16_update;
        input [15:0] crc_in;
        input data_bit;
        reg feedback;
    begin
        feedback = data_bit ^ crc_in[15];
        crc16_update = {crc_in[14:0], 1'b0};
        if (feedback) begin
            crc16_update = crc16_update ^ 16'h8005;
        end
    end
    endfunction

    // USB reset, suspend, resume detection (unchanged)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            se0_counter <= 20'd0;
            idle_counter <= 24'd0;
            reset_detect <= 1'b0;
            suspend_detect <= 1'b0;
            resume_detect <= 1'b0;
        end else begin
            if (utmi_line_state == 2'b00) begin
                if (se0_counter < 20'hFFFFF) begin
                    se0_counter <= se0_counter + 1'b1;
                end
                if (se0_counter == 20'd150) begin
                    reset_detect <= 1'b1;
                end
            end else begin
                se0_counter <= 20'd0;
                if (se0_counter > 20'd150) begin
                    reset_detect <= 1'b0;
                end
            end
            
            if (utmi_line_state == 2'b01) begin
                if (idle_counter < 24'hFFFFFF) begin
                    idle_counter <= idle_counter + 1'b1;
                end
                if (idle_counter == 24'd180000) begin
                    suspend_detect <= 1'b1;
                end
            end else begin
                idle_counter <= 24'd0;
                if (idle_counter > 24'd180000 && utmi_line_state == 2'b10) begin
                    resume_detect <= 1'b1;
                    suspend_detect <= 1'b0;
                end else begin
                    resume_detect <= 1'b0;
                end
            end
        end
    end

    // FIXED: SINGLE state machine for both RX and TX
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            is_transmitting <= 1'b0;
            packet_data <= 8'd0;
            packet_valid <= 1'b0;
            packet_sop <= 1'b0;
            packet_eop <= 1'b0;
            pid <= 4'd0;
            dev_addr <= 7'd0;
            endp <= 4'd0;
            crc_valid <= 1'b0;
            token_data <= 16'd0;
            byte_cnt <= 3'd0;
            crc5 <= 5'b11111;
            crc16 <= 16'hFFFF;
            utmi_tx_data <= 8'd0;
            utmi_tx_valid <= 1'b0;
            utmi_tx_op_mode <= 2'b00;
            tx_byte_cnt <= 4'd0;
            tx_length <= 4'd0;
            tx_current_pid <= 4'd0;
        end else begin
            // Default: clear one-cycle signals
            packet_valid <= 1'b0;
            packet_sop <= 1'b0;
            packet_eop <= 1'b0;
            utmi_tx_valid <= 1'b0;
            
            case (state)
                ST_IDLE: begin
                    byte_cnt <= 3'd0;
                    tx_byte_cnt <= 4'd0;
                    
                    // Priority: Check RX first
                    if (utmi_rx_active && utmi_rx_valid && !is_transmitting) begin
                        state <= ST_RX_PID;
                        is_transmitting <= 1'b0;
                        crc5 <= 5'b11111;
                        crc16 <= 16'hFFFF;
                    // Then check TX request
                    end else if (tx_packet_valid && tx_packet_sop && !utmi_rx_active) begin
                        state <= ST_TX_PID;
                        is_transmitting <= 1'b1;
                        tx_current_pid <= tx_pid;
                        utmi_tx_valid <= 1'b1;
                        utmi_tx_data <= {~tx_pid, tx_pid};
                    end
                end
                
                // ===== RX STATES =====
                ST_RX_PID: begin
                    if (utmi_rx_valid) begin
                        pid <= utmi_rx_data[3:0];
                        packet_sop <= 1'b1;
                        
                        case (utmi_rx_data[3:0])
                            PID_OUT, PID_IN, PID_SETUP, PID_PING, PID_SOF: begin
                                state <= ST_RX_TOKEN;
                                byte_cnt <= 3'd0;
                            end
                            
                            PID_DATA0, PID_DATA1, PID_DATA2, PID_MDATA: begin
                                state <= ST_RX_DATA;
                                crc16 <= 16'hFFFF;
                            end
                            
                            default: begin
                                state <= ST_WAIT_EOP;
                            end
                        endcase
                    end
                end
                
                ST_RX_TOKEN: begin
                    if (utmi_rx_valid) begin
                        token_data <= {utmi_rx_data, token_data[15:8]};
                        byte_cnt <= byte_cnt + 1'b1;
                        
                        for (i=0; i<8; i=i+1) begin
                            crc5 <= crc5_update(crc5, utmi_rx_data[i]);
                        end
                        
                        if (byte_cnt == 3'd1) begin
                            dev_addr <= token_data[6:0];
                            endp <= {utmi_rx_data[2:0], token_data[7]};
                            state <= ST_WAIT_EOP;
                        end
                    end
                    
                    if (!utmi_rx_active) begin
                        state <= ST_IDLE;
                        packet_eop <= 1'b1;
                        crc_valid <= (crc5 == 5'b01100);
                    end
                end
                
                ST_RX_DATA: begin
                    if (!utmi_rx_active) begin
                        state <= ST_IDLE;
                        packet_eop <= 1'b1;
                        crc_valid <= (crc16 == 16'hB001);
                    end else if (utmi_rx_valid) begin
                        packet_valid <= 1'b1;
                        packet_data <= utmi_rx_data;
                        
                        for (i=0; i<8; i=i+1) begin
                            crc16 <= crc16_update(crc16, utmi_rx_data[i]);
                        end
                    end
                end
                
                ST_WAIT_EOP: begin
                    if (!utmi_rx_active) begin
                        state <= ST_IDLE;
                        packet_eop <= 1'b1;
                    end
                end
                
                // ===== TX STATES =====
                ST_TX_PID: begin
                    if (utmi_tx_ready) begin
                        case (tx_current_pid)
                            PID_OUT, PID_IN, PID_SETUP, PID_PING, PID_SOF: begin
                                state <= ST_TX_DATA;
                                tx_length <= 4'd2;
                            end
                            
                            PID_DATA0, PID_DATA1, PID_DATA2, PID_MDATA: begin
                                state <= ST_TX_DATA;
                            end
                            
                            default: begin
                                // Handshake - PID only
                                state <= ST_TX_EOP;
                            end
                        endcase
                    end
                end
                
                ST_TX_DATA: begin
                    if (utmi_tx_ready) begin
                        if (tx_packet_valid) begin
                            utmi_tx_data <= tx_packet_data;
                            utmi_tx_valid <= 1'b1;
                            tx_byte_cnt <= tx_byte_cnt + 1'b1;
                            
                            // Update CRC on-the-fly
                            for (i=0; i<8; i=i+1) begin
                                crc16 <= crc16_update(crc16, tx_packet_data[i]);
                            end
                            
                            if (tx_packet_eop) begin
                                state <= ST_TX_CRC;
                            end
                        end else begin
                            utmi_tx_valid <= 1'b0;
                        end
                    end
                end
                
                ST_TX_CRC: begin
                    if (utmi_tx_ready) begin
                        case (tx_current_pid)
                            PID_OUT, PID_IN, PID_SETUP, PID_PING, PID_SOF: begin
                                // Send CRC5 for token packets
                                utmi_tx_valid <= 1'b1;
                                utmi_tx_data <= {3'b000, ~crc5};
                                state <= ST_TX_EOP;
                            end
                            
                            PID_DATA0, PID_DATA1, PID_DATA2, PID_MDATA: begin
                                // Send CRC16 LSB first
                                if (tx_byte_cnt == 4'd0) begin
                                    utmi_tx_valid <= 1'b1;
                                    utmi_tx_data <= ~crc16[7:0];
                                    tx_byte_cnt <= 4'd1;
                                end else begin
                                    utmi_tx_valid <= 1'b1;
                                    utmi_tx_data <= ~crc16[15:8];
                                    state <= ST_TX_EOP;
                                end
                            end
                            
                            default: begin
                                state <= ST_TX_EOP;
                            end
                        endcase
                    end
                end
                
                ST_TX_EOP: begin
                    if (utmi_tx_ready) begin
                        utmi_tx_valid <= 1'b0;
                        state <= ST_IDLE;
                        is_transmitting <= 1'b0;
                    end
                end
                
                default: begin
                    state <= ST_IDLE;
                    is_transmitting <= 1'b0;
                end
            endcase
            
            // Handle RX errors
            if (utmi_rx_error) begin
                state <= ST_IDLE;
                crc_valid <= 1'b0;
                is_transmitting <= 1'b0;
            end
        end
    end
    
    // Connection detection
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            conn_detect <= 1'b0;
            conn_speed <= 2'b00;
        end else begin
            if (utmi_line_state != 2'b00) begin
                conn_detect <= 1'b1;
                if (reset_detect && se0_counter > 20'd300) begin
                    conn_speed <= 2'b10;
                end else begin
                    conn_speed <= 2'b01;
                end
            end else if (se0_counter > 20'd10000) begin
                conn_detect <= 1'b0;
            end
        end
    end
    
    // Configuration outputs
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            utmi_xcvr_select <= 2'b01;
            utmi_termselect <= 1'b1;
            utmi_dppulldown <= 1'b0;
            utmi_dmpulldown <= 1'b0;
        end else begin
            utmi_xcvr_select <= usb_speed;
            
            case (usb_speed)
                2'b00: begin
                    utmi_termselect <= 1'b1;
                    utmi_dppulldown <= 1'b0;
                    utmi_dmpulldown <= 1'b1;
                end
                2'b01: begin
                    utmi_termselect <= 1'b1;
                    utmi_dppulldown <= 1'b0;
                    utmi_dmpulldown <= 1'b0;
                end
                2'b10: begin
                    utmi_termselect <= 1'b0;
                    utmi_dppulldown <= 1'b0;
                    utmi_dmpulldown <= 1'b0;
                end
                default: begin
                    utmi_termselect <= 1'b1;
                    utmi_dppulldown <= 1'b0;
                    utmi_dmpulldown <= 1'b0;
                end
            endcase
        end
    end
    
    // Ready signal
    assign tx_packet_ready = (state == ST_IDLE && !utmi_rx_active) || 
                             (state == ST_TX_DATA && utmi_tx_ready);

endmodule