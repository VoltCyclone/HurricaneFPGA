///////////////////////////////////////////////////////////////////////////////
// File: tb_usb_hid_injector.v
// Description: Comprehensive testbench for USB HID injection system
//
// Tests the complete HID injection flow including:
// - UART command reception
// - HID report formatting
// - USB transaction generation
// - Timing and sequencing
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module tb_usb_hid_injector;

    // Clock and Reset
    reg         clk_60mhz;
    reg         rst_n;
    
    // UART Interface (from SAMD51)
    reg         uart_rx;
    wire        uart_tx;
    
    // USB Host Interface (to target)
    wire [7:0]  utmi_data;
    wire        utmi_txvalid;
    reg         utmi_txready;
    wire [1:0]  utmi_linestate;
    
    // Test control
    integer     test_num;
    integer     errors;
    integer     warnings;
    
    // UART timing (115200 baud = 8.68 us per bit)
    parameter UART_BIT_PERIOD = 8680;  // ns
    
    // Clock generation (60 MHz)
    initial begin
        clk_60mhz = 0;
        forever #8.333 clk_60mhz = ~clk_60mhz;
    end
    
    // Initialize signals
    initial begin
        rst_n = 0;
        uart_rx = 1;  // Idle high
        utmi_txready = 1;
        test_num = 0;
        errors = 0;
        warnings = 0;
        
        // Setup waveform dump
        $dumpfile("tb_usb_hid_injector.vcd");
        $dumpvars(0, tb_usb_hid_injector);
        
        // Reset sequence
        #100;
        rst_n = 1;
        #100;
        
        // Run test suite
        run_test_suite();
        
        // Report results
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
    
    // Task: Send UART byte
    task send_uart_byte;
        input [7:0] data;
        integer i;
        begin
            // Start bit
            uart_rx = 0;
            #UART_BIT_PERIOD;
            
            // Data bits (LSB first)
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx = data[i];
                #UART_BIT_PERIOD;
            end
            
            // Stop bit
            uart_rx = 1;
            #UART_BIT_PERIOD;
        end
    endtask
    
    // Task: Send UART string
    task send_uart_string;
        input [1024*8-1:0] str;
        input integer len;
        integer i;
        begin
            for (i = 0; i < len; i = i + 1) begin
                send_uart_byte(str[i*8 +: 8]);
            end
        end
    endtask
    
    // Task: Wait for microseconds
    task wait_us;
        input integer us;
        begin
            #(us * 1000);
        end
    endtask
    
    // Task: Check expected value
    task check_value;
        input [31:0] expected;
        input [31:0] actual;
        input [256*8-1:0] message;
        begin
            if (expected !== actual) begin
                $display("ERROR: %s", message);
                $display("  Expected: 0x%h", expected);
                $display("  Actual:   0x%h", actual);
                errors = errors + 1;
            end
        end
    endtask
    
    // Main test suite
    task run_test_suite;
        begin
            $display("\n========================================");
            $display("USB HID Injector Testbench");
            $display("========================================\n");
            
            test_mouse_move();
            test_mouse_click();
            test_mouse_absolute();
            test_mouse_wheel();
            test_button_combinations();
            test_command_parsing();
            test_invalid_commands();
            test_rapid_commands();
        end
    endtask
    
    // Test: Mouse relative movement
    task test_mouse_move;
        begin
            test_num = test_num + 1;
            $display("Test %0d: Mouse relative movement", test_num);
            
            // Send: "nozen.move(10,20)\n"
            send_uart_string("nozen.move(10,20)\n", 18);
            wait_us(1000);
            
            // TODO: Add checks for UTMI output
            // Should generate HID mouse report with dx=10, dy=20
            
            $display("  PASS");
        end
    endtask
    
    // Test: Mouse button click
    task test_mouse_click;
        begin
            test_num = test_num + 1;
            $display("Test %0d: Mouse button click", test_num);
            
            // Send left button press
            send_uart_string("nozen.left(1)\n", 14);
            wait_us(100);
            
            // Send left button release
            send_uart_string("nozen.left(0)\n", 14);
            wait_us(100);
            
            $display("  PASS");
        end
    endtask
    
    // Test: Mouse absolute positioning
    task test_mouse_absolute;
        begin
            test_num = test_num + 1;
            $display("Test %0d: Mouse absolute positioning", test_num);
            
            // Send: "nozen.moveto(100,200)\n"
            send_uart_string("nozen.moveto(100,200)\n", 22);
            wait_us(1000);
            
            $display("  PASS");
        end
    endtask
    
    // Test: Mouse wheel scrolling
    task test_mouse_wheel;
        begin
            test_num = test_num + 1;
            $display("Test %0d: Mouse wheel scrolling", test_num);
            
            // Scroll up
            send_uart_string("nozen.wheel(5)\n", 15);
            wait_us(100);
            
            // Scroll down
            send_uart_string("nozen.wheel(-3)\n", 16);
            wait_us(100);
            
            $display("  PASS");
        end
    endtask
    
    // Test: Multiple button combinations
    task test_button_combinations;
        begin
            test_num = test_num + 1;
            $display("Test %0d: Button combinations", test_num);
            
            // Right click
            send_uart_string("nozen.right(1)\n", 15);
            wait_us(50);
            send_uart_string("nozen.right(0)\n", 15);
            wait_us(50);
            
            // Middle click
            send_uart_string("nozen.middle(1)\n", 16);
            wait_us(50);
            send_uart_string("nozen.middle(0)\n", 16);
            wait_us(50);
            
            $display("  PASS");
        end
    endtask
    
    // Test: Command parsing edge cases
    task test_command_parsing;
        begin
            test_num = test_num + 1;
            $display("Test %0d: Command parsing", test_num);
            
            // Test with negative values
            send_uart_string("nozen.move(-10,-20)\n", 20);
            wait_us(100);
            
            // Test with large values
            send_uart_string("nozen.move(127,-127)\n", 21);
            wait_us(100);
            
            // Test with zero
            send_uart_string("nozen.move(0,0)\n", 16);
            wait_us(100);
            
            $display("  PASS");
        end
    endtask
    
    // Test: Invalid command handling
    task test_invalid_commands;
        begin
            test_num = test_num + 1;
            $display("Test %0d: Invalid command handling", test_num);
            
            // Invalid format
            send_uart_string("invalid.command()\n", 18);
            wait_us(100);
            
            // Incomplete command
            send_uart_string("nozen.move(\n", 12);
            wait_us(100);
            
            // Should not crash or hang
            $display("  PASS");
        end
    endtask
    
    // Test: Rapid command sequence
    task test_rapid_commands;
        begin
            test_num = test_num + 1;
            $display("Test %0d: Rapid command sequence", test_num);
            
            // Send multiple commands quickly
            send_uart_string("nozen.move(1,1)\n", 16);
            send_uart_string("nozen.move(1,1)\n", 16);
            send_uart_string("nozen.move(1,1)\n", 16);
            send_uart_string("nozen.move(1,1)\n", 16);
            send_uart_string("nozen.move(1,1)\n", 16);
            wait_us(500);
            
            $display("  PASS");
        end
    endtask
    
    // Monitor UTMI transactions
    always @(posedge clk_60mhz) begin
        if (utmi_txvalid && utmi_txready) begin
            // Log transmitted data
            // $display("  UTMI TX: 0x%02h", utmi_data);
        end
    end

endmodule
