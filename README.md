# HurricaneFPGA – HID Injection Tools

[![Build Status](https://github.com/ramseymcgrath/HurricaneFPGA/actions/workflows/get_bitstream.yml/badge.svg)](https://github.com/ramseymcgrath/HurricaneFPGA/actions/workflows/build_and_test.yml)
[![Code Coverage](https://codecov.io/gh/ramseymcgrath/HurricaneFPGA/branch/main/graph/badge.svg)](https://codecov.io/gh/yourusername/kmboxetry)

> ✨ **Current status – Full HDL Implementation with USB Host Mode!**  
> The project now provides **two implementations**:
> - **New HDL Implementation** (`HDL/`) - A complete Verilog implementation with:
>   - ✅ USB passthrough and monitoring
>   - ✅ UART-controlled HID injection
>   - ✅ **NEW: USB Host Mode** - Complete device enumeration and HID keyboard support
> - **Legacy Python/Luna** (`legacy/`) - Original amaranth/LUNA implementation
>
> The HDL implementation can now act as both a passive USB sniffer and an active USB keyboard host!

HurricaneFPGA explores low‑level USB manipulation on the **[Cynthion FPGA](https://greatscottgadgets.com/cynthion/)**. It ships:

- **Hurricane HDL** – Complete Verilog implementation for advanced USB manipulation
- **Legacy Amaranth/LUNA gateware** – FS passthrough + UART HID injection
- **Rust CLI** – network‑to‑UART bridge for easy scripting

---

## Table of Contents
1. [Features](#features)  
2. [Requirements](#requirements)  
3. [Installation](#installation)  
   3.1 [Environment setup](#1-environment-setup) | 3.2 [Build gateware](#2-build-the-fpga-gateware) | 3.3 [Flash gateware](#3-flash-the-fpga-gateware) | 3.4 [Build Rust CLI](#4-build-the-rust-cli)  
4. [Hardware setup](#hardware-setup)  
5. [Usage](#usage)  
   5.1 [Run gateway](#running-the-rust-gateway) | 5.2 [Send commands](#sending-commands)  
6. [Architecture](#architecture)  
7. [Development](#development)  
8. [Troubleshooting](#troubleshooting)  
9. [License](#license)  
10. [Acknowledgements](#acknowledgements)

---

## Features

### Core Features
- **USB passthrough** – Full‑/Low‑Speed packets flow between **TARGET (J2)** ⇄ **CONTROL (J3)**.
- **HID injection** – FPGA can splice one‑byte‑per‑axis mouse reports (`buttons, dx, dy`).
- **UART control** – Send _exactly_ three bytes over PMOD A @ 115200 baud to inject.
- **Rust gateway** – Accepts UDP strings (`buttons,dx,dy`) → forwards raw UART bytes.
- **Command acknowledgment** – FPGA sends ACK/NAK responses with error codes.

### NEW: USB Host Mode Features 🎉
- **Complete device enumeration** – Automatically enumerate USB devices with speed detection (LS/FS/HS)
- **HID keyboard support** – Poll USB keyboards and extract key reports
- **HID mouse support** – Poll USB mice and extract movement/button data
- **Automatic operation** – Self-configuring after enumeration completes
- **Status monitoring** – LED indicators and comprehensive status reporting
- **Python control interface** – Easy-to-use script for host mode control
- **Real-time events** – Monitor key presses and mouse movements with decoded reports

See `HDL/USB_HOST_QUICKSTART.md` for a quick start guide!

---

## Requirements

| Category | Items |
| -------- | ----- |
| **Hardware** | Cynthion board (r0.5+) |
| **FPGA toolchain** | [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build) (Yosys + nextpnr‑ecp5 + Trellis) |
| **Python** | Python 3 · `amaranth` · `luna` · `pyserial` |
| **Rust** | Stable toolchain (`rustup`, `cargo`) |
| **Debug Interface** | Built-in UART0→USB (no external adapter needed!) |

---

## Installation (Generic build)

### 1. Environment setup

You only need Docker for the initial build now. We provide a Makefile for convenience:

```bash
# Quick start - build everything
make build

# Or manually with Docker
docker build -t amaranth-cynthion .
```

See `make help` for all available commands.

### 2. Flash the FPGA gateware

#### Legacy Python/Luna Implementation
Python should be able to run this with `python legacy/src/flash_fpga.py`

#### Hurricane HDL Implementation
The HDL implementation provides dedicated flashing tools:
```bash
cd HDL/tools
./flash_cynthion.sh  # Flash the precompiled bitstream
```

For advanced builds and debugging:
```bash
# Compile a custom bitstream
./compile_bitstream.sh

# Validate HDL before building
./validate_hdl.sh

# Debug connected Cynthion
python cynthion_debugger.py
```

See `HDL/architecture.md` and `HDL/transparent_proxy_implementation.md` for detailed documentation on the HDL implementation.

### 4. Build the Rust CLI

The Rust CLI is now built automatically within Docker:

```bash
# Build everything (Docker image + extract binaries)
make build

# Or manually
docker build -t amaranth-cynthion .
./deploy.sh

# Run the CLI
make run-rust
# Or directly:
./build/binaries/hurricanefpga --help
```

The binary will be available at `build/binaries/hurricanefpga`.

> **Note:** Docker now builds **both** the PC CLI tool and the SAMD51 embedded firmware using ARM cross-compilation. Both binaries are extracted to the `build/` directory. See `docs/RUST_PROJECTS.md` for details on the two Rust projects.

---

## Hardware setup

| Connection | Details |
| ---------- | ------- |
| Host PC USB | → **TARGET (J2)** |
| USB device (keyboard, mouse, etc.) | → **CONTROL (J3)** or **TARGET B** |
| Debug/Control | → **CONTROL port** (USB, built-in UART0→USB CDC-ACM) |

> **Debug Interface**: Connect Cynthion's CONTROL port to your PC. It appears as `/dev/ttyACM0` (Linux) or a COM port (Windows) for real-time status and HID report monitoring. **No external UART adapter needed!**
>
> See `HDL/UART0_USB_INTEGRATION.md` for complete details.

---

## Usage

### Monitoring Debug Output (New!)

The FPGA now outputs real-time status via UART0→USB:

```bash
# Linux/macOS
picocom -b 115200 /dev/ttyACM0

# Or simply:
cat /dev/ttyACM0

# Windows (PowerShell)
# Check Device Manager for COM port, then:
mode COM3 BAUD=115200 PARITY=n DATA=8
type COM3
```

**Example Output:**
```
[STATUS] Proxy: ON, Host: ON, Enum: DONE
[HID-KBD] Mod: 0x00, Keys: [0x04, 0x00, 0x00]
[HID-MOUSE] Btn: 0x01, dX: 0x05, dY: 0xFD
[STATUS] Proxy: ON, Host: ON, Enum: DONE
```

See `HDL/UART0_USB_INTEGRATION.md` for detailed message formats.

### Running the Rust gateway

```bash
# list serial ports
target/release/packetry_injector --list

# start UDP→UART bridge
target/release/packetry_injector \
    --udp 127.0.0.1:9001 \
    --control-serial /dev/ttyUSB0  # or COM3 on Windows
```

### Command Acknowledgments

The FPGA now provides acknowledgments for each command sent:
- **ACK (0x06)** - Command was successfully received and processed
- **NAK (0x15) + Error Code** - Command failed with specific error code:
  - `0x01` - Value out of range
  - `0x02` - Syntax error
  - `0x03` - System busy
  - `0x04` - Buffer overflow

The Rust CLI automatically handles these acknowledgments.

### USB Host Mode (NEW!)

The HDL implementation now supports USB host functionality for enumerating and communicating with USB keyboards.

#### Quick Start

```bash
# Install Python dependencies
pip install pyusb

# Navigate to tools directory
cd HDL/tools

# Enable USB host mode
./usb_host_control.py --enable

# Connect USB keyboard to PHY2 port (J2 on Cynthion)
# OR connect USB mouse to PHY2 port

# Start enumeration
./usb_host_control.py --enumerate

# Monitor keyboard events in real-time
./usb_host_control.py --monitor  # Auto-detects keyboard or mouse
```

#### Example Output

**Keyboard**:
```
Detected keyboard, starting keyboard monitor...
Monitoring keyboard events... (Ctrl+C to stop)
[10:45:23] H
[10:45:24] E
[10:45:25] L
[10:45:26] L
[10:45:27] O
[10:45:28] LEFT_SHIFT + W
[10:45:29] O
[10:45:30] R
[10:45:31] L
[10:45:32] D
```

**Mouse**:
```
Detected mouse, starting mouse monitor...
Monitoring mouse events... (Ctrl+C to stop)
[10:50:15] Move(+10, +  5)
[10:50:16] LEFT
[10:50:17] Move( +3, +  2) LEFT
[10:50:18] Wheel( +1)
```

#### LED Status Indicators

| LED | Meaning | State |
|-----|---------|-------|
| LED7 | Host Mode Enabled | ON when host mode active |
| LED6 | Enumeration Complete | ON after successful enumeration |
| LED5 | Device Polling | ON when actively polling keyboard/mouse |
| LED4 | New Report | BLINKS when keys pressed or mouse moved |

#### Documentation

For complete USB host mode documentation, see:
- `HDL/USB_HOST_QUICKSTART.md` - Quick start and troubleshooting
- `HDL/USB_HOST_INTEGRATION.md` - Complete architecture and integration details
- `HDL/USB_HOST_COMPLETE.md` - Full feature summary

---

## Architecture

```text
                     ┌──────────────────┐  Serial  ┌────────────┐
                     │ Rust Gateway CLI │ ───────► │ UART Dongle│
                     │ packetry_injector│          │ (FT232)   │
                     └──────────────────┘          └─────┬──────┘
                                                         │
                                                         ▼
                      ┌────────────────────────────────────────┐
       ─────────────> │  Cynthion FPGA (ECP5)                  │
      |DEVICE|        │  • ULPI AUX  ↔ Host PC                 │
                      │  • ULPI HOST ↔ Target Device           │
                      │  • UART Rx/Tx ↔ PMOD A                 │
                      │  • Amaranth/LUNA passthrough/injector  │
                      └────────────────────────────────────────┘
                                                         |
                                                         |
                                                         ▼
                                                      HOST PC

```

---

## Development

```bash
# Rust
cargo build && cargo test

# Gateware (needs Python env)
python src/backend/top.py
```

### Coverage

```bash
cargo install cargo-tarpaulin
cargo tarpaulin --out Html --output-dir coverage \
                --packages packetry_injector
open coverage/tarpaulin-report.html
```

### Testing

Comprehensive test coverage across all layers:

```bash
# Run all tests
make test-local
# or
./run_tests.sh

# Run individual test suites
make test-rust      # Firmware unit tests (66 tests)
make test-python    # Python unit tests (59 tests)

# Test results
# ✅ Rust firmware: 66/66 passed
# ✅ Python tools:  59/59 passed
# ✅ Total:         125 tests
```

**Test Coverage:**
- **Firmware**: HID reports, recoil patterns, protocol parsing, state management
- **Python Tools**: Command generation, validation, descriptor parsing
- **HDL**: USB token generation, transaction engine, HID injector

See `TESTING.md` for complete testing documentation and `TEST_COVERAGE_SUMMARY.md` for detailed coverage metrics.

---

## Troubleshooting

<details>
<summary>USB device on J3 not detected by host</summary>

* Re‑flash correct bitstream & reset.
* Check cabling: Host ↔ J2, Device ↔ J3.
* Only FS/LS devices work.
* Ensure VBUS on J3 (jumper) or self‑powered device.
</details>


### udev rules (Linux)

```udev
# Cynthion DFU
SUBSYSTEM=="usb", ATTRS{idVendor}=="1d50", ATTRS{idProduct}=="615b", MODE="0666"
# CP210x example
SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", MODE="0666", GROUP="dialout"
# FT232 example
SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", MODE="0666", GROUP="dialout"
```

```bash
sudo udevadm control --reload-rules && sudo udevadm trigger
```

---

## License

Distributed under the terms of the **MIT License** – see `LICENSE`.

## Acknowledgements

* **Cynthion** by *Great Scott Gadgets*.
* Built with **Amaranth HDL**, **LUNA USB framework**, and a stack of fantastic Rust crates.
