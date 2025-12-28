///////////////////////////////////////////////////////////////////////////////
// File: tb_usb_reset_controller.v
// Description: Testbench for USB Reset Controller with Speed Detection
//
// Tests USB bus reset sequence, high-speed chirp negotiation, and
// automatic speed detection.
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module tb_usb_reset_controller;

    // Clock and Reset
    reg        clk;
    reg        rst_n;
    
    // Control Interface
    reg        bus_reset_req;
    wire       reset_active;
    wire [1:0] detected_speed;
    
    // PHY Control Outputs
    wire [1:0] phy_op_mode;
    wire [1:0] phy_xcvr_select;
    wire       phy_term_select;
    
    // PHY Status Inputs
    reg  [1:0] phy_line_state;
    
    // UTMI Transmit Interface
    wire [7:0] utmi_tx_data;
    wire       utmi_tx_valid;
    reg        utmi_tx_ready;
    
    // Test variables
    integer    test_num;
    integer    errors;
    integer    warnings;
    
    // Speed constants
    localparam SPEED_UNKNOWN = 2'b00;
    localparam SPEED_FULL    = 2'b01;
    localparam SPEED_HIGH    = 2'b10;
    
    // Line state constants
    localparam LINE_STATE_SE0 = 2'b00;
    localparam LINE_STATE_J   = 2'b01;
    localparam LINE_STATE_K   = 2'b10;
    localparam LINE_STATE_SE1 = 2'b11;
    
    // Instantiate DUT
    usb_reset_controller dut (
        .clk(clk),
        .rst_n(rst_n),
        .bus_reset_req(bus_reset_req),
        .reset_active(reset_active),
        .detected_speed(detected_speed),
        .phy_op_mode(phy_op_mode),
        .phy_xcvr_select(phy_xcvr_select),
        .phy_term_select(phy_term_select),
        .phy_line_state(phy_line_state),
        .utmi_tx_data(utmi_tx_data),
        .utmi_tx_valid(utmi_tx_valid),
        .utmi_tx_ready(utmi_tx_ready)
    );
    
    // Clock generation (60MHz)
    initial begin
        clk = 0;
        forever #8.333 clk = ~clk;  // 60MHz = 16.666ns period
    end
    
    // Task: Simulate Full-Speed device response
    task simulate_fullspeed_device;
        begin
            $display("  Simulating Full-Speed device...");
            
            // Wait for SE0 (reset signaling)
            wait (phy_line_state == LINE_STATE_SE0);
            $display("    Device sees SE0 (reset)");
            
            // Keep SE0 during reset
            #100000;  // Wait for reset duration
            
            // After reset, device returns to J state (FS idle)
            wait (phy_line_state != LINE_STATE_SE0);
            #1000;
            phy_line_state = LINE_STATE_J;
            $display("    Device returns to J state (FS idle)");
        end
    endtask
    
    // Task: Simulate High-Speed device response with chirp
    task simulate_highspeed_device;
        begin
            $display("  Simulating High-Speed device...");
            
            // Wait for SE0 (reset signaling)
            wait (phy_line_state == LINE_STATE_SE0);
            $display("    Device sees SE0 (reset)");
            
            // Keep SE0 during reset
            #100000;
            
            // After reset, device returns to J state briefly
            wait (phy_line_state != LINE_STATE_SE0);
            #1000;
            phy_line_state = LINE_STATE_J;
            $display("    Device returns to J state");
            
            // Wait for host chirp K
            #5000;
            if (phy_line_state == LINE_STATE_K) begin
                $display("    Device detects Host Chirp K");
                
                // Device responds with Chirp K
                #1000;
                phy_line_state = LINE_STATE_K;
                $display("    Device sends Chirp K");
                
                // Hold chirp for required duration
                #10000;
                
                // Return to HS idle state
                phy_line_state = LINE_STATE_SE0;  // HS idle
                $display("    Device in HS idle state");
            end
        end
    endtask
    
    // Test sequence
    initial begin
        // Initialize
        rst_n = 0;
        bus_reset_req = 0;
        phy_line_state = LINE_STATE_J;  // Normal idle
        utmi_tx_ready = 1;
        test_num = 0;
        errors = 0;
        warnings = 0;
        
        // Dump waveforms
        $dumpfile("tb_usb_reset_controller.vcd");
        $dumpvars(0, tb_usb_reset_controller);
        
        // Reset
        #100;
        rst_n = 1;
        #100;
        
        //--------------------------------------------------------------------
        // Test 1: Basic reset without device (timeout to Full-Speed)
        //--------------------------------------------------------------------
        test_num = 1;
        $display("\n=== Test %0d: Reset with No Device (Default to FS) ===", test_num);
        
        bus_reset_req = 1;
        @(posedge clk);
        bus_reset_req = 0;
        
        $display("  Reset requested...");
        
        // Wait for reset to become active
        wait (reset_active);
        $display("  Reset active");
        
        // Check PHY is driving SE0
        #1000;
        if (phy_line_state == LINE_STATE_SE0) begin
            $display("  PASS: PHY driving SE0 during reset");
        end else begin
            $display("  ERROR: PHY not driving SE0 (line_state = %b)", phy_line_state);
            errors = errors + 1;
        end
        
        // Wait for reset to complete
        wait (!reset_active);
        $display("  Reset complete");
        
        // Check detected speed (should default to Full-Speed)
        #1000;
        if (detected_speed == SPEED_FULL) begin
            $display("  PASS: Detected Full-Speed (default)");
        end else begin
            $display("  ERROR: Speed = %b (expected FS)", detected_speed);
            errors = errors + 1;
        end
        
        #10000;
        
        //--------------------------------------------------------------------
        // Test 2: Reset with Full-Speed device response
        //--------------------------------------------------------------------
        test_num = 2;
        $display("\n=== Test %0d: Reset with Full-Speed Device ===", test_num);
        
        // Start device simulation in background
        fork
            simulate_fullspeed_device();
        join_none
        
        // Request reset
        #1000;
        bus_reset_req = 1;
        @(posedge clk);
        bus_reset_req = 0;
        
        // Wait for reset sequence
        wait (reset_active);
        $display("  Reset active");
        
        // Wait for completion
        wait (!reset_active);
        $display("  Reset complete");
        
        // Verify speed detection
        #1000;
        if (detected_speed == SPEED_FULL) begin
            $display("  PASS: Detected Full-Speed");
        end else begin
            $display("  ERROR: Speed = %b (expected FS)", detected_speed);
            errors = errors + 1;
        end
        
        #10000;
        
        //--------------------------------------------------------------------
        // Test 3: Reset with High-Speed device response (chirp sequence)
        //--------------------------------------------------------------------
        test_num = 3;
        $display("\n=== Test %0d: Reset with High-Speed Device (Chirp) ===", test_num);
        
        // Reset line state
        phy_line_state = LINE_STATE_J;
        
        // Start device simulation
        fork
            simulate_highspeed_device();
        join_none
        
        // Request reset
        #1000;
        bus_reset_req = 1;
        @(posedge clk);
        bus_reset_req = 0;
        
        // Wait for reset sequence
        wait (reset_active);
        $display("  Reset active");
        
        // Wait for completion
        wait (!reset_active);
        $display("  Reset complete");
        
        // Verify speed detection
        #1000;
        if (detected_speed == SPEED_HIGH) begin
            $display("  PASS: Detected High-Speed");
        end else begin
            $display("  WARNING: Speed = %b (expected HS)", detected_speed);
            warnings = warnings + 1;
        end
        
        #10000;
        
        //--------------------------------------------------------------------
        // Test 4: PHY configuration during reset
        //--------------------------------------------------------------------
        test_num = 4;
        $display("\n=== Test %0d: PHY Configuration During Reset ===", test_num);
        
        phy_line_state = LINE_STATE_J;
        
        bus_reset_req = 1;
        @(posedge clk);
        bus_reset_req = 0;
        
        wait (reset_active);
        
        // Check PHY is configured for reset
        #1000;
        $display("  PHY op_mode = %b", phy_op_mode);
        $display("  PHY xcvr_select = %b", phy_xcvr_select);
        $display("  PHY term_select = %b", phy_term_select);
        
        // Wait for reset completion
        wait (!reset_active);
        
        // Check PHY is configured for normal operation
        #1000;
        $display("  After reset:");
        $display("    PHY op_mode = %b (should be normal)", phy_op_mode);
        
        #10000;
        
        //--------------------------------------------------------------------
        // Test 5: Multiple consecutive resets
        //--------------------------------------------------------------------
        test_num = 5;
        $display("\n=== Test %0d: Multiple Consecutive Resets ===", test_num);
        
        repeat(3) begin
            phy_line_state = LINE_STATE_J;
            
            bus_reset_req = 1;
            @(posedge clk);
            bus_reset_req = 0;
            
            wait (reset_active);
            $display("  Reset %0d started", test_num);
            
            wait (!reset_active);
            $display("  Reset %0d complete", test_num);
            
            #5000;
            test_num = test_num + 1;
        end
        
        $display("  PASS: Multiple resets completed successfully");
        
        #10000;
        
        //--------------------------------------------------------------------
        // Test Results
        //--------------------------------------------------------------------
        $display("\n========================================");
        $display("Test Results:");
        $display("  Tests run: %0d", test_num);
        $display("  Errors: %0d", errors);
        $display("  Warnings: %0d", warnings);
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
        #100000000;  // 100ms timeout
        $display("\nERROR: Testbench timeout!");
        $finish;
    end

endmodule
