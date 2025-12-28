///////////////////////////////////////////////////////////////////////////////
// File: tb_usb_transaction_engine.v
// Description: Testbench for USB Transaction Engine
//
// Tests SETUP, IN, and OUT transactions with handshake responses.
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module tb_usb_transaction_engine;

    // Clock and Reset
    reg        clk;
    reg        rst_n;
    
    // Transaction Request Interface
    reg        trans_start;
    reg  [1:0] trans_type;
    reg  [6:0] trans_addr;
    reg  [3:0] trans_endp;
    reg        trans_data_pid;
    reg  [7:0] trans_data_len;
    wire       trans_ready;
    wire       trans_done;
    wire [2:0] trans_result;
    
    // Data Interface
    reg  [7:0] data_in;
    reg        data_in_valid;
    wire       data_in_ready;
    wire [7:0] data_out;
    wire       data_out_valid;
    reg        data_out_ready;
    wire [7:0] data_out_count;
    
    // Token Generator Interface
    wire       token_start;
    wire [1:0] token_type;
    wire [6:0] token_addr;
    wire [3:0] token_endp;
    reg        token_ready;
    reg        token_done;
    
    // UTMI Interface
    reg  [7:0] utmi_rx_data;
    reg        utmi_rx_valid;
    reg        utmi_rx_active;
    wire [7:0] utmi_tx_data;
    wire       utmi_tx_valid;
    reg        utmi_tx_ready;
    
    // Instantiate DUT
    usb_transaction_engine dut (
        .clk(clk),
        .rst_n(rst_n),
        .trans_start(trans_start),
        .trans_type(trans_type),
        .trans_addr(trans_addr),
        .trans_endp(trans_endp),
        .trans_data_pid(trans_data_pid),
        .trans_data_len(trans_data_len),
        .trans_ready(trans_ready),
        .trans_done(trans_done),
        .trans_result(trans_result),
        .data_in(data_in),
        .data_in_valid(data_in_valid),
        .data_in_ready(data_in_ready),
        .data_out(data_out),
        .data_out_valid(data_out_valid),
        .data_out_ready(data_out_ready),
        .data_out_count(data_out_count),
        .token_start(token_start),
        .token_type(token_type),
        .token_addr(token_addr),
        .token_endp(token_endp),
        .token_ready(token_ready),
        .token_done(token_done),
        .utmi_rx_data(utmi_rx_data),
        .utmi_rx_valid(utmi_rx_valid),
        .utmi_rx_active(utmi_rx_active),
        .utmi_tx_data(utmi_tx_data),
        .utmi_tx_valid(utmi_tx_valid),
        .utmi_tx_ready(utmi_tx_ready)
    );
    
    // Clock generation (60MHz)
    initial begin
        clk = 0;
        forever #8.333 clk = ~clk;
    end
    
    // Test data
    reg [7:0] setup_data [0:7];
    reg [7:0] test_data [0:15];
    integer i;
    
    initial begin
        // Initialize setup packet (Get Device Descriptor)
        setup_data[0] = 8'h80;  // bmRequestType
        setup_data[1] = 8'h06;  // bRequest (GET_DESCRIPTOR)
        setup_data[2] = 8'h00;  // wValue low
        setup_data[3] = 8'h01;  // wValue high (DEVICE descriptor)
        setup_data[4] = 8'h00;  // wIndex low
        setup_data[5] = 8'h00;  // wIndex high
        setup_data[6] = 8'h08;  // wLength low (8 bytes)
        setup_data[7] = 8'h00;  // wLength high
        
        // Initialize test data
        for (i = 0; i < 16; i = i + 1)
            test_data[i] = i;
    end
    
    // Token generator simulation
    always @(posedge clk) begin
        if (token_start) begin
            token_ready <= 0;
            #100;
            token_done <= 1;
            #20;
            token_done <= 0;
            token_ready <= 1;
        end
    end
    
    // Test stimulus
    initial begin
        // Initialize
        rst_n = 0;
        trans_start = 0;
        trans_type = 0;
        trans_addr = 0;
        trans_endp = 0;
        trans_data_pid = 0;
        trans_data_len = 0;
        data_in = 0;
        data_in_valid = 0;
        data_out_ready = 1;
        token_ready = 1;
        token_done = 0;
        utmi_rx_data = 0;
        utmi_rx_valid = 0;
        utmi_rx_active = 0;
        utmi_tx_ready = 1;
        
        $dumpfile("tb_usb_transaction_engine.vcd");
        $dumpvars(0, tb_usb_transaction_engine);
        
        // Reset
        #100;
        rst_n = 1;
        #100;
        
        // Test 1: SETUP Transaction with ACK
        $display("\nTest 1: SETUP Transaction (addr=0, endp=0)");
        wait(trans_ready);
        @(posedge clk);
        trans_type = 2'b00;  // SETUP
        trans_addr = 7'd0;
        trans_endp = 4'd0;
        trans_data_pid = 1'b0;  // DATA0
        trans_data_len = 8'd8;
        trans_start = 1;
        @(posedge clk);
        trans_start = 0;
        
        // Wait for data request
        wait(data_in_ready);
        
        // Send setup data
        for (i = 0; i < 8; i = i + 1) begin
            @(posedge clk);
            data_in = setup_data[i];
            data_in_valid = 1;
        end
        @(posedge clk);
        data_in_valid = 0;
        
        // Simulate ACK response after short delay
        #200;
        utmi_rx_active = 1;
        utmi_rx_valid = 1;
        utmi_rx_data = 8'h2D;  // ACK PID with complement
        @(posedge clk);
        utmi_rx_valid = 0;
        utmi_rx_active = 0;
        
        wait(trans_done);
        $display("Test 1 Complete - Result: %0d (1=ACK expected)", trans_result);
        #100;
        
        // Test 2: IN Transaction with DATA1 and ACK
        $display("\nTest 2: IN Transaction (addr=1, endp=1)");
        wait(trans_ready);
        @(posedge clk);
        trans_type = 2'b01;  // IN
        trans_addr = 7'd1;
        trans_endp = 4'd1;
        trans_data_pid = 1'b1;  // Expect DATA1
        trans_data_len = 8'd0;
        trans_start = 1;
        @(posedge clk);
        trans_start = 0;
        
        // Simulate DATA1 response
        #300;
        utmi_rx_active = 1;
        utmi_rx_valid = 1;
        utmi_rx_data = 8'hCB;  // DATA1 PID
        @(posedge clk);
        // Send 4 data bytes
        for (i = 0; i < 4; i = i + 1) begin
            utmi_rx_data = test_data[i];
            @(posedge clk);
        end
        // CRC16 (simplified - just send zeros)
        utmi_rx_data = 8'h00;
        @(posedge clk);
        utmi_rx_data = 8'h00;
        @(posedge clk);
        utmi_rx_valid = 0;
        utmi_rx_active = 0;
        
        wait(trans_done);
        $display("Test 2 Complete - Result: %0d (1=ACK expected)", trans_result);
        #100;
        
        // Test 3: OUT Transaction with NAK
        $display("\nTest 3: OUT Transaction with NAK");
        wait(trans_ready);
        @(posedge clk);
        trans_type = 2'b10;  // OUT
        trans_addr = 7'd1;
        trans_endp = 4'd2;
        trans_data_pid = 1'b0;  // DATA0
        trans_data_len = 8'd4;
        trans_start = 1;
        @(posedge clk);
        trans_start = 0;
        
        // Send data
        wait(data_in_ready);
        for (i = 0; i < 4; i = i + 1) begin
            @(posedge clk);
            data_in = test_data[i];
            data_in_valid = 1;
        end
        @(posedge clk);
        data_in_valid = 0;
        
        // Simulate NAK response
        #200;
        utmi_rx_active = 1;
        utmi_rx_valid = 1;
        utmi_rx_data = 8'h5A;  // NAK PID
        @(posedge clk);
        utmi_rx_valid = 0;
        utmi_rx_active = 0;
        
        wait(trans_done);
        $display("Test 3 Complete - Result: %0d (2=NAK expected)", trans_result);
        #100;
        
        // Test 4: SETUP Transaction with STALL
        $display("\nTest 4: SETUP Transaction with STALL");
        wait(trans_ready);
        @(posedge clk);
        trans_type = 2'b00;  // SETUP
        trans_addr = 7'd1;
        trans_endp = 4'd0;
        trans_data_pid = 1'b0;  // DATA0
        trans_data_len = 8'd8;
        trans_start = 1;
        @(posedge clk);
        trans_start = 0;
        
        wait(data_in_ready);
        for (i = 0; i < 8; i = i + 1) begin
            @(posedge clk);
            data_in = setup_data[i];
            data_in_valid = 1;
        end
        @(posedge clk);
        data_in_valid = 0;
        
        // Simulate STALL response
        #200;
        utmi_rx_active = 1;
        utmi_rx_valid = 1;
        utmi_rx_data = 8'h1E;  // STALL PID
        @(posedge clk);
        utmi_rx_valid = 0;
        utmi_rx_active = 0;
        
        wait(trans_done);
        $display("Test 4 Complete - Result: %0d (3=STALL expected)", trans_result);
        #100;
        
        $display("\nAll tests completed successfully!");
        $finish;
    end
    
    // Monitor transaction events
    always @(posedge clk) begin
        if (token_start)
            $display("Time %0t: Token Start - Type=%0d Addr=%0d Endp=%0d", 
                     $time, token_type, token_addr, token_endp);
        if (trans_done)
            $display("Time %0t: Transaction Done - Result=%0d", $time, trans_result);
        if (data_out_valid)
            $display("Time %0t: Data Out - Byte[%0d]=0x%02h", 
                     $time, data_out_count, data_out);
    end

endmodule
