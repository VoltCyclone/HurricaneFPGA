///////////////////////////////////////////////////////////////////////////////
// File: usb_descriptor_parser.v
// Description: USB Descriptor Parser for Endpoint Extraction
//
// Parses USB configuration descriptors to extract interface and endpoint
// information. Filters based on interface class, subclass, and protocol.
//
// Supports:
// - Device descriptors (0x01)
// - Configuration descriptors (0x02)
// - Interface descriptors (0x04)
// - Endpoint descriptors (0x05)
///////////////////////////////////////////////////////////////////////////////

module usb_descriptor_parser (
    // Clock and Reset
    input  wire        clk,                 // System clock
    input  wire        rst_n,               // Active low reset
    
    // Control Interface
    input  wire        enable,              // Enable parsing
    output reg         done,                // Parsing complete
    output reg         valid,               // Valid endpoints found
    
    // Descriptor Stream Input
    input  wire [7:0]  desc_data,           // Descriptor byte stream
    input  wire        desc_valid,          // Data valid
    output reg         desc_ready,          // Ready for data
    
    // Filter Configuration
    input  wire [7:0]  filter_class,        // Interface class to match
    input  wire [7:0]  filter_subclass,     // Interface subclass (0xFF=any)
    input  wire [7:0]  filter_protocol,     // Interface protocol (0xFF=any)
    input  wire [1:0]  filter_transfer_type, // Endpoint transfer type
    input  wire        filter_direction,    // 0=OUT, 1=IN
    
    // Extracted Endpoint Information
    output reg  [3:0]  endp_number,         // Endpoint number
    output reg         endp_direction,      // 0=OUT, 1=IN
    output reg  [1:0]  endp_type,           // Transfer type
    output reg  [10:0] endp_max_packet,     // Max packet size
    output reg  [7:0]  endp_interval,       // Polling interval
    output reg  [7:0]  iface_protocol_out,  // Interface protocol for this endpoint
    output reg  [7:0]  iface_number_out     // Interface number for this endpoint
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
    reg [7:0]  desc_length;         // bLength field
    reg [7:0]  desc_offset;         // Current offset in descriptor
    reg [7:0]  desc_type;           // Current descriptor type
    
    // Interface descriptor fields
    reg [7:0]  iface_class;
    reg [7:0]  iface_subclass;
    reg [7:0]  iface_protocol;
    reg [7:0]  iface_number;        // Interface number (bInterfaceNumber)
    reg        in_matching_iface;   // Currently in a matching interface
    
    // Endpoint descriptor temporary storage
    reg [7:0]  temp_endp_addr;      // bEndpointAddress
    reg [7:0]  temp_endp_attr;      // bmAttributes
    reg [10:0] temp_max_packet_low; // wMaxPacketSize (storing across cycles)
    
    // Endpoint found flags
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
            temp_max_packet_low <= 11'd0;
            found_endpoint <= 1'b0;
            endp_number <= 4'd0;
            endp_direction <= 1'b0;
            endp_max_packet <= 11'd0;
            endp_interval <= 8'd0;
            iface_protocol_out <= 8'd0;
            iface_number_out <= 8'd0;
            iface_protocol_out <= 8'd0;
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
                        // Process based on offset within current descriptor
                        case (desc_offset)
                            8'd0: begin
                                // Byte 1: descriptor type
                                desc_type <= desc_data;
                            end
                            // Interface Descriptor fields
                            8'd1: begin
                                if (desc_type == DESC_INTERFACE) begin
                                    iface_number <= desc_data;  // bInterfaceNumber
                                end
                            end
                            
                            8'd4: begin
                                if (desc_type == DESC_INTERFACE) begin
                                    iface_class <= desc_data;
                                end
                            end end
                            end
                            
                            8'd5: begin
                                if (desc_type == DESC_INTERFACE) begin
                                    iface_subclass <= desc_data;
                                end
                            end
                            
                            8'd6: begin
                                if (desc_type == DESC_INTERFACE) begin
                                    iface_protocol <= desc_data;
                                end
                            end
                            
                            // Endpoint Descriptor fields
                            8'd1: begin
                                if (desc_type == DESC_ENDPOINT) begin
                                    temp_endp_addr <= desc_data;
                                end
                            end
                            
                            8'd2: begin
                                if (desc_type == DESC_ENDPOINT) begin
                                    temp_endp_attr <= desc_data;
                                end
                            end
                            
                            8'd3: begin
                                if (desc_type == DESC_ENDPOINT) begin
                                    // wMaxPacketSize low byte
                                    temp_max_packet_low[7:0] <= desc_data;
                                end
                            end
                            
                            8'd4: begin
                                if (desc_type == DESC_ENDPOINT) begin
                                    // wMaxPacketSize high byte (only lower 3 bits)
                                    temp_max_packet_low[10:8] <= desc_data[2:0];
                                end
                            end
                            
                            8'd5: begin
                                if (desc_type == DESC_ENDPOINT) begin
                                    // bInterval
                                    endp_interval <= desc_data;
                                end
                            end
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
                            end
                                // Check if endpoint matches filter
                                if (ep_type == filter_transfer_type && ep_dir == filter_direction) begin
                                    endp_number <= ep_num;
                                    endp_direction <= ep_dir;
                                    endp_type <= ep_type;
                                    endp_max_packet <= temp_max_packet_low;
                                    iface_protocol_out <= iface_protocol;  // Output the protocol
                                    iface_number_out <= iface_number;      // Output interface number
                                    found_endpoint <= 1'b1;
                                    valid <= 1'b1;
                                    state <= STATE_DONE;m;
                                    endp_direction <= ep_dir;
                                    endp_type <= ep_type;
                                    endp_max_packet <= temp_max_packet_low;
                                    iface_protocol_out <= iface_protocol;  // Output the protocol
                                    found_endpoint <= 1'b1;
                                    valid <= 1'b1;
                                    state <= STATE_DONE;
                                end else begin
                                    state <= STATE_GET_LENGTH;
                                end
                            end else if (desc_type == DESC_CONFIGURATION && desc_offset == 8'd0) begin
                                // Configuration descriptor is first, continue parsing
                                state <= STATE_GET_LENGTH;
                            end else begin
                                // Continue to next descriptor
                                state <= STATE_GET_LENGTH;
                            end
                        end
                    end
                end
                
                STATE_DONE: begin
                    done <= 1'b1;
                    desc_ready <= 1'b0;
                    // Stay in this state until reset
                end
                
                default: begin
                    state <= STATE_IDLE;
                end
            endcase
        end
    end

endmodule
