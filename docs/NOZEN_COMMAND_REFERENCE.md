# Nozen Command Reference

## Overview

This document describes the "nozen" command protocol for HID mouse injection, matching the command format from the HurricaneMAKCM ESP32 project.

## Command Format

All commands are text-based, terminated with newline (`\n`):

```
nozen.command(arguments)\n
```

Commands are sent via USB CDC-ACM to the SAMD51, which translates them to binary frames for the FPGA.

## Mouse Movement Commands

### nozen.move(x,y)
**Move mouse relative to current position**

- `x`: X movement delta (-32768 to +32767 pixels)
- `y`: Y movement delta (-32768 to +32767 pixels)

**Examples:**
```python
nozen.move(10,-5)     # Move right 10, up 5
nozen.move(-20,15)    # Move left 20, down 15
nozen.move(0,0)       # No movement (valid but does nothing)
```

### nozen.moveto(x,y)
**Move mouse to absolute position**

- `x`: Absolute X coordinate (0-65535)
- `y`: Absolute Y coordinate (0-65535)

**Examples:**
```python
nozen.moveto(100,200)   # Move to screen position (100,200)
nozen.moveto(0,0)       # Move to top-left corner
nozen.moveto(1920,1080) # Move to specific position
```

**Note:** The SAMD51 tracks absolute position and converts to relative deltas for USB.

### nozen.getpos()
**Query current mouse position**

Returns the current tracked position in format: `km.pos(x,y)`

**Example:**
```python
>>> nozen.getpos()
km.pos(150,300)
```

## Mouse Button Commands

All button commands use format: `nozen.button(state)`
- `state`: `0` = release, `1` = press

### Left Button
```python
nozen.left(1)    # Press left button
nozen.left(0)    # Release left button
```

### Right Button
```python
nozen.right(1)   # Press right button
nozen.right(0)   # Release right button
```

### Middle Button
```python
nozen.middle(1)  # Press middle button (wheel click)
nozen.middle(0)  # Release middle button
```

### Side Buttons (Forward/Back)
```python
nozen.side1(1)   # Press side button 1 (forward)
nozen.side1(0)   # Release side button 1

nozen.side2(1)   # Press side button 2 (back)
nozen.side2(0)   # Release side button 2
```

**Button Mapping:**
- `nozen.left` → HID button bit 0 (0x01)
- `nozen.right` → HID button bit 1 (0x02)
- `nozen.middle` → HID button bit 2 (0x04)
- `nozen.side1` → HID button bit 3 (0x08)
- `nozen.side2` → HID button bit 4 (0x10)

## Mouse Wheel Commands

### nozen.wheel(amount)
**Scroll mouse wheel**

- `amount`: Scroll amount (-128 to +127), positive = scroll down, negative = scroll up

**Examples:**
```python
nozen.wheel(5)    # Scroll down 5 notches
nozen.wheel(-3)   # Scroll up 3 notches
```

## Recoil Pattern Commands

Recoil patterns are pre-programmed mouse movement sequences, useful for gaming applications (e.g., weapon recoil compensation).

### nozen.recoil.add(name){pattern}
**Add or update a recoil pattern**

- `name`: Pattern name (up to 32 characters)
- `pattern`: Comma-separated triplets of `x,y,delay` where:
  - `x`: X movement delta
  - `y`: Y movement delta  
  - `delay`: Delay in milliseconds

**Examples:**
```python
# Simple recoil pattern (3 steps)
nozen.recoil.add(ak47){2,-3,50,1,-2,50,0,-1,50}

# Complex pattern (6 steps)
nozen.recoil.add(m4a1){1,-2,40,1,-2,40,0,-1,40,0,-1,40,-1,0,40,-1,1,40}

# Single-step pattern
nozen.recoil.add(test){5,-5,100}
```

**Pattern Format:** Each triplet represents one recoil compensation step:
- Move mouse by (x,y) pixels
- Wait for delay milliseconds
- Repeat for next triplet

Maximum pattern size: 64 values (21 triplets max)

### nozen.recoil.delete(name)
**Delete a recoil pattern**

**Examples:**
```python
nozen.recoil.delete(ak47)
```

### nozen.recoil.list
**List all recoil patterns with full data**

Returns all stored patterns with their names and pattern data.

**Example:**
```python
>>> nozen.recoil.list
Stored patterns:
ak47: {2,-3,50,1,-2,50,0,-1,50}
m4a1: {1,-2,40,1,-2,40,0,-1,40,...}
```

### nozen.recoil.get(name)
**Get specific recoil pattern**

Returns the named pattern with full data.

**Example:**
```python
>>> nozen.recoil.get(ak47)
ak47: {2,-3,50,1,-2,50,0,-1,50}
```

### nozen.recoil.names
**List only pattern names**

Returns just the names of stored patterns, useful for quick reference.

**Example:**
```python
>>> nozen.recoil.names
Available patterns:
- ak47
- m4a1
- test
```

## Utility Commands

### nozen.print(message)
**Echo message back to serial**

Useful for debugging and testing communication.

**Examples:**
```python
nozen.print(Hello World)
nozen.print(Test 123)
```

### nozen.restart
**Restart the device**

Triggers a system reset of the SAMD51 microcontroller.

**Example:**
```python
>>> nozen.restart
Restarting...
```

## Mouse Wheel Commands (continued from above)

- `amount`: Wheel movement delta (-127 to +127)
  - Positive values = scroll down
  - Negative values = scroll up

**Examples:**
```python
nozen.wheel(5)     # Scroll down 5 notches
nozen.wheel(-3)    # Scroll up 3 notches
nozen.wheel(0)     # No wheel movement
```

## Python API

### Basic Usage

```python
import serial
import time

# Connect to Cynthion
ser = serial.Serial('/dev/ttyACM0', 115200)
time.sleep(0.5)

# Move mouse
ser.write(b'nozen.move(10,-5)\n')
time.sleep(0.01)

# Click left button
ser.write(b'nozen.left(1)\n')
time.sleep(0.05)
ser.write(b'nozen.left(0)\n')

# Scroll wheel
ser.write(b'nozen.wheel(5)\n')

ser.close()
```

### Using test_injection.py

The provided Python test script wraps these commands:

```bash
# Move mouse
python3 test_injection.py --move 10 -5

# Move to absolute position
python3 test_injection.py --moveto 100 200

# Click buttons
python3 test_injection.py --left-click
python3 test_injection.py --right-press
python3 test_injection.py --middle-release

# Scroll wheel
python3 test_injection.py --wheel 5

# Get position
python3 test_injection.py --getpos

# Monitor FPGA status
python3 test_injection.py --monitor
```

## Command Sequences

### Click and Drag
```python
ser.write(b'nozen.moveto(100,100)\n')  # Start position
time.sleep(0.01)
ser.write(b'nozen.left(1)\n')          # Press left button
time.sleep(0.01)

# Drag to new position
for i in range(10):
    ser.write(b'nozen.move(5,0)\n')    # Move right
    time.sleep(0.01)

ser.write(b'nozen.left(0)\n')          # Release left button
```

### Double Click
```python
def double_click():
    ser.write(b'nozen.left(1)\n')
    time.sleep(0.05)
    ser.write(b'nozen.left(0)\n')
    time.sleep(0.05)
    ser.write(b'nozen.left(1)\n')
    time.sleep(0.05)
    ser.write(b'nozen.left(0)\n')
```

### Smooth Movement
```python
# Move in a circle (8 steps)
import math

for angle in range(0, 360, 45):
    rad = math.radians(angle)
    x = int(10 * math.cos(rad))
    y = int(10 * math.sin(rad))
    ser.write(f'nozen.move({x},{y})\n'.encode())
    time.sleep(0.01)
```

## HID Report Format

### Mouse Report (5 bytes)

The FPGA translates nozen commands to standard USB HID mouse reports:

```
Byte 0: Button state (bitmask)
        Bit 0: Left button
        Bit 1: Right button
        Bit 2: Middle button
        Bit 3: Side button 1 (forward)
        Bit 4: Side button 2 (back)
        Bit 5-7: Reserved

Byte 1: X movement (signed 8-bit, -127 to +127)
Byte 2: Y movement (signed 8-bit, -127 to +127)
Byte 3: Wheel movement (signed 8-bit, -127 to +127)
Byte 4: Horizontal pan (usually 0)
```

## Internal Protocol

Commands flow through the system:

```
Python Script
    ↓ (nozen commands via USB CDC-ACM)
SAMD51 Firmware
    ↓ (binary frames via UART0)
FPGA Command Processor
    ↓ (injection signals)
USB Injection Mux
    ↓ (merged HID reports)
Target USB Device
```

### SAMD51 → FPGA Frame Format

The SAMD51 converts nozen commands to binary frames:

```
[CMD:XX] [LEN:YYYY] [PAYLOAD] [CKSUM:ZZ]\n

CMD:11 = INJECT_MOUSE (5 bytes payload)
CMD:12 = MOVETO (4 bytes: x_lo, x_hi, y_lo, y_hi)
```

**Example:**
```
nozen.move(10,-5)
↓
[CMD:11] [LEN:0005] \x00\x0A\xFB\x00\x00 [CKSUM:XX]\n
         buttons=0, dx=10, dy=-5 (0xFB), wheel=0, pan=0
```

## Timing Considerations

- **Minimum delay between commands**: 10ms recommended
- **Button hold duration**: 50ms minimum for reliable clicks
- **Movement updates**: Can send up to 100 updates/second
- **USB polling interval**: 
  - Keyboard: 10ms (100 reports/sec max)
  - Mouse: 8ms (125 reports/sec max)
  - High-speed mouse: 1ms (1000 reports/sec)

## Troubleshooting

### Commands Not Working

1. **Check connection:**
   ```bash
   ls /dev/ttyACM*  # Should show /dev/ttyACM0
   ```

2. **Verify baud rate:**
   ```python
   ser = serial.Serial('/dev/ttyACM0', 115200)  # Must be 115200
   ```

3. **Check command format:**
   ```python
   # Correct:
   ser.write(b'nozen.move(10,-5)\n')
   
   # Wrong (missing newline):
   ser.write(b'nozen.move(10,-5)')
   
   # Wrong (wrong format):
   ser.write(b'nozen.move 10 -5\n')
   ```

### Movement Not Accurate

- For large movements, break into smaller steps:
  ```python
  # Bad: May be clamped to ±127
  ser.write(b'nozen.move(500,0)\n')
  
  # Good: Multiple small moves
  for i in range(5):
      ser.write(b'nozen.move(100,0)\n')
      time.sleep(0.01)
  ```

### Buttons Stuck

- Always pair press with release:
  ```python
  ser.write(b'nozen.left(1)\n')
  time.sleep(0.05)
  ser.write(b'nozen.left(0)\n')  # Don't forget!
  ```

- Send explicit release if unsure:
  ```python
  # Release all buttons
  ser.write(b'nozen.left(0)\n')
  ser.write(b'nozen.right(0)\n')
  ser.write(b'nozen.middle(0)\n')
  ser.write(b'nozen.side1(0)\n')
  ser.write(b'nozen.side2(0)\n')
  ```

## Compatibility

**Matches Command Format:**
- HurricaneMAKCM ESP32 project
- Standard nozen protocol

**Supported Platforms:**
- Linux (tested)
- macOS (tested)
- Windows 10+ (should work)

**Requirements:**
- Python 3.6+
- pyserial library
- Cynthion with SAMD51 firmware flashed
