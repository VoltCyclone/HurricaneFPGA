# SAMD51 Firmware for Cynthion HID Injection

Rust firmware for the SAMD51 microcontroller on Cynthion to handle HID report injection and control.

## Overview

This firmware runs on the SAMD51 ARM Cortex-M4 (Apollo debug controller) and provides:
- USB CDC-ACM interface to host PC for commands
- UART communication with FPGA for HID injection
- Command protocol parser (nozen format)
- HID report construction helpers
- **HID descriptor parser** - NEW!
- **Descriptor caching (8 devices)** - NEW!
- **Automatic device type detection** - NEW!

## Architecture

```
Host PC
  ↓ USB
SAMD51 (This Firmware)
  ↓ UART0 @ 115200 baud
FPGA (HurricaneFPGA HDL)
  ↓ USB
Target Device
```

## Building

### Prerequisites

```bash
# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Add ARM Cortex-M4 target
rustup target add thumbv7em-none-eabihf

# Install cargo-binutils for objcopy
cargo install cargo-binutils
rustup component add llvm-tools-preview

# Install DFU programming tool (for flashing SAMD51)
pip install apollo-fpga
```

### Build Firmware

```bash
cd firmware/samd51_hid_injector
cargo build --release

# Convert to binary format
cargo objcopy --release -- -O binary target/thumbv7em-none-eabihf/release/samd51_hid_injector.bin
```

### Flash to SAMD51

```bash
# Put Cynthion into DFU mode (hold PROGRAM button, press RESET)
# Flash firmware
apollo flash-mcu target/thumbv7em-none-eabihf/release/samd51_hid_injector.bin
```

## Usage

### Python Control Example

```python
import serial

# Connect to SAMD51 via USB CDC-ACM
dev = serial.Serial('/dev/ttyACM0', 115200)

# Inject 'A' key press (HID scancode 0x04)
cmd = b'[CMD:10] [LEN:0008] \x00\x00\x04\x00\x00\x00\x00\x00 [CKSUM:0C]\n'
dev.write(cmd)

# Inject mouse move (+10, -5)
cmd = b'[CMD:11] [LEN:0005] \x00\x0A\xFB\x00\x00 [CKSUM:15]\n'
dev.write(cmd)
```

### Command Protocol

See `HDL/SAMD51_OFFLOAD_ARCHITECTURE.md` for full protocol specification.

#### Quick Reference

- `CMD:10` - INJECT_KBD (8 bytes: modifier, reserved, key1-6)
- `CMD:11` - INJECT_MOUSE (5 bytes: buttons, dx, dy, wheel, pan)
- `CMD:20` - SET_FILTER (4 bytes: filter mask)
- `CMD:21` - SET_MODE (1 byte: bit 0=proxy, bit 1=host)

## Development

### Project Structure

```
firmware/samd51_hid_injector/
├── Cargo.toml          # Dependencies and build config
├── memory.x            # Memory layout for SAMD51
├── src/
│   ├── main.rs         # Main firmware entry point
│   ├── usb_cdc.rs      # USB CDC-ACM interface
│   ├── uart.rs         # UART0 interface to FPGA
│   ├── protocol.rs     # Command protocol parser
│   └── hid.rs          # HID report helpers
└── README.md           # This file
```

### Dependencies

- `cortex-m` - ARM Cortex-M primitives
- `cortex-m-rt` - Runtime for ARM Cortex-M
- `atsamd-hal` - Hardware Abstraction Layer for SAMD51
- `usb-device` - USB device framework
- `usbd-serial` - USB CDC-ACM class

## Features

### Phase 1 (Current)
- [x] Basic firmware skeleton
- [x] USB CDC-ACM interface
- [x] UART0 communication with FPGA
- [x] Command protocol parser
- [x] Keyboard injection
- [x] Mouse injection

### Phase 2 (Future)
- [ ] HID descriptor parsing
- [ ] Keyboard layout translation
- [ ] Macro/script engine
- [ ] Report filtering
- [ ] Configuration persistence in flash

## License

See main project LICENSE file.
