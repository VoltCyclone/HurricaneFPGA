///////////////////////////////////////////////////////////////////////////////
// File: tb_usb_token_generator.v
// Description: Testbench for USB Token Generator
//
// Tests token packet generation with CRC5 calculation.
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module tb_usb_token_generator;

    // Clock and Reset
    reg        clk;
    reg        rst_n;
    
    // Token Request Interface
    reg        token_start;
    reg  [1:0] token_type;
    reg  [6:0] token_addr;
    reg  [3:0] token_endp;
    reg  [10:0] token_frame;
    wire       token_ready;
    wire       token_done;
    
    // UTMI Transmit Interface
    wire [7:0] utmi_tx_data;
    wire       utmi_tx_valid;
    reg        utmi_tx_ready;
    
    // Instantiate DUT
    usb_token_generator dut (
        .clk(clk),
        .rst_n(rst_n),
        .token_start(token_start),
        .token_type(token_type),
        .token_addr(token_addr),
        .token_endp(token_endp),
        .token_frame(token_frame),
        .token_ready(token_ready),
        .token_done(token_done),
        .utmi_tx_data(utmi_tx_data),
        .utmi_tx_valid(utmi_tx_valid),
        .utmi_tx_ready(utmi_tx_ready)
    );
    
    // Clock generation (60MHz)
    initial begin
        clk = 0;
        forever #8.333 clk = ~clk;  // 60MHz = 16.666ns period
    end
    
    // Test sequence
    initial begin
        // Initialize
        rst_n = 0;
        token_start = 0;
        token_type = 0;
        token_addr = 0;
        token_endp = 0;
        token_frame = 0;
        utmi_tx_ready = 1;
        
        // Dump waveforms
        $dumpfile("tb_usb_token_generator.vcd");
        $dumpvars(0, tb_usb_token_generator);
        
        // Reset
        #100;
        rst_n = 1;
        #100;
        
        // Test 1: Generate SETUP token to address 0, endpoint 0
        $display("Test 1: SETUP token (addr=0, endp=0)");
        @(posedge clk);
        token_type = 2'b11;  // SETUP
        token_addr = 7'd0;
        token_endp = 4'd0;
        token_start = 1;
        @(posedge clk);
        token_start = 0;
        
        // Wait for completion
        wait(token_done);
        #100;
        
        // Test 2: Generate IN token to address 1, endpoint 1
        $display("Test 2: IN token (addr=1, endp=1)");
        @(posedge clk);
        token_type = 2'b01;  // IN
        token_addr = 7'd1;
        token_endp = 4'd1;
        token_start = 1;
        @(posedge clk);
        token_start = 0;
        
        wait(token_done);
        #100;
        
        // Test 3: Generate SOF token with frame 123
        $display("Test 3: SOF token (frame=123)");
        @(posedge clk);
        token_type = 2'b10;  // SOF
        token_frame = 11'd123;
        token_start = 1;
        @(posedge clk);
        token_start = 0;
        
        wait(token_done);
        #100;
        
        // Test 4: Generate OUT token to address 5, endpoint 2
        $display("Test 4: OUT token (addr=5, endp=2)");
        @(posedge clk);
        token_type = 2'b00;  // OUT
        token_addr = 7'd5;
        token_endp = 4'd2;
        token_start = 1;
        @(posedge clk);
        token_start = 0;
        
        wait(token_done);
        #100;
        
        $display("All tests completed");
        $finish;
    end
    
    // Monitor transmitted bytes
    always @(posedge clk) begin
        if (utmi_tx_valid && utmi_tx_ready) begin
            $display("Time %0t: TX Data = 0x%02h", $time, utmi_tx_data);
        end
    end

endmodule
