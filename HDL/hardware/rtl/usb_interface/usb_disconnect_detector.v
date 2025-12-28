// USB Disconnect Detector Module
// Monitors USB line state to detect device disconnection
// Triggers reset when device is unplugged (SE0 state for extended period)

module usb_disconnect_detector (
    input  wire clk,
    input  wire reset,
    
    // USB line state from PHY
    input  wire [1:0] line_state,  // 00=SE0, 01=J, 10=K, 11=SE1
    
    // Configuration
    input  wire enable,            // Enable disconnect detection
    input  wire high_speed,        // Speed mode (affects timeout)
    
    // Status output
    output reg  device_connected,
    output reg  disconnect_detected
);

    // Line state definitions
    localparam LINE_SE0 = 2'b00;  // Single-Ended Zero (both D+/D- low)
    localparam LINE_J   = 2'b01;  // J state (idle for FS/LS)
    localparam LINE_K   = 2'b10;  // K state
    localparam LINE_SE1 = 2'b11;  // Single-Ended One (both D+/D- high)
    
    // Disconnect detection timing
    // USB spec requires SE0 for 2.5us minimum for disconnect
    // Use 10us to be safe and filter glitches
    // At 60MHz: 10us = 600 cycles
    localparam DISCONNECT_TIMEOUT = 16'd600;
    
    // Debounce connect detection (device must be stable for 1ms)
    // At 60MHz: 1ms = 60000 cycles
    localparam CONNECT_TIMEOUT = 16'd60000;
    
    reg [15:0] se0_counter;
    reg [15:0] connect_counter;
    reg prev_connected;
    
    // Detect SE0 state (disconnect condition)
    wire is_se0 = (line_state == LINE_SE0);
    
    // Detect valid idle state (connected condition)
    // J state for Full-Speed/Low-Speed, or any non-SE0 for High-Speed
    wire is_idle = high_speed ? !is_se0 : (line_state == LINE_J);
    
    always @(posedge clk) begin
        if (reset || !enable) begin
            se0_counter <= 16'd0;
            connect_counter <= 16'd0;
            device_connected <= 1'b0;
            disconnect_detected <= 1'b0;
            prev_connected <= 1'b0;
        end else begin
            prev_connected <= device_connected;
            
            // Disconnect detection: count SE0 duration
            if (is_se0 && device_connected) begin
                if (se0_counter < DISCONNECT_TIMEOUT) begin
                    se0_counter <= se0_counter + 1'b1;
                end else begin
                    // SE0 held long enough - device disconnected
                    device_connected <= 1'b0;
                    disconnect_detected <= 1'b1;
                    connect_counter <= 16'd0;
                end
            end else begin
                // Reset SE0 counter if line state changes
                se0_counter <= 16'd0;
                disconnect_detected <= 1'b0;
            end
            
            // Connect detection: count stable idle duration
            if (is_idle && !device_connected) begin
                if (connect_counter < CONNECT_TIMEOUT) begin
                    connect_counter <= connect_counter + 1'b1;
                end else begin
                    // Idle held long enough - device connected
                    device_connected <= 1'b1;
                end
            end else if (is_se0 || device_connected) begin
                // Reset connect counter if SE0 or already connected
                connect_counter <= 16'd0;
            end
        end
    end

endmodule
