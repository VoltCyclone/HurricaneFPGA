///////////////////////////////////////////////////////////////////////////////
// File: usb_descriptor_parser.v (FIXED VERSION)
// Description: USB Descriptor Parser for Endpoint Extraction
//
// FIXES APPLIED:
// - CRITICAL: Fixed duplicate case labels by using if-else based on desc_type
// - Removed duplicate assignment on line 110-111
// - Improved clarity of descriptor field extraction
//
// Supports:
// - Device descriptors (0x01)
// - Configuration descriptors (0x02)
// - Interface descriptors (0x04)
// - Endpoint descriptors (0x05)
///////////////////////////////////////////////////////////////////////////////

module usb_descriptor_parser (
    // Clock and Reset
    input  wire        clk,
    input  wire        rst_n,
    
    // Control Interface
    input  wire        enable,
    output reg         done,
    output reg         valid,
    
    // Descriptor Stream Input
    input  wire [7:0]  desc_data,
    input  wire        desc_valid,
    output reg         desc_ready,
    
    // Filter Configuration
    input  wire [7:0]  filter_class,
    input  wire [7:0]  filter_subclass,
    input  wire [7:0]  filter_protocol,
    input  wire [1:0]  filter_transfer_type,
    input  wire        filter_direction,
    
    // Extracted Endpoint Information
    output reg  [3:0]  endp_number,
    output reg         endp_direction,
    output reg  [1:0]  endp_type,
    output reg  [10:0] endp_max_packet,
    output reg  [7:0]  endp_interval,
    output reg  [7:0]  iface_protocol_out,
    output reg  [7:0]  iface_number_out
);

    // Descriptor Types
    localparam DESC_DEVICE        = 8'h01;
    localparam DESC_CONFIGURATION = 8'h02;
    localparam DESC_STRING        = 8'h03;
    localparam DESC_INTERFACE     = 8'h04;
    localparam DESC_ENDPOINT      = 8'h05;
    
    // Transfer Types
    localparam XFER_CONTROL     = 2'b00;
    localparam XFER_ISOCHRONOUS = 2'b01;
    localparam XFER_BULK        = 2'b10;
    localparam XFER_INTERRUPT   = 2'b11;
    
    // State Machine
    localparam STATE_IDLE          = 3'd0;
    localparam STATE_GET_LENGTH    = 3'd1;
    localparam STATE_IN_DESCRIPTOR = 3'd2;
    localparam STATE_DONE          = 3'd3;
    
    reg [2:0]  state;
    reg [7:0]  desc_length;
    reg [7:0]  desc_offset;
    reg [7:0]  desc_type;
    
    // Interface descriptor fields
    reg [7:0]  iface_class;
    reg [7:0]  iface_subclass;
    reg [7:0]  iface_protocol;
    reg [7:0]  iface_number;
    reg        in_matching_iface;
    
    // Endpoint descriptor temporary storage
    reg [7:0]  temp_endp_addr;
    reg [7:0]  temp_endp_attr;
    reg [10:0] temp_max_packet;
    
    // Endpoint found flag
    reg        found_endpoint;
    
    // State Machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            done <= 1'b0;
            valid <= 1'b0;
            desc_ready <= 1'b0;
            desc_length <= 8'd0;
            desc_offset <= 8'd0;
            desc_type <= 8'd0;
            iface_class <= 8'd0;
            iface_subclass <= 8'd0;
            iface_protocol <= 8'd0;
            iface_number <= 8'd0;
            in_matching_iface <= 1'b0;
            temp_endp_addr <= 8'd0;
            temp_endp_attr <= 8'd0;
            temp_max_packet <= 11'd0;
            found_endpoint <= 1'b0;
            endp_number <= 4'd0;
            endp_direction <= 1'b0;
            endp_max_packet <= 11'd0;
            endp_interval <= 8'd0;
            iface_protocol_out <= 8'd0;  // FIXED: Single assignment
            iface_number_out <= 8'd0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    done <= 1'b0;
                    valid <= 1'b0;
                    desc_ready <= 1'b0;
                    in_matching_iface <= 1'b0;
                    found_endpoint <= 1'b0;
                    
                    if (enable) begin
                        state <= STATE_GET_LENGTH;
                        desc_ready <= 1'b1;
                    end
                end
                
                STATE_GET_LENGTH: begin
                    if (desc_valid) begin
                        desc_length <= desc_data;
                        desc_offset <= 8'd0;
                        state <= STATE_IN_DESCRIPTOR;
                    end
                end
                
                STATE_IN_DESCRIPTOR: begin
                    if (desc_valid) begin
                        // FIXED: No more duplicate case labels
                        // Use if-else to distinguish between descriptor types
                        case (desc_offset)
                            8'd0: begin
                                // Byte 1 is always descriptor type
                                desc_type <= desc_data;
                            end
                            
                            8'd1: begin
                                // Different meaning for different descriptor types
                                if (desc_type == DESC_INTERFACE) begin
                                    // bInterfaceNumber
                                    iface_number <= desc_data;
                                end else if (desc_type == DESC_ENDPOINT) begin
                                    // bEndpointAddress
                                    temp_endp_addr <= desc_data;
                                end
                                // Other descriptor types: ignore or handle as needed
                            end
                            
                            8'd2: begin
                                if (desc_type == DESC_ENDPOINT) begin
                                    // bmAttributes
                                    temp_endp_attr <= desc_data;
                                end
                                // Interface descriptor byte 2: bAlternateSetting (not needed)
                            end
                            
                            8'd3: begin
                                if (desc_type == DESC_ENDPOINT) begin
                                    // wMaxPacketSize low byte
                                    temp_max_packet[7:0] <= desc_data;
                                end
                                // Interface descriptor byte 3: bNumEndpoints (not needed)
                            end
                            
                            8'd4: begin
                                if (desc_type == DESC_INTERFACE) begin
                                    // bInterfaceClass
                                    iface_class <= desc_data;
                                end else if (desc_type == DESC_ENDPOINT) begin
                                    // wMaxPacketSize high byte (only lower 3 bits used)
                                    temp_max_packet[10:8] <= desc_data[2:0];
                                end
                            end
                            
                            8'd5: begin
                                if (desc_type == DESC_INTERFACE) begin
                                    // bInterfaceSubClass
                                    iface_subclass <= desc_data;
                                end else if (desc_type == DESC_ENDPOINT) begin
                                    // bInterval
                                    endp_interval <= desc_data;
                                end
                            end
                            
                            8'd6: begin
                                if (desc_type == DESC_INTERFACE) begin
                                    // bInterfaceProtocol
                                    iface_protocol <= desc_data;
                                end
                                // Endpoint descriptors don't have byte 6
                            end
                            
                            // Note: Interface descriptor has byte 7 (iInterface string index)
                            // but we don't need it for endpoint extraction
                        endcase
                        
                        desc_offset <= desc_offset + 1'b1;
                        
                        // Check if this is the last byte of the descriptor
                        if (desc_offset == (desc_length - 2)) begin
                            // Process complete descriptor
                            
                            if (desc_type == DESC_INTERFACE) begin
                                // Check if interface matches filter
                                if (iface_class == filter_class &&
                                    (filter_subclass == 8'hFF || iface_subclass == filter_subclass) &&
                                    (filter_protocol == 8'hFF || iface_protocol == filter_protocol)) begin
                                    in_matching_iface <= 1'b1;
                                end else begin
                                    in_matching_iface <= 1'b0;
                                end
                                state <= STATE_GET_LENGTH;
                                
                            end else if (desc_type == DESC_ENDPOINT && in_matching_iface) begin
                                // Check if endpoint matches filter
                                if (temp_endp_attr[1:0] == filter_transfer_type && 
                                    temp_endp_addr[7] == filter_direction) begin
                                    // Found matching endpoint - extract info
                                    endp_number <= temp_endp_addr[3:0];
                                    endp_direction <= temp_endp_addr[7];
                                    endp_type <= temp_endp_attr[1:0];
                                    endp_max_packet <= temp_max_packet;
                                    iface_protocol_out <= iface_protocol;
                                    iface_number_out <= iface_number;
                                    found_endpoint <= 1'b1;
                                    valid <= 1'b1;
                                    state <= STATE_DONE;
                                end else begin
                                    // Endpoint doesn't match filter - continue parsing
                                    state <= STATE_GET_LENGTH;
                                end
                                
                            end else if (desc_type == DESC_CONFIGURATION) begin
                                // Configuration descriptor is first - continue
                                state <= STATE_GET_LENGTH;
                                
                            end else begin
                                // Unknown/unhandled descriptor type - skip
                                state <= STATE_GET_LENGTH;
                            end
                        end
                    end
                end
                
                STATE_DONE: begin
                    done <= 1'b1;
                    desc_ready <= 1'b0;
                    // Stay in this state until reset or disable
                end
                
                default: begin
                    state <= STATE_IDLE;
                end
            endcase
        end
    end

endmodule