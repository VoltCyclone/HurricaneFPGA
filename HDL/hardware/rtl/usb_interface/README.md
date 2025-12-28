# USB Host Components

This directory contains the USB host controller implementation for HurricaneFPGA, enabling full USB device enumeration and interaction capabilities.

## Core Components

### 1. USB Reset Controller (`usb_reset_controller.v`)
Handles USB bus reset sequence with automatic speed detection.

**Features:**
- SE0 reset signaling (minimum 10ms)
- High-speed chirp negotiation (K-J-K-J pattern)
- Automatic speed detection (Full-Speed 12Mbit / High-Speed 480Mbit)
- PHY configuration management
- Line state monitoring

**Interfaces:**
- Control: `bus_reset_req`, `reset_active`, `detected_speed`
- PHY Control: `phy_op_mode`, `phy_xcvr_select`, `phy_term_select`
- PHY Status: `phy_line_state`
- UTMI TX: For chirp generation

### 2. Token Packet Generator (`usb_token_generator.v`)
Generates USB token packets with proper PID encoding and CRC5 calculation.

**Features:**
- Supports OUT, IN, SOF, and SETUP tokens
- Automatic CRC5 calculation
- PID encoding with inverted check nibble
- UTMI transmit interface

**Token Types:**
- `00`: OUT
- `01`: IN
- `10`: SOF
- `11`: SETUP

**Interfaces:**
- Request: `token_start`, `token_type`, `token_addr`, `token_endp`, `token_frame`
- Status: `token_ready`, `token_done`
- UTMI TX: `utmi_tx_data`, `utmi_tx_valid`, `utmi_tx_ready`

### 3. SOF Generator (`usb_sof_generator.v`)
Generates Start-of-Frame packets at proper intervals.

**Features:**
- 1ms intervals for Full-Speed
- 125us intervals for High-Speed
- 11-bit frame counter (0-2047)
- Automatic wraparound
- Integrates with token generator

**Interfaces:**
- Control: `enable`, `speed`
- Output: `sof_trigger`, `frame_number`
- Token Generator Interface

### 4. Descriptor Parser (`usb_descriptor_parser.v`)
Parses USB configuration descriptors to extract endpoint information.

**Features:**
- Streaming descriptor parser
- Interface class/subclass/protocol filtering
- Endpoint extraction (number, direction, type, max packet size, interval)
- Supports device, configuration, interface, and endpoint descriptors

**Filter Configuration:**
- `filter_class`: Interface class (e.g., 0x03 for HID)
- `filter_subclass`: Interface subclass (0xFF = any)
- `filter_protocol`: Interface protocol (0xFF = any)
- `filter_transfer_type`: Endpoint type (00=control, 01=iso, 10=bulk, 11=interrupt)
- `filter_direction`: 0=OUT, 1=IN

**Output:**
- `endp_number`, `endp_direction`, `endp_type`
- `endp_max_packet`, `endp_interval`
- `valid`, `done`

### 5. USB Enumerator (`usb_enumerator.v`)
**Status:** Skeleton implemented, needs completion

Main enumeration state machine that orchestrates the full USB enumeration sequence.

**Planned Sequence:**
1. Bus Reset
2. Get Device Descriptor (8 bytes) - learn bMaxPacketSize
3. Set Address (assign non-zero address)
4. Get Device Descriptor (18 bytes) - full descriptor
5. Get Configuration Descriptor - parse interfaces/endpoints
6. Set Configuration (activate configuration 1)

## Device Class Engines

### 1. HID Keyboard Engine (`usb_hid_keyboard_engine.v`)
Polls USB HID keyboard devices for keypress data.

**Features:**
- Interrupt endpoint polling (every 1ms frame)
- 8-byte keyboard report parsing
- DATA0/DATA1 PID toggling
- Watchdog timer (3-second timeout)
- NAK/STALL handling
- Error recovery

**Output Report Format:**
- `report_modifiers`: Ctrl, Shift, Alt, GUI keys
- `report_key0` - `report_key5`: Up to 6 simultaneous key codes

**Status Flags:**
- `STATUS_ACTIVE`: Engine is polling
- `STATUS_ERROR`: Error occurred
- `STATUS_STALL`: Device stalled
- `STATUS_TIMEOUT`: Watchdog timeout
- `STATUS_ENUMERATED`: Device ready

### 2. USB MIDI Engine
**Status:** Not yet implemented

See `guh/engines/midi.py` for reference implementation.

### 3. USB Mass Storage Engine
**Status:** Not yet implemented

See `guh/engines/msc.py` for reference implementation.

## Integration Example

```verilog
// Instantiate reset controller
usb_reset_controller reset_ctrl (
    .clk(clk),
    .rst_n(rst_n),
    .bus_reset_req(bus_reset_req),
    .reset_active(reset_active),
    .detected_speed(detected_speed),
    .phy_line_state(phy_line_state),
    // ... other connections
);

// Instantiate token generator
usb_token_generator token_gen (
    .clk(clk),
    .rst_n(rst_n),
    .token_start(token_start),
    .token_type(token_type),
    .token_addr(token_addr),
    .token_endp(token_endp),
    .token_ready(token_ready),
    .token_done(token_done),
    // ... UTMI interface
);

// Instantiate SOF generator
usb_sof_generator sof_gen (
    .clk(clk),
    .rst_n(rst_n),
    .enable(sof_enable),
    .speed(device_speed),
    .sof_trigger(sof_trigger),
    .frame_number(frame_number),
    // ... token generator interface
);

// Instantiate HID keyboard engine
usb_hid_keyboard_engine kbd_engine (
    .clk(clk),
    .rst_n(rst_n),
    .enable(kbd_enable),
    .enumerated(enum_done),
    .device_addr(device_addr),
    .endp_number(kbd_endp),
    .sof_trigger(sof_trigger),
    .frame_number(frame_number),
    .report_valid(kbd_report_valid),
    .report_modifiers(kbd_modifiers),
    // ... other connections
);
```

## Testing

### Unit Tests
Located in `HDL/hardware/testbenches/`

- `tb_usb_token_generator.v`: Tests token generation and CRC5
- `tb_usb_reset_controller.v`: Tests reset sequence and speed detection (TODO)
- `tb_usb_sof_generator.v`: Tests SOF timing (TODO)
- `tb_usb_descriptor_parser.v`: Tests descriptor parsing with real data (TODO)

### Running Simulations

Using Icarus Verilog:
```bash
cd HDL/hardware/testbenches
iverilog -o tb_token tb_usb_token_generator.v ../rtl/usb_interface/usb_token_generator.v
vvp tb_token
gtkwave tb_usb_token_generator.vcd
```

Using Verilator (for faster simulation):
```bash
verilator --lint-only ../rtl/usb_interface/usb_token_generator.v
```

## Timing Requirements

### Full-Speed (12 Mbit/s)
- Bit time: 83.3 ns
- SOF interval: 1 ms (1000 frames/second)
- Inter-packet delay: 2 bit times minimum

### High-Speed (480 Mbit/s)
- Bit time: 2.08 ns
- SOF interval: 125 us (8000 microframes/second)
- Inter-packet delay: 8 bit times minimum

### Clock Requirements
- System clock: 60 MHz (minimum)
- PHY clock: 240 MHz for high-speed operation
- All timing is derived from system clock

## USB 2.0 Compliance

These modules implement the following USB 2.0 specification sections:
- Section 7.1.7.5: Reset Signaling
- Section 8.3.1: Sync Field
- Section 8.4: Token Packets
- Section 8.4.3: Start-of-Frame Packets
- Section 8.5: Data Packets
- Section 9: USB Device Framework (enumeration)

## Known Limitations

1. **Enumerator**: Not fully implemented yet
2. **Hub Support**: Not implemented
3. **Low-Speed**: Not tested (implementation focuses on FS/HS)
4. **Error Recovery**: Basic implementation, could be more robust
5. **Multiple Devices**: No multi-device support (no hub)

## Future Enhancements

1. Complete USB enumerator implementation
2. Add USB MIDI device support
3. Add USB Mass Storage device support
4. Improve error recovery and retry logic
5. Add disconnect detection
6. Add USB hub support
7. Comprehensive simulation test suite
8. PCAP file generation for packet analysis

## References

- [USB 2.0 Specification](https://www.usb.org/document-library/usb-20-specification)
- [LUNA USB Framework](https://github.com/greatscottgadgets/luna)
- [guh - Gateware USB Host](https://github.com/apfaudio/guh)
- [USB Made Simple](https://www.usbmadesimple.co.uk/)

## Contributing

When adding new components:
1. Follow the existing module structure
2. Add comprehensive comments
3. Create a testbench
4. Update this README
5. Update IMPLEMENTATION_PLAN.md

## License

Same as HurricaneFPGA project (see root LICENSE file).
