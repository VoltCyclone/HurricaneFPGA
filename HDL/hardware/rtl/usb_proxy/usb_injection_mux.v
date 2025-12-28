///////////////////////////////////////////////////////////////////////////////
// File: usb_injection_mux.v
// Description: USB HID Report Injection Multiplexer
//
// This module merges real USB HID reports from the host device with
// injected reports from the SAMD51 (via UART commands). Injected reports
// are inserted into the USB stream transparently.
//
// Features:
// - Keyboard report injection (8 bytes)
// - Mouse report injection (5 bytes)
// - Priority handling (injection takes precedence)
// - Automatic report release (inject 0x00 release after key press)
//
// Target: Lattice ECP5 on Cynthion device
///////////////////////////////////////////////////////////////////////////////

module usb_injection_mux (
    // Clock and Reset
    input  wire        clk,                 // System clock
    input  wire        rst_n,               // Active low reset
    
    // Real HID Reports from USB Host
    input  wire [63:0] host_kbd_report,     // Real keyboard report
    input  wire        host_kbd_valid,      // Real keyboard report valid
    input  wire [39:0] host_mouse_report,   // Real mouse report
    input  wire        host_mouse_valid,    // Real mouse report valid
    
    // Injected Reports from SAMD51
    input  wire [63:0] inject_kbd_report,   // Injected keyboard report
    input  wire        inject_kbd_valid,    // Injection request
    output reg         inject_kbd_ack,      // Injection acknowledged
    input  wire [39:0] inject_mouse_report, // Injected mouse report
    input  wire        inject_mouse_valid,  // Injection request
    output reg         inject_mouse_ack,    // Injection acknowledged
    
    // Output to USB Device (merged stream)
    output reg  [63:0] out_kbd_report,      // Merged keyboard report
    output reg         out_kbd_valid,       // Merged keyboard valid
    output reg  [39:0] out_mouse_report,    // Merged mouse report
    output reg         out_mouse_valid      // Merged mouse valid
);

    // Injection state
    reg kbd_inject_pending;
    reg mouse_inject_pending;
    
    // Report release generator (auto-release after injection)
    reg [15:0] kbd_release_timer;
    reg        kbd_release_pending;
    reg [15:0] mouse_release_timer;
    reg        mouse_release_pending;
    
    localparam RELEASE_DELAY = 16'd6000;  // 100µs at 60MHz = auto-release delay
    
    // =======================================================================
    // Keyboard Report Multiplexer
    // =======================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_kbd_report <= 64'd0;
            out_kbd_valid <= 1'b0;
            inject_kbd_ack <= 1'b0;
            kbd_inject_pending <= 1'b0;
            kbd_release_timer <= 16'd0;
            kbd_release_pending <= 1'b0;
        end else begin
            // Default: clear acknowledgment
            inject_kbd_ack <= 1'b0;
            out_kbd_valid <= 1'b0;
            
            // Handle injection request
            if (inject_kbd_valid && !kbd_inject_pending) begin
                kbd_inject_pending <= 1'b1;
                inject_kbd_ack <= 1'b1;
            end
            
            // Priority: Injected report > Real report
            if (kbd_inject_pending) begin
                // Send injected report
                out_kbd_report <= inject_kbd_report;
                out_kbd_valid <= 1'b1;
                kbd_inject_pending <= 1'b0;
                
                // Check if it's a key press (any non-zero keys)
                if (inject_kbd_report[47:0] != 48'd0) begin
                    // Start release timer to auto-release keys
                    kbd_release_timer <= RELEASE_DELAY;
                    kbd_release_pending <= 1'b1;
                end
            end
            else if (kbd_release_pending) begin
                // Count down release timer
                if (kbd_release_timer > 0) begin
                    kbd_release_timer <= kbd_release_timer - 1'b1;
                end else begin
                    // Send release report (all zeros)
                    out_kbd_report <= 64'd0;
                    out_kbd_valid <= 1'b1;
                    kbd_release_pending <= 1'b0;
                end
            end
            else if (host_kbd_valid) begin
                // Pass through real report
                out_kbd_report <= host_kbd_report;
                out_kbd_valid <= 1'b1;
            end
        end
    end
    
    // =======================================================================
    // Mouse Report Multiplexer
    // =======================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_mouse_report <= 40'd0;
            out_mouse_valid <= 1'b0;
            inject_mouse_ack <= 1'b0;
            mouse_inject_pending <= 1'b0;
            mouse_release_timer <= 16'd0;
            mouse_release_pending <= 1'b0;
        end else begin
            // Default: clear acknowledgment
            inject_mouse_ack <= 1'b0;
            out_mouse_valid <= 1'b0;
            
            // Handle injection request
            if (inject_mouse_valid && !mouse_inject_pending) begin
                mouse_inject_pending <= 1'b1;
                inject_mouse_ack <= 1'b1;
            end
            
            // Priority: Injected report > Real report
            if (mouse_inject_pending) begin
                // Send injected report
                out_mouse_report <= inject_mouse_report;
                out_mouse_valid <= 1'b1;
                mouse_inject_pending <= 1'b0;
                
                // Check if it's a button press (button bits non-zero)
                if (inject_mouse_report[7:0] != 8'd0) begin
                    // Start release timer to auto-release buttons
                    mouse_release_timer <= RELEASE_DELAY;
                    mouse_release_pending <= 1'b1;
                end
            end
            else if (mouse_release_pending) begin
                // Count down release timer
                if (mouse_release_timer > 0) begin
                    mouse_release_timer <= mouse_release_timer - 1'b1;
                end else begin
                    // Send release report (all zeros)
                    out_mouse_report <= 40'd0;
                    out_mouse_valid <= 1'b1;
                    mouse_release_pending <= 1'b0;
                end
            end
            else if (host_mouse_valid) begin
                // Pass through real report
                out_mouse_report <= host_mouse_report;
                out_mouse_valid <= 1'b1;
            end
        end
    end

endmodule
