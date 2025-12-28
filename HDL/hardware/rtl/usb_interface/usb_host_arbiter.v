///////////////////////////////////////////////////////////////////////////////
// File: usb_host_arbiter.v
// Description: USB Host PHY Arbiter - Multiplexes multiple host controllers
//
// This module arbitrates access to the USB host PHY between multiple
// controllers (reset, enumerator, transaction engine, etc.)
//
// Priority order:
// 1. Reset Controller (highest priority - handles bus reset)
// 2. Enumerator (handles device enumeration)
// 3. Transaction Engine (handles normal transfers)
// 4. Protocol Handler (lowest priority - fallback)
//
// Target: Lattice ECP5 on Cynthion device
///////////////////////////////////////////////////////////////////////////////

module usb_host_arbiter (
    input  wire        clk,
    input  wire        rst_n,
    
    // Reset Controller Interface
    input  wire [7:0]  reset_tx_data,
    input  wire        reset_tx_valid,
    input  wire        reset_active,
    
    // Enumerator Interface
    input  wire [7:0]  enum_tx_data,
    input  wire        enum_tx_valid,
    input  wire        enum_active,
    
    // Transaction Engine Interface
    input  wire [7:0]  trans_tx_data,
    input  wire        trans_tx_valid,
    input  wire        trans_active,
    
    // Protocol Handler Interface
    input  wire [7:0]  protocol_tx_data,
    input  wire        protocol_tx_valid,
    input  wire        protocol_active,
    
    // Token Generator Interface
    input  wire [7:0]  token_tx_data,
    input  wire        token_tx_valid,
    input  wire        token_active,
    
    // SOF Generator Interface
    input  wire [7:0]  sof_tx_data,
    input  wire        sof_tx_valid,
    input  wire        sof_active,
    
    // Multiplexed PHY Output
    output reg  [7:0]  phy_tx_data,
    output reg         phy_tx_valid
);

    // Priority selection (higher number = higher priority)
    always @(*) begin
        // Default: protocol handler (lowest priority)
        phy_tx_data = protocol_tx_data;
        phy_tx_valid = protocol_active ? protocol_tx_valid : 1'b0;
        
        // SOF generator
        if (sof_active && sof_tx_valid) begin
            phy_tx_data = sof_tx_data;
            phy_tx_valid = sof_tx_valid;
        end
        
        // Token generator
        if (token_active && token_tx_valid) begin
            phy_tx_data = token_tx_data;
            phy_tx_valid = token_tx_valid;
        end
        
        // Transaction engine
        if (trans_active && trans_tx_valid) begin
            phy_tx_data = trans_tx_data;
            phy_tx_valid = trans_tx_valid;
        end
        
        // Enumerator (high priority)
        if (enum_active && enum_tx_valid) begin
            phy_tx_data = enum_tx_data;
            phy_tx_valid = enum_tx_valid;
        end
        
        // Reset controller (highest priority)
        if (reset_active && reset_tx_valid) begin
            phy_tx_data = reset_tx_data;
            phy_tx_valid = reset_tx_valid;
        end
    end

endmodule
