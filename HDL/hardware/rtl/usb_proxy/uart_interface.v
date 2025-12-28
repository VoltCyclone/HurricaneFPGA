///////////////////////////////////////////////////////////////////////////////
// File: uart_interface.v
// Description: UART interface for SAMD51 communication
//
// This module provides UART0 communication to the SAMD51 microcontroller,
// which bridges to USB CDC-ACM for host PC access. This eliminates the need
// for external UART adapters and provides cleaner integration.
//
// Features:
// - 115200 baud rate (configurable)
// - 8N1 format (8 data bits, no parity, 1 stop bit)
// - TX buffer for status/debug output
// - RX buffer for control commands
// - Compatible with Apollo firmware CDC-ACM bridge
//
// Connection: FPGA UART0 <-> SAMD51 <-> USB CDC-ACM <-> Host PC
//
// Target: Lattice ECP5 on Cynthion device
///////////////////////////////////////////////////////////////////////////////

module uart_interface #(
    parameter CLK_FREQ = 60_000_000,    // System clock frequency (Hz)
    parameter BAUD_RATE = 115200,       // UART baud rate
    parameter TX_FIFO_DEPTH = 256,      // Transmit FIFO depth
    parameter RX_FIFO_DEPTH = 256       // Receive FIFO depth
)(
    // Clock and Reset
    input  wire        clk,             // System clock
    input  wire        rst_n,           // Active low reset
    
    // UART Physical Interface (to SAMD51)
    input  wire        uart_rx,         // UART receive (from SAMD51)
    output wire        uart_tx,         // UART transmit (to SAMD51)
    
    // Data Interface
    input  wire [7:0]  tx_data,         // Data to transmit
    input  wire        tx_valid,        // Transmit data valid
    output wire        tx_ready,        // Ready to accept transmit data
    
    output wire [7:0]  rx_data,         // Received data
    output wire        rx_valid,        // Receive data valid
    input  wire        rx_ready,        // Ready to accept received data
    
    // Status
    output wire        tx_busy,         // Transmitter busy
    output wire        rx_error,        // Receive error (framing/overrun)
    output wire [7:0]  tx_fifo_used,    // TX FIFO occupancy
    output wire [7:0]  rx_fifo_used     // RX FIFO occupancy
);

    // Baud rate divider calculation
    localparam BAUD_DIV = CLK_FREQ / BAUD_RATE;
    localparam BAUD_WIDTH = $clog2(BAUD_DIV);
    
    // UART TX state machine
    localparam TX_IDLE  = 3'd0;
    localparam TX_START = 3'd1;
    localparam TX_DATA  = 3'd2;
    localparam TX_STOP  = 3'd3;
    
    // UART RX state machine
    localparam RX_IDLE  = 3'd0;
    localparam RX_START = 3'd1;
    localparam RX_DATA  = 3'd2;
    localparam RX_STOP  = 3'd3;
    
    // Transmitter signals
    reg [2:0]  tx_state;
    reg [BAUD_WIDTH-1:0] tx_baud_counter;
    reg [2:0]  tx_bit_counter;
    reg [7:0]  tx_shift_reg;
    reg        tx_line;
    
    // Receiver signals
    reg [2:0]  rx_state;
    reg [BAUD_WIDTH-1:0] rx_baud_counter;
    reg [2:0]  rx_bit_counter;
    reg [7:0]  rx_shift_reg;
    reg [1:0]  rx_sync;
    reg        rx_frame_error;
    
    // FIFO signals
    wire [7:0] tx_fifo_data;
    wire       tx_fifo_empty;
    wire       tx_fifo_full;
    wire       tx_fifo_rd_en;
    
    wire       rx_fifo_wr_en;
    wire       rx_fifo_full;
    wire       rx_fifo_empty;
    
    // Synchronize RX input
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rx_sync <= 2'b11;
        else
            rx_sync <= {rx_sync[0], uart_rx};
    end
    
    wire uart_rx_sync = rx_sync[1];
    
    // =======================================================================
    // UART Transmitter
    // =======================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state <= TX_IDLE;
            tx_baud_counter <= 0;
            tx_bit_counter <= 0;
            tx_shift_reg <= 8'h00;
            tx_line <= 1'b1;  // Idle high
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    tx_line <= 1'b1;
                    if (!tx_fifo_empty) begin
                        tx_shift_reg <= tx_fifo_data;
                        tx_state <= TX_START;
                        tx_baud_counter <= 0;
                    end
                end
                
                TX_START: begin
                    tx_line <= 1'b0;  // Start bit
                    if (tx_baud_counter == BAUD_DIV - 1) begin
                        tx_baud_counter <= 0;
                        tx_bit_counter <= 0;
                        tx_state <= TX_DATA;
                    end else begin
                        tx_baud_counter <= tx_baud_counter + 1'b1;
                    end
                end
                
                TX_DATA: begin
                    tx_line <= tx_shift_reg[0];
                    if (tx_baud_counter == BAUD_DIV - 1) begin
                        tx_baud_counter <= 0;
                        tx_shift_reg <= {1'b0, tx_shift_reg[7:1]};
                        if (tx_bit_counter == 7) begin
                            tx_state <= TX_STOP;
                        end else begin
                            tx_bit_counter <= tx_bit_counter + 1'b1;
                        end
                    end else begin
                        tx_baud_counter <= tx_baud_counter + 1'b1;
                    end
                end
                
                TX_STOP: begin
                    tx_line <= 1'b1;  // Stop bit
                    if (tx_baud_counter == BAUD_DIV - 1) begin
                        tx_baud_counter <= 0;
                        tx_state <= TX_IDLE;
                    end else begin
                        tx_baud_counter <= tx_baud_counter + 1'b1;
                    end
                end
                
                default: tx_state <= TX_IDLE;
            endcase
        end
    end
    
    assign uart_tx = tx_line;
    assign tx_fifo_rd_en = (tx_state == TX_IDLE && !tx_fifo_empty);
    assign tx_busy = (tx_state != TX_IDLE);
    
    // =======================================================================
    // UART Receiver
    // =======================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state <= RX_IDLE;
            rx_baud_counter <= 0;
            rx_bit_counter <= 0;
            rx_shift_reg <= 8'h00;
            rx_frame_error <= 1'b0;
        end else begin
            case (rx_state)
                RX_IDLE: begin
                    rx_frame_error <= 1'b0;
                    if (uart_rx_sync == 1'b0) begin  // Start bit detected
                        rx_state <= RX_START;
                        rx_baud_counter <= 0;
                    end
                end
                
                RX_START: begin
                    // Wait for middle of start bit
                    if (rx_baud_counter == (BAUD_DIV / 2)) begin
                        if (uart_rx_sync == 1'b0) begin  // Valid start bit
                            rx_baud_counter <= 0;
                            rx_bit_counter <= 0;
                            rx_state <= RX_DATA;
                        end else begin  // False start bit
                            rx_state <= RX_IDLE;
                        end
                    end else begin
                        rx_baud_counter <= rx_baud_counter + 1'b1;
                    end
                end
                
                RX_DATA: begin
                    if (rx_baud_counter == BAUD_DIV - 1) begin
                        rx_baud_counter <= 0;
                        rx_shift_reg <= {uart_rx_sync, rx_shift_reg[7:1]};
                        if (rx_bit_counter == 7) begin
                            rx_state <= RX_STOP;
                        end else begin
                            rx_bit_counter <= rx_bit_counter + 1'b1;
                        end
                    end else begin
                        rx_baud_counter <= rx_baud_counter + 1'b1;
                    end
                end
                
                RX_STOP: begin
                    if (rx_baud_counter == BAUD_DIV - 1) begin
                        rx_baud_counter <= 0;
                        if (uart_rx_sync == 1'b1) begin  // Valid stop bit
                            rx_frame_error <= 1'b0;
                        end else begin  // Framing error
                            rx_frame_error <= 1'b1;
                        end
                        rx_state <= RX_IDLE;
                    end else begin
                        rx_baud_counter <= rx_baud_counter + 1'b1;
                    end
                end
                
                default: rx_state <= RX_IDLE;
            endcase
        end
    end
    
    assign rx_fifo_wr_en = (rx_state == RX_STOP && rx_baud_counter == BAUD_DIV - 1 && !rx_frame_error);
    assign rx_error = rx_frame_error;
    
    // =======================================================================
    // Transmit FIFO
    // =======================================================================
    
    simple_fifo #(
        .DATA_WIDTH(8),
        .DEPTH(TX_FIFO_DEPTH)
    ) tx_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .wr_data(tx_data),
        .wr_en(tx_valid && !tx_fifo_full),
        .rd_data(tx_fifo_data),
        .rd_en(tx_fifo_rd_en),
        .empty(tx_fifo_empty),
        .full(tx_fifo_full),
        .used(tx_fifo_used)
    );
    
    assign tx_ready = !tx_fifo_full;
    
    // =======================================================================
    // Receive FIFO
    // =======================================================================
    
    simple_fifo #(
        .DATA_WIDTH(8),
        .DEPTH(RX_FIFO_DEPTH)
    ) rx_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .wr_data(rx_shift_reg),
        .wr_en(rx_fifo_wr_en && !rx_fifo_full),
        .rd_data(rx_data),
        .rd_en(rx_ready && !rx_fifo_empty),
        .empty(rx_fifo_empty),
        .full(rx_fifo_full),
        .used(rx_fifo_used)
    );
    
    assign rx_valid = !rx_fifo_empty;

endmodule


///////////////////////////////////////////////////////////////////////////////
// Simple FIFO for UART buffers
///////////////////////////////////////////////////////////////////////////////

module simple_fifo #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH = 256
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire [DATA_WIDTH-1:0]   wr_data,
    input  wire                    wr_en,
    output reg  [DATA_WIDTH-1:0]   rd_data,
    input  wire                    rd_en,
    output wire                    empty,
    output wire                    full,
    output wire [7:0]              used
);

    localparam ADDR_WIDTH = $clog2(DEPTH);
    
    (* syn_ramstyle = "block_ram" *) reg [DATA_WIDTH-1:0] mem [DEPTH-1:0];
    reg [DATA_WIDTH-1:0] mem_read_data;  // For BRAM inference
    reg [ADDR_WIDTH:0] wr_ptr;
    reg [ADDR_WIDTH:0] rd_ptr;
    
    wire [ADDR_WIDTH:0] count = wr_ptr - rd_ptr;
    
    assign empty = (count == 0);
    assign full = (count == DEPTH);
    assign used = (count > 255) ? 8'd255 : count[7:0];
    
    // Synchronous read for BRAM inference
    always @(posedge clk) begin
        mem_read_data <= mem[rd_ptr[ADDR_WIDTH-1:0]];
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0;
        end else if (wr_en && !full) begin
            mem[wr_ptr[ADDR_WIDTH-1:0]] <= wr_data;
            wr_ptr <= wr_ptr + 1'b1;
        end
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= 0;
            rd_data <= 0;
        end else if (rd_en && !empty) begin
            rd_data <= mem_read_data;  // Use registered read
            rd_ptr <= rd_ptr + 1'b1;
        end
    end

endmodule
