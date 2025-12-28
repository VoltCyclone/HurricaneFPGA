///////////////////////////////////////////////////////////////////////////////
// File: usb_token_arbiter.v
// Description: USB Token Request Arbiter
//
// Arbitrates token generator requests from multiple USB host controllers.
// This is a request-level arbiter (not data path multiplexing).
//
// Priority order:
// 1. Enumerator (highest - enumeration must complete)
// 2. Transaction Engine (normal data transfers)
// 3. Keyboard Engine (lowest - periodic polling)
//
// Target: Lattice ECP5 on Cynthion device
///////////////////////////////////////////////////////////////////////////////

module usb_token_arbiter (
    input  wire        clk,
    input  wire        rst_n,
    
    // Enumerator Token Request Interface
    input  wire        enum_token_start,
    input  wire [1:0]  enum_token_type,
    input  wire [6:0]  enum_token_addr,
    input  wire [3:0]  enum_token_endp,
    input  wire        enum_active,
    
    // Transaction Engine Token Request Interface
    input  wire        trans_token_start,
    input  wire [1:0]  trans_token_type,
    input  wire [6:0]  trans_token_addr,
    input  wire [3:0]  trans_token_endp,
    input  wire        trans_active,
    
    // Keyboard Engine Token Request Interface
    input  wire        kbd_token_start,
    input  wire [1:0]  kbd_token_type,
    input  wire [6:0]  kbd_token_addr,
    input  wire [3:0]  kbd_token_endp,
    input  wire        kbd_active,
    
    // Token Generator Interface (output)
    output reg         token_start,
    output reg  [1:0]  token_type,
    output reg  [6:0]  token_addr,
    output reg  [3:0]  token_endp
);

    // Priority-based token request selection
    always @(*) begin
        // Default: keyboard engine (lowest priority)
        token_start = kbd_token_start;
        token_type = kbd_token_type;
        token_addr = kbd_token_addr;
        token_endp = kbd_token_endp;
        
        // Transaction engine (higher priority)
        if (trans_active && trans_token_start) begin
            token_start = trans_token_start;
            token_type = trans_token_type;
            token_addr = trans_token_addr;
            token_endp = trans_token_endp;
        end
        
        // Enumerator (highest priority)
        if (enum_active && enum_token_start) begin
            token_start = enum_token_start;
            token_type = enum_token_type;
            token_addr = enum_token_addr;
            token_endp = enum_token_endp;
        end
    end

endmodule
