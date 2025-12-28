///////////////////////////////////////////////////////////////////////////////
// File: tb_usb_descriptor_parser.v
// Description: Testbench for USB Descriptor Parser
//
// Tests parsing of USB descriptors and endpoint extraction with filtering.
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module tb_usb_descriptor_parser;

    // Clock and Reset
    reg        clk;
    reg        rst_n;
    
    // Control Interface
    reg        enable;
    wire       done;
    wire       valid;
    
    // Descriptor Stream Input
    reg  [7:0] desc_data;
    reg        desc_valid;
    wire       desc_ready;
    
    // Filter Configuration
    reg  [7:0] filter_class;
    reg  [7:0] filter_subclass;
    reg  [7:0] filter_protocol;
    reg  [1:0] filter_transfer_type;
    reg        filter_direction;
    
    // Extracted Endpoint Information
    wire [3:0] endp_number;
    wire       endp_direction;
    wire [1:0] endp_type;
    wire [10:0] endp_max_packet;
    wire [7:0] endp_interval;
    wire [7:0] iface_protocol_out;
    wire [7:0] iface_number_out;
    
    // Test variables
    integer    test_num;
    integer    errors;
    integer    warnings;
    integer    endpoints_found;
    
    // Descriptor type constants
    localparam DESC_DEVICE        = 8'h01;
    localparam DESC_CONFIGURATION = 8'h02;
    localparam DESC_INTERFACE     = 8'h04;
    localparam DESC_ENDPOINT      = 8'h05;
    
    // Endpoint types
    localparam EP_CONTROL     = 2'b00;
    localparam EP_ISOCHRONOUS = 2'b01;
    localparam EP_BULK        = 2'b10;
    localparam EP_INTERRUPT   = 2'b11;
    
    // Instantiate DUT
    usb_descriptor_parser dut (
        .clk(clk),
        .rst_n(rst_n),
        .enable(enable),
        .done(done),
        .valid(valid),
        .desc_data(desc_data),
        .desc_valid(desc_valid),
        .desc_ready(desc_ready),
        .filter_class(filter_class),
        .filter_subclass(filter_subclass),
        .filter_protocol(filter_protocol),
        .filter_transfer_type(filter_transfer_type),
        .filter_direction(filter_direction),
        .endp_number(endp_number),
        .endp_direction(endp_direction),
        .endp_type(endp_type),
        .endp_max_packet(endp_max_packet),
        .endp_interval(endp_interval),
        .iface_protocol_out(iface_protocol_out),
        .iface_number_out(iface_number_out)
    );
    
    // Clock generation (60MHz)
    initial begin
        clk = 0;
        forever #8.333 clk = ~clk;
    end
    
    // Task: Send descriptor byte
    task send_desc_byte(input [7:0] data);
        begin
            @(posedge clk);
            desc_data = data;
            desc_valid = 1;
            @(posedge clk);
            while (!desc_ready) @(posedge clk);
            desc_valid = 0;
        end
    endtask
    
    // Task: Send device descriptor
    task send_device_descriptor;
        begin
            $display("  Sending Device Descriptor...");
            send_desc_byte(8'd18);           // bLength
            send_desc_byte(DESC_DEVICE);     // bDescriptorType
            send_desc_byte(8'h00);           // bcdUSB (low)
            send_desc_byte(8'h02);           // bcdUSB (high) - USB 2.0
            send_desc_byte(8'h00);           // bDeviceClass
            send_desc_byte(8'h00);           // bDeviceSubClass
            send_desc_byte(8'h00);           // bDeviceProtocol
            send_desc_byte(8'd64);           // bMaxPacketSize0
            send_desc_byte(8'h34);           // idVendor (low)
            send_desc_byte(8'h12);           // idVendor (high)
            send_desc_byte(8'h78);           // idProduct (low)
            send_desc_byte(8'h56);           // idProduct (high)
            send_desc_byte(8'h00);           // bcdDevice (low)
            send_desc_byte(8'h01);           // bcdDevice (high)
            send_desc_byte(8'd1);            // iManufacturer
            send_desc_byte(8'd2);            // iProduct
            send_desc_byte(8'd3);            // iSerialNumber
            send_desc_byte(8'd1);            // bNumConfigurations
        end
    endtask
    
    // Task: Send configuration descriptor
    task send_config_descriptor;
        begin
            $display("  Sending Configuration Descriptor...");
            send_desc_byte(8'd9);            // bLength
            send_desc_byte(DESC_CONFIGURATION); // bDescriptorType
            send_desc_byte(8'd34);           // wTotalLength (low)
            send_desc_byte(8'd0);            // wTotalLength (high)
            send_desc_byte(8'd1);            // bNumInterfaces
            send_desc_byte(8'd1);            // bConfigurationValue
            send_desc_byte(8'd0);            // iConfiguration
            send_desc_byte(8'b10000000);     // bmAttributes
            send_desc_byte(8'd50);           // bMaxPower (100mA)
        end
    endtask
    
    // Task: Send interface descriptor (HID Keyboard)
    task send_interface_descriptor(input [7:0] iface_num, iface_class, iface_subclass, iface_protocol);
        begin
            $display("  Sending Interface Descriptor (Class=%02h, Protocol=%02h)...", 
                     iface_class, iface_protocol);
            send_desc_byte(8'd9);            // bLength
            send_desc_byte(DESC_INTERFACE);  // bDescriptorType
            send_desc_byte(iface_num);       // bInterfaceNumber
            send_desc_byte(8'd0);            // bAlternateSetting
            send_desc_byte(8'd1);            // bNumEndpoints
            send_desc_byte(iface_class);     // bInterfaceClass
            send_desc_byte(iface_subclass);  // bInterfaceSubClass
            send_desc_byte(iface_protocol);  // bInterfaceProtocol
            send_desc_byte(8'd0);            // iInterface
        end
    endtask
    
    // Task: Send endpoint descriptor
    task send_endpoint_descriptor(
        input [3:0] ep_num,
        input       ep_dir,      // 0=OUT, 1=IN
        input [1:0] ep_type,
        input [10:0] ep_max_pkt,
        input [7:0] ep_interval
    );
        begin
            $display("  Sending Endpoint Descriptor (EP%0d %s, Type=%0d)...",
                     ep_num, ep_dir ? "IN" : "OUT", ep_type);
            send_desc_byte(8'd7);            // bLength
            send_desc_byte(DESC_ENDPOINT);   // bDescriptorType
            send_desc_byte({ep_dir, 3'd0, ep_num}); // bEndpointAddress
            send_desc_byte({6'd0, ep_type}); // bmAttributes
            send_desc_byte(ep_max_pkt[7:0]); // wMaxPacketSize (low)
            send_desc_byte({5'd0, ep_max_pkt[10:8]}); // wMaxPacketSize (high)
            send_desc_byte(ep_interval);     // bInterval
        end
    endtask
    
    // Monitor endpoint detection
    always @(posedge clk) begin
        if (valid) begin
            $display("    *** ENDPOINT FOUND ***");
            $display("      Number: %0d", endp_number);
            $display("      Direction: %s", endp_direction ? "IN" : "OUT");
            $display("      Type: %0d", endp_type);
            $display("      Max Packet: %0d", endp_max_packet);
            $display("      Interval: %0d", endp_interval);
            $display("      Interface Protocol: 0x%02h", iface_protocol_out);
            endpoints_found = endpoints_found + 1;
        end
    end
    
    // Test sequence
    initial begin
        // Initialize
        rst_n = 0;
        enable = 0;
        desc_data = 0;
        desc_valid = 0;
        filter_class = 8'h00;
        filter_subclass = 8'h00;
        filter_protocol = 8'h00;
        filter_transfer_type = 2'b00;
        filter_direction = 0;
        test_num = 0;
        errors = 0;
        warnings = 0;
        endpoints_found = 0;
        
        // Dump waveforms
        $dumpfile("tb_usb_descriptor_parser.vcd");
        $dumpvars(0, tb_usb_descriptor_parser);
        
        // Reset
        #100;
        rst_n = 1;
        #100;
        
        //--------------------------------------------------------------------
        // Test 1: Parse HID Keyboard descriptors
        //--------------------------------------------------------------------
        test_num = 1;
        $display("\n=== Test %0d: Parse HID Keyboard Descriptors ===", test_num);
        
        // Configure filter for HID Keyboard (Class=03, Protocol=01)
        filter_class = 8'h03;        // HID
        filter_subclass = 8'h01;     // Boot Interface
        filter_protocol = 8'h01;     // Keyboard
        filter_transfer_type = EP_INTERRUPT;
        filter_direction = 1;        // IN
        
        enable = 1;
        endpoints_found = 0;
        
        // Send descriptors
        send_device_descriptor();
        send_config_descriptor();
        send_interface_descriptor(8'd0, 8'h03, 8'h01, 8'h01); // HID Keyboard
        send_endpoint_descriptor(4'd1, 1'b1, EP_INTERRUPT, 11'd8, 8'd10); // EP1 IN
        
        // Wait for parsing to complete
        #1000;
        wait (done || $time > 100000);
        
        if (endpoints_found == 1) begin
            $display("  PASS: Found 1 matching endpoint");
        end else begin
            $display("  ERROR: Found %0d endpoints (expected 1)", endpoints_found);
            errors = errors + 1;
        end
        
        enable = 0;
        #1000;
        
        //--------------------------------------------------------------------
        // Test 2: Parse HID Mouse descriptors
        //--------------------------------------------------------------------
        test_num = 2;
        $display("\n=== Test %0d: Parse HID Mouse Descriptors ===", test_num);
        
        rst_n = 0;
        #100;
        rst_n = 1;
        #100;
        
        // Configure filter for HID Mouse (Class=03, Protocol=02)
        filter_class = 8'h03;        // HID
        filter_subclass = 8'h01;     // Boot Interface
        filter_protocol = 8'h02;     // Mouse
        filter_transfer_type = EP_INTERRUPT;
        filter_direction = 1;        // IN
        
        enable = 1;
        endpoints_found = 0;
        
        // Send descriptors
        send_device_descriptor();
        send_config_descriptor();
        send_interface_descriptor(8'd0, 8'h03, 8'h01, 8'h02); // HID Mouse
        send_endpoint_descriptor(4'd1, 1'b1, EP_INTERRUPT, 11'd4, 8'd10); // EP1 IN
        
        // Wait for parsing
        #1000;
        wait (done || $time > 100000);
        
        if (endpoints_found == 1) begin
            $display("  PASS: Found 1 matching endpoint");
        end else begin
            $display("  ERROR: Found %0d endpoints (expected 1)", endpoints_found);
            errors = errors + 1;
        end
        
        enable = 0;
        #1000;
        
        //--------------------------------------------------------------------
        // Test 3: Filter non-matching interface
        //--------------------------------------------------------------------
        test_num = 3;
        $display("\n=== Test %0d: Filter Non-Matching Interface ===", test_num);
        
        rst_n = 0;
        #100;
        rst_n = 1;
        #100;
        
        // Configure filter for HID Keyboard
        filter_class = 8'h03;
        filter_protocol = 8'h01;     // Keyboard
        
        enable = 1;
        endpoints_found = 0;
        
        // Send descriptors with Mass Storage interface (should not match)
        send_device_descriptor();
        send_config_descriptor();
        send_interface_descriptor(8'd0, 8'h08, 8'h06, 8'h50); // Mass Storage
        send_endpoint_descriptor(4'd1, 1'b1, EP_BULK, 11'd64, 8'd0);
        
        // Wait for parsing
        #1000;
        wait (done || $time > 100000);
        
        if (endpoints_found == 0) begin
            $display("  PASS: Correctly filtered non-matching interface");
        end else begin
            $display("  ERROR: Found %0d endpoints (expected 0)", endpoints_found);
            errors = errors + 1;
        end
        
        enable = 0;
        #1000;
        
        //--------------------------------------------------------------------
        // Test 4: Multiple endpoints with filtering
        //--------------------------------------------------------------------
        test_num = 4;
        $display("\n=== Test %0d: Multiple Endpoints with Filtering ===", test_num);
        
        rst_n = 0;
        #100;
        rst_n = 1;
        #100;
        
        // Filter for IN endpoints only
        filter_class = 8'h03;        // HID
        filter_protocol = 8'h01;     // Keyboard
        filter_direction = 1;        // IN only
        
        enable = 1;
        endpoints_found = 0;
        
        // Send descriptors
        send_device_descriptor();
        send_config_descriptor();
        send_interface_descriptor(8'd0, 8'h03, 8'h01, 8'h01);
        send_endpoint_descriptor(4'd1, 1'b1, EP_INTERRUPT, 11'd8, 8'd10);  // EP1 IN
        send_endpoint_descriptor(4'd2, 1'b0, EP_INTERRUPT, 11'd8, 8'd10);  // EP2 OUT
        send_endpoint_descriptor(4'd3, 1'b1, EP_INTERRUPT, 11'd8, 8'd10);  // EP3 IN
        
        // Wait for parsing
        #1000;
        wait (done || $time > 100000);
        
        if (endpoints_found == 2) begin
            $display("  PASS: Found 2 IN endpoints (filtered OUT)");
        end else begin
            $display("  WARNING: Found %0d endpoints (expected 2)", endpoints_found);
            warnings = warnings + 1;
        end
        
        enable = 0;
        #1000;
        
        //--------------------------------------------------------------------
        // Test 5: Endpoint type filtering
        //--------------------------------------------------------------------
        test_num = 5;
        $display("\n=== Test %0d: Endpoint Type Filtering ===", test_num);
        
        rst_n = 0;
        #100;
        rst_n = 1;
        #100;
        
        // Filter for INTERRUPT endpoints only
        filter_class = 8'h03;
        filter_protocol = 8'h01;
        filter_transfer_type = EP_INTERRUPT;
        filter_direction = 1;
        
        enable = 1;
        endpoints_found = 0;
        
        // Send descriptors with mixed endpoint types
        send_device_descriptor();
        send_config_descriptor();
        send_interface_descriptor(8'd0, 8'h03, 8'h01, 8'h01);
        send_endpoint_descriptor(4'd1, 1'b1, EP_INTERRUPT, 11'd8, 8'd10);  // Match
        send_endpoint_descriptor(4'd2, 1'b1, EP_BULK, 11'd64, 8'd0);       // No match
        
        // Wait for parsing
        #1000;
        wait (done || $time > 100000);
        
        if (endpoints_found == 1) begin
            $display("  PASS: Found 1 INTERRUPT endpoint (filtered BULK)");
        end else begin
            $display("  WARNING: Found %0d endpoints (expected 1)", endpoints_found);
            warnings = warnings + 1;
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
        #50000000;  // 50ms timeout
        $display("\nERROR: Testbench timeout!");
        $finish;
    end

endmodule
