///////////////////////////////////////////////////////////////////////////////
// File: tb_usb_sof_generator.v
// Description: Testbench for USB SOF (Start-of-Frame) Generator
//
// Tests SOF packet generation timing and frame number counter.
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module tb_usb_sof_generator;

    // Clock and Reset
    reg        clk;
    reg        rst_n;
    
    // Control
    reg        enable;
    reg  [1:0] speed;
    
    // SOF Output
    wire       sof_trigger;
    wire [10:0] frame_number;
    
    // Token Generator Interface
    wire       token_start;
    wire [1:0] token_type;
    wire [10:0] token_frame;
    reg        token_ready;
    reg        token_done;
    
    // Test variables
    integer    sof_count;
    integer    test_num;
    integer    errors;
    real       last_sof_time;
    real       current_time;
    real       sof_interval;
    
    // Instantiate DUT
    usb_sof_generator dut (
        .clk(clk),
        .rst_n(rst_n),
        .enable(enable),
        .speed(speed),
        .sof_trigger(sof_trigger),
        .frame_number(frame_number),
        .token_start(token_start),
        .token_type(token_type),
        .token_frame(token_frame),
        .token_ready(token_ready),
        .token_done(token_done)
    );
    
    // Clock generation (60MHz)
    initial begin
        clk = 0;
        forever #8.333 clk = ~clk;  // 60MHz = 16.666ns period
    end
    
    // Monitor SOF triggers
    always @(posedge clk) begin
        if (sof_trigger) begin
            current_time = $realtime;
            if (sof_count > 0) begin
                sof_interval = (current_time - last_sof_time) / 1000.0;  // Convert to us
                if (speed == 2'b01) begin  // Full-Speed: 1ms = 1000us
                    if (sof_interval < 995.0 || sof_interval > 1005.0) begin
                        $display("ERROR: FS SOF interval %.2f us (expected ~1000us)", sof_interval);
                        errors = errors + 1;
                    end
                end else if (speed == 2'b10) begin  // High-Speed: 125us
                    if (sof_interval < 122.0 || sof_interval > 128.0) begin
                        $display("ERROR: HS SOF interval %.2f us (expected ~125us)", sof_interval);
                        errors = errors + 1;
                    end
                end
            end
            last_sof_time = current_time;
            sof_count = sof_count + 1;
        end
    end
    
    // Simulate token generator completion
    always @(posedge clk) begin
        if (token_start) begin
            token_ready = 0;
            #200;  // Simulate token transmission time
            @(posedge clk);
            token_done = 1;
            @(posedge clk);
            token_done = 0;
            token_ready = 1;
        end
    end
    
    // Test sequence
    initial begin
        // Initialize
        rst_n = 0;
        enable = 0;
        speed = 2'b01;  // Full-Speed
        token_ready = 1;
        token_done = 0;
        sof_count = 0;
        test_num = 0;
        errors = 0;
        last_sof_time = 0;
        
        // Dump waveforms
        $dumpfile("tb_usb_sof_generator.vcd");
        $dumpvars(0, tb_usb_sof_generator);
        
        // Reset
        #100;
        rst_n = 1;
        #100;
        
        //--------------------------------------------------------------------
        // Test 1: Full-Speed SOF generation (1ms interval)
        //--------------------------------------------------------------------
        test_num = 1;
        $display("\n=== Test %0d: Full-Speed SOF Generation ===", test_num);
        speed = 2'b01;  // Full-Speed
        enable = 1;
        
        // Wait for several SOF packets
        repeat(5) begin
            @(posedge sof_trigger);
            $display("  SOF %0d: Frame Number = %0d", sof_count, frame_number);
        end
        
        enable = 0;
        #1000;
        
        //--------------------------------------------------------------------
        // Test 2: High-Speed SOF generation (125us interval)
        //--------------------------------------------------------------------
        test_num = 2;
        $display("\n=== Test %0d: High-Speed SOF Generation ===", test_num);
        speed = 2'b10;  // High-Speed
        sof_count = 0;
        last_sof_time = 0;
        enable = 1;
        
        // Wait for several SOF packets
        repeat(10) begin
            @(posedge sof_trigger);
            $display("  SOF %0d: Frame Number = %0d", sof_count, frame_number);
        end
        
        enable = 0;
        #1000;
        
        //--------------------------------------------------------------------
        // Test 3: Frame number rollover (11-bit counter: 0-2047)
        //--------------------------------------------------------------------
        test_num = 3;
        $display("\n=== Test %0d: Frame Number Rollover ===", test_num);
        
        // Force frame number near rollover point
        force dut.frame_number = 11'd2045;
        #100;
        release dut.frame_number;
        
        speed = 2'b01;  // Full-Speed
        enable = 1;
        
        // Monitor rollover
        repeat(5) begin
            @(posedge sof_trigger);
            $display("  Frame Number = %0d", frame_number);
        end
        
        // Check rollover occurred
        if (frame_number < 11'd10) begin
            $display("  PASS: Frame number rolled over correctly");
        end else begin
            $display("  ERROR: Frame number did not rollover");
            errors = errors + 1;
        end
        
        enable = 0;
        #1000;
        
        //--------------------------------------------------------------------
        // Test 4: Enable/Disable behavior
        //--------------------------------------------------------------------
        test_num = 4;
        $display("\n=== Test %0d: Enable/Disable Behavior ===", test_num);
        
        sof_count = 0;
        enable = 1;
        speed = 2'b01;
        
        // Wait for first SOF
        @(posedge sof_trigger);
        $display("  SOF triggered, disabling...");
        
        enable = 0;
        #2000000;  // Wait 2ms (longer than FS interval)
        
        if (sof_count == 1) begin
            $display("  PASS: No SOF when disabled");
        end else begin
            $display("  ERROR: SOF still triggering when disabled");
            errors = errors + 1;
        end
        
        #1000;
        
        //--------------------------------------------------------------------
        // Test 5: Token type verification
        //--------------------------------------------------------------------
        test_num = 5;
        $display("\n=== Test %0d: Token Type Verification ===", test_num);
        
        enable = 1;
        speed = 2'b01;
        
        @(posedge token_start);
        if (token_type == 2'b10) begin  // SOF token type
            $display("  PASS: Token type is SOF (2'b10)");
        end else begin
            $display("  ERROR: Token type = %b (expected 2'b10)", token_type);
            errors = errors + 1;
        end
        
        if (token_frame == frame_number) begin
            $display("  PASS: Token frame matches frame_number");
        end else begin
            $display("  ERROR: Token frame = %0d, frame_number = %0d", 
                     token_frame, frame_number);
            errors = errors + 1;
        end
        
        enable = 0;
        #1000;
        
        //--------------------------------------------------------------------
        // Test Results
        //--------------------------------------------------------------------
        $display("\n========================================");
        $display("Test Results:");
        $display("  Tests run: %0d", test_num);
        $display("  Errors: %0d", errors);
        $display("========================================");
        
        if (errors == 0) begin
            $display("ALL TESTS PASSED!");
        end else begin
            $display("TESTS FAILED!");
        end
        
        #1000;
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #50000000;  // 50ms timeout
        $display("\nERROR: Testbench timeout!");
        $finish;
    end

endmodule
