# HurricaneFPGA Test Suite

This document describes the comprehensive test coverage for the HurricaneFPGA project.

## Overview

The project now includes extensive test coverage across multiple layers:

- **Firmware Tests (Rust)**: Unit tests for embedded firmware components
- **Python Tests**: Unit tests for command-line tools and utilities
- **HDL Tests (Verilog)**: Testbenches for hardware modules

## Running Tests

### All Tests
```bash
make test-local
# or
./run_tests.sh
```

### Individual Test Suites

#### Rust Firmware Tests
```bash
make test-rust
# or
cd firmware/samd51_hid_injector && cargo test
```

#### Python Unit Tests
```bash
make test-python
# or
python3 tools/test_descriptor_unit.py
python3 tools/test_injection_unit.py
```

#### HDL Tests
```bash
cd HDL/hardware/testbenches
make
```

## Test Coverage

### Firmware Tests (firmware/samd51_hid_injector/)

#### HID Module (`src/hid.rs`)
- ✅ Keyboard report generation (empty, single key, with modifiers)
- ✅ Mouse report generation (empty, clicks, movement)
- ✅ HID scancode constants validation
- ✅ Modifier key bitmasks
- ✅ Report serialization to bytes
- ✅ Extreme value handling

**Test Count**: 14 tests

#### Recoil Pattern Management (`src/recoil.rs`)
- ✅ Pattern creation and storage
- ✅ Pattern validation (triplet format, length limits)
- ✅ Pattern retrieval by name
- ✅ Pattern deletion
- ✅ Pattern listing
- ✅ Pattern updates
- ✅ Command parsing (add, delete, get)
- ✅ Integer parsing with negative values
- ✅ Maximum capacity handling

**Test Count**: 18 tests

#### Mouse State Tracking (`src/state.rs`)
- ✅ Initial state
- ✅ Relative movement updates
- ✅ Absolute positioning
- ✅ Delta calculations
- ✅ Saturation handling (i16 limits)
- ✅ Movement sequences
- ✅ Extreme position handling

**Test Count**: 11 tests

#### Protocol Parser (`src/protocol.rs`)
- ✅ Mouse move commands (relative, absolute)
- ✅ Button commands (left, right, middle, side buttons)
- ✅ Wheel scroll commands
- ✅ Position query commands
- ✅ Restart command
- ✅ Multi-line parsing
- ✅ Partial command buffering
- ✅ Utility function tests (hex conversion, parsing)
- ✅ UART frame generation
- ✅ Invalid command handling

**Test Count**: 25 tests

#### Descriptor Cache (`src/descriptor_cache.rs`)
- ✅ Cache operations (add, get, eviction)
- ✅ Device type detection
- ✅ Statistics tracking

**Test Count**: 2 tests (existing)

**Total Firmware Tests**: 70 tests

### Python Unit Tests (tools/)

#### Descriptor Unit Tests (`test_descriptor_unit.py`)
- ✅ HID descriptor structure validation
- ✅ Mouse descriptor parsing
- ✅ Keyboard descriptor parsing
- ✅ Collection nesting
- ✅ Usage page values
- ✅ Command formatting
- ✅ Scancode mappings
- ✅ Modifier key combinations
- ✅ Recoil pattern formatting
- ✅ Mouse state tracking logic

**Test Count**: 32 tests (6 test classes)

#### Injection Unit Tests (`test_injection_unit.py`)
- ✅ Mouse command generation (move, moveto, click, wheel)
- ✅ Keyboard command generation
- ✅ Recoil pattern commands
- ✅ Command sequences (click, drag, double-click)
- ✅ Command validation (ranges, formats)
- ✅ Pattern validation (triplets, limits)
- ✅ Utility commands (getpos, restart, stats)
- ✅ Response parsing

**Test Count**: 43 tests (8 test classes)

**Total Python Tests**: 75 tests

### HDL Testbenches (HDL/hardware/testbenches/)

#### USB Token Generator (`tb_usb_token_generator.v`)
- ✅ SETUP token generation
- ✅ IN token generation
- ✅ OUT token generation
- ✅ SOF token generation
- ✅ CRC5 calculation
- ✅ Token timing

#### USB Transaction Engine (`tb_usb_transaction_engine.v`)
- ✅ Transaction sequencing
- ✅ Data packet handling
- ✅ Handshake protocol

#### USB HID Injector (`tb_usb_hid_injector.v`) - NEW
- ✅ Mouse relative movement
- ✅ Mouse button clicks
- ✅ Mouse absolute positioning
- ✅ Mouse wheel scrolling
- ✅ Button combinations
- ✅ Command parsing edge cases
- ✅ Invalid command handling
- ✅ Rapid command sequences

**Total HDL Tests**: 8 comprehensive testbenches

## Test Organization

```
HurricaneFPGA/
├── firmware/samd51_hid_injector/
│   └── src/
│       ├── hid.rs              (14 tests)
│       ├── recoil.rs           (18 tests)
│       ├── state.rs            (11 tests)
│       ├── protocol.rs         (25 tests)
│       └── descriptor_cache.rs  (2 tests)
├── tools/
│   ├── test_descriptor_unit.py  (32 tests)
│   └── test_injection_unit.py   (43 tests)
├── HDL/hardware/testbenches/
│   ├── tb_usb_token_generator.v
│   ├── tb_usb_transaction_engine.v
│   └── tb_usb_hid_injector.v     (NEW)
├── run_tests.sh                  (Test runner)
└── Makefile                      (Test targets)
```

## Test Coverage Summary

| Component | Tests | Coverage |
|-----------|-------|----------|
| Rust Firmware | 70 | High - All core modules |
| Python Tools | 75 | High - Command generation & validation |
| HDL Testbenches | 8 | Medium - Core USB functions |
| **Total** | **153** | **Comprehensive** |

## Test Categories

### Unit Tests
- Individual function testing
- Edge case validation
- Error handling
- Data structure operations

### Integration Tests
- Command parsing end-to-end
- State management across operations
- Multi-step sequences

### Hardware Tests
- Protocol timing
- Transaction sequences
- Signal integrity
- Corner cases

## Continuous Integration

Tests can be integrated into CI/CD pipelines:

```bash
# Quick test (local)
make test-local

# Full test (with Docker)
make test

# With coverage report
make test-coverage
```

## Adding New Tests

### Rust Tests
Add tests to the relevant module with `#[cfg(test)]`:
```rust
#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_my_function() {
        assert_eq!(my_function(), expected_value);
    }
}
```

### Python Tests
Add test classes to the test files:
```python
class TestNewFeature(unittest.TestCase):
    def test_something(self):
        self.assertEqual(actual, expected)
```

### HDL Tests
Create new testbench files following the naming convention `tb_*.v`

## Test Quality Guidelines

1. **Completeness**: Test all code paths, including error conditions
2. **Independence**: Tests should not depend on each other
3. **Clarity**: Test names should clearly describe what is being tested
4. **Speed**: Tests should run quickly for rapid iteration
5. **Stability**: Tests should be deterministic and not flaky

## Future Improvements

- [ ] Add performance benchmarks
- [ ] Increase HDL coverage (aim for 100%)
- [ ] Add end-to-end hardware-in-the-loop tests
- [ ] Add fuzzing tests for protocol parser
- [ ] Measure and improve code coverage metrics
- [ ] Add continuous integration workflows

## Resources

- [Rust Testing Guide](https://doc.rust-lang.org/book/ch11-00-testing.html)
- [Python unittest Documentation](https://docs.python.org/3/library/unittest.html)
- [Verilog Testbench Guide](https://www.asic-world.com/verilog/art_testbench_writing_good.html)
