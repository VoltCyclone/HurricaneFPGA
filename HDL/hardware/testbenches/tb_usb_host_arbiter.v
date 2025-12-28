///////////////////////////////////////////////////////////////////////////////
// File: tb_usb_host_arbiter.v
// Description: Testbench for USB Host PHY Arbiter
//
// Tests priority-based arbitration between multiple USB host controllers.
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module tb_usb_host_arbiter;

    // Clock and Reset
    reg        clk;
    reg        rst_n;
    
    // Reset Controller Interface
    reg  [7:0] reset_tx_data;
    reg        reset_tx_valid;
    reg        reset_active;
    
    // Enumerator Interface
    reg  [7:0] enum_tx_data;
    reg        enum_tx_valid;
    reg        enum_active;
    
    // Transaction Engine Interface
    reg  [7:0] trans_tx_data;
    reg        trans_tx_valid;
    reg        trans_active;
    
    // Protocol Handler Interface
    reg  [7:0] protocol_tx_data;
    reg        protocol_tx_valid;
    reg        protocol_active;
    
    // Token Generator Interface
    reg  [7:0] token_tx_data;
    reg        token_tx_valid;
    reg        token_active;
    
    // SOF Generator Interface
    reg  [7:0] sof_tx_data;
    reg        sof_tx_valid;
    reg        sof_active;
    
    // Multiplexed PHY Output
    wire [7:0] phy_tx_data;
    wire       phy_tx_valid;
    
    // Test variables
    integer    test_num;
    integer    errors;
    
    // Instantiate DUT
    usb_host_arbiter dut (
        .clk(clk),
        .rst_n(rst_n),
        .reset_tx_data(reset_tx_data),
        .reset_tx_valid(reset_tx_valid),
        .reset_active(reset_active),
        .enum_tx_data(enum_tx_data),
        .enum_tx_valid(enum_tx_valid),
        .enum_active(enum_active),
        .trans_tx_data(trans_tx_data),
        .trans_tx_valid(trans_tx_valid),
        .trans_active(trans_active),
        .protocol_tx_data(protocol_tx_data),
        .protocol_tx_valid(protocol_tx_valid),
        .protocol_active(protocol_active),
        .token_tx_data(token_tx_data),
        .token_tx_valid(token_tx_valid),
        .token_active(token_active),
        .sof_tx_data(sof_tx_data),
        .sof_tx_valid(sof_tx_valid),
        .sof_active(sof_active),
        .phy_tx_data(phy_tx_data),
        .phy_tx_valid(phy_tx_valid)
    );
    
    // Clock generation (60MHz)
    initial begin
        clk = 0;
        forever #8.333 clk = ~clk;
    end
    
    // Task: Initialize all inputs
    task init_inputs;
        begin
            reset_tx_data = 8'h00;
            reset_tx_valid = 0;
            reset_active = 0;
            
            enum_tx_data = 8'h00;
            enum_tx_valid = 0;
            enum_active = 0;
            
            trans_tx_data = 8'h00;
            trans_tx_valid = 0;
            trans_active = 0;
            
            protocol_tx_data = 8'h00;
            protocol_tx_valid = 0;
            protocol_active = 0;
            
            token_tx_data = 8'h00;
            token_tx_valid = 0;
            token_active = 0;
            
            sof_tx_data = 8'h00;
            sof_tx_valid = 0;
            sof_active = 0;
        end
    endtask
    
    // Task: Check expected output
    task check_output(input [7:0] expected_data, input expected_valid, input [255:0] source_name);
        begin
            @(posedge clk);
            #1;  // Small delay for combinational logic
            if (phy_tx_data !== expected_data || phy_tx_valid !== expected_valid) begin
                $display("  ERROR: Expected %s: data=0x%02h valid=%b, Got: data=0x%02h valid=%b",
                         source_name, expected_data, expected_valid, phy_tx_data, phy_tx_valid);
                errors = errors + 1;
            end else begin
                $display("  PASS: %s selected correctly (data=0x%02h, valid=%b)",
                         source_name, expected_data, expected_valid);
            end
        end
    endtask
    
    // Test sequence
    initial begin
        // Initialize
        rst_n = 0;
        init_inputs();
        test_num = 0;
        errors = 0;
        
        // Dump waveforms
        $dumpfile("tb_usb_host_arbiter.vcd");
        $dumpvars(0, tb_usb_host_arbiter);
        
        // Reset
        #100;
        rst_n = 1;
        #100;
        
        //--------------------------------------------------------------------
        // Test 1: Default state (no active sources)
        //--------------------------------------------------------------------
        test_num = 1;
        $display("\n=== Test %0d: Default State (No Active Sources) ===", test_num);
        
        init_inputs();
        check_output(8'h00, 1'b0, "IDLE");
        
        //--------------------------------------------------------------------
        // Test 2: Protocol Handler only (lowest priority)
        //--------------------------------------------------------------------
        test_num = 2;
        $display("\n=== Test %0d: Protocol Handler Only ===", test_num);
        
        init_inputs();
        protocol_tx_data = 8'hAA;
        protocol_tx_valid = 1;
        protocol_active = 1;
        
        check_output(8'hAA, 1'b1, "Protocol Handler");
        
        //--------------------------------------------------------------------
        // Test 3: Token Generator priority
        //--------------------------------------------------------------------
        test_num = 3;
        $display("\n=== Test %0d: Token Generator Priority ===", test_num);
        
        init_inputs();
        protocol_tx_data = 8'hAA;
        protocol_tx_valid = 1;
        protocol_active = 1;
        
        token_tx_data = 8'hBB;
        token_tx_valid = 1;
        token_active = 1;
        
        check_output(8'hBB, 1'b1, "Token Generator (over Protocol)");
        
        //--------------------------------------------------------------------
        // Test 4: SOF Generator priority
        //--------------------------------------------------------------------
        test_num = 4;
        $display("\n=== Test %0d: SOF Generator Priority ===", test_num);
        
        init_inputs();
        protocol_tx_data = 8'hAA;
        protocol_tx_valid = 1;
        protocol_active = 1;
        
        token_tx_data = 8'hBB;
        token_tx_valid = 1;
        token_active = 1;
        
        sof_tx_data = 8'hCC;
        sof_tx_valid = 1;
        sof_active = 1;
        
        check_output(8'hCC, 1'b1, "SOF Generator (over Token)");
        
        //--------------------------------------------------------------------
        // Test 5: Transaction Engine priority
        //--------------------------------------------------------------------
        test_num = 5;
        $display("\n=== Test %0d: Transaction Engine Priority ===", test_num);
        
        init_inputs();
        protocol_tx_data = 8'hAA;
        protocol_tx_valid = 1;
        protocol_active = 1;
        
        sof_tx_data = 8'hCC;
        sof_tx_valid = 1;
        sof_active = 1;
        
        trans_tx_data = 8'hDD;
        trans_tx_valid = 1;
        trans_active = 1;
        
        check_output(8'hDD, 1'b1, "Transaction Engine (over SOF)");
        
        //--------------------------------------------------------------------
        // Test 6: Enumerator priority
        //--------------------------------------------------------------------
        test_num = 6;
        $display("\n=== Test %0d: Enumerator Priority ===", test_num);
        
        init_inputs();
        trans_tx_data = 8'hDD;
        trans_tx_valid = 1;
        trans_active = 1;
        
        enum_tx_data = 8'hEE;
        enum_tx_valid = 1;
        enum_active = 1;
        
        check_output(8'hEE, 1'b1, "Enumerator (over Transaction)");
        
        //--------------------------------------------------------------------
        // Test 7: Reset Controller priority (highest)
        //--------------------------------------------------------------------
        test_num = 7;
        $display("\n=== Test %0d: Reset Controller Priority (Highest) ===", test_num);
        
        init_inputs();
        enum_tx_data = 8'hEE;
        enum_tx_valid = 1;
        enum_active = 1;
        
        reset_tx_data = 8'hFF;
        reset_tx_valid = 1;
        reset_active = 1;
        
        check_output(8'hFF, 1'b1, "Reset Controller (over Enumerator)");
        
        //--------------------------------------------------------------------
        // Test 8: All sources active (verify priority)
        //--------------------------------------------------------------------
        test_num = 8;
        $display("\n=== Test %0d: All Sources Active (Priority Test) ===", test_num);
        
        protocol_tx_data = 8'hAA;
        protocol_tx_valid = 1;
        protocol_active = 1;
        
        token_tx_data = 8'hBB;
        token_tx_valid = 1;
        token_active = 1;
        
        sof_tx_data = 8'hCC;
        sof_tx_valid = 1;
        sof_active = 1;
        
        trans_tx_data = 8'hDD;
        trans_tx_valid = 1;
        trans_active = 1;
        
        enum_tx_data = 8'hEE;
        enum_tx_valid = 1;
        enum_active = 1;
        
        reset_tx_data = 8'hFF;
        reset_tx_valid = 1;
        reset_active = 1;
        
        check_output(8'hFF, 1'b1, "Reset Controller (highest priority)");
        
        //--------------------------------------------------------------------
        // Test 9: Active but not valid (should not output)
        //--------------------------------------------------------------------
        test_num = 9;
        $display("\n=== Test %0d: Active but Not Valid ===", test_num);
        
        init_inputs();
        protocol_tx_data = 8'hAA;
        protocol_tx_valid = 0;  // Valid is low
        protocol_active = 1;
        
        check_output(8'hAA, 1'b0, "Protocol (inactive output)");
        
        //--------------------------------------------------------------------
        // Test 10: Dynamic priority switching
        //--------------------------------------------------------------------
        test_num = 10;
        $display("\n=== Test %0d: Dynamic Priority Switching ===", test_num);
        
        // Start with protocol handler
        init_inputs();
        protocol_tx_data = 8'hAA;
        protocol_tx_valid = 1;
        protocol_active = 1;
        check_output(8'hAA, 1'b1, "Protocol Handler");
        
        // Add transaction engine (higher priority)
        trans_tx_data = 8'hDD;
        trans_tx_valid = 1;
        trans_active = 1;
        check_output(8'hDD, 1'b1, "Transaction Engine");
        
        // Add reset controller (highest priority)
        reset_tx_data = 8'hFF;
        reset_tx_valid = 1;
        reset_active = 1;
        check_output(8'hFF, 1'b1, "Reset Controller");
        
        // Remove reset controller
        reset_tx_valid = 0;
        reset_active = 0;
        check_output(8'hDD, 1'b1, "Transaction Engine (after reset done)");
        
        // Remove transaction engine
        trans_tx_valid = 0;
        trans_active = 0;
        check_output(8'hAA, 1'b1, "Protocol Handler (after trans done)");
        
        //--------------------------------------------------------------------
        // Test 11: Verify each source can transmit when alone
        //--------------------------------------------------------------------
        test_num = 11;
        $display("\n=== Test %0d: Each Source Individual Test ===", test_num);
        
        // Reset Controller
        init_inputs();
        reset_tx_data = 8'h01;
        reset_tx_valid = 1;
        reset_active = 1;
        check_output(8'h01, 1'b1, "Reset Controller alone");
        
        // Enumerator
        init_inputs();
        enum_tx_data = 8'h02;
        enum_tx_valid = 1;
        enum_active = 1;
        check_output(8'h02, 1'b1, "Enumerator alone");
        
        // Transaction Engine
        init_inputs();
        trans_tx_data = 8'h03;
        trans_tx_valid = 1;
        trans_active = 1;
        check_output(8'h03, 1'b1, "Transaction Engine alone");
        
        // SOF Generator
        init_inputs();
        sof_tx_data = 8'h04;
        sof_tx_valid = 1;
        sof_active = 1;
        check_output(8'h04, 1'b1, "SOF Generator alone");
        
        // Token Generator
        init_inputs();
        token_tx_data = 8'h05;
        token_tx_valid = 1;
        token_active = 1;
        check_output(8'h05, 1'b1, "Token Generator alone");
        
        // Protocol Handler
        init_inputs();
        protocol_tx_data = 8'h06;
        protocol_tx_valid = 1;
        protocol_active = 1;
        check_output(8'h06, 1'b1, "Protocol Handler alone");
        
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
        #10000000;  // 10ms timeout
        $display("\nERROR: Testbench timeout!");
        $finish;
    end

endmodule
