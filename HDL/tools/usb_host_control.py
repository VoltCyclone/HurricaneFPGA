#!/usr/bin/env python3
"""
USB Host Mode Control Script for HurricaneFPGA

This script provides a command-line interface to control the USB host mode
functionality of the HurricaneFPGA Cynthion device.

Usage:
    python3 usb_host_control.py --enable       # Enable host mode
    python3 usb_host_control.py --enumerate    # Start enumeration
    python3 usb_host_control.py --status       # Get status
    python3 usb_host_control.py --monitor      # Monitor keyboard events
"""

import argparse
import sys
import time
from typing import Optional

try:
    import usb.core
    import usb.util
except ImportError:
    print("Error: pyusb not installed. Install with: pip install pyusb")
    sys.exit(1)


class CynthionUSBHost:
    """Control interface for Cynthion USB Host functionality."""
    
    # USB VID/PID for Cynthion
    VENDOR_ID = 0x1d50    # OpenMoko vendor ID
    PRODUCT_ID = 0x615b   # Cynthion product ID
    
    # Control register addresses (these would map to actual hardware registers)
    REG_HOST_MODE_ENABLE = 0x00
    REG_ENUM_START = 0x01
    REG_ENUM_DONE = 0x02
    REG_ENUM_ERROR = 0x03
    REG_ENUM_ERROR_CODE = 0x04
    REG_VENDOR_ID_LO = 0x10
    REG_VENDOR_ID_HI = 0x11
    REG_PRODUCT_ID_LO = 0x12
    REG_PRODUCT_ID_HI = 0x13
    REG_KBD_ACTIVE = 0x20
    REG_KBD_REPORT_BASE = 0x30  # 8 bytes from 0x30-0x37
    REG_MOUSE_ACTIVE = 0x40
    REG_MOUSE_REPORT_BASE = 0x50  # 5 bytes from 0x50-0x54
    REG_MOUSE_BUTTONS = 0x50
    REG_MOUSE_DELTA_X = 0x51
    REG_MOUSE_DELTA_Y = 0x52
    REG_MOUSE_WHEEL = 0x53
    
    def __init__(self):
        """Initialize connection to Cynthion device."""
        self.device = None
        self.connect()
    
    def connect(self) -> bool:
        """Find and connect to Cynthion device."""
        self.device = usb.core.find(idVendor=self.VENDOR_ID, idProduct=self.PRODUCT_ID)
        
        if self.device is None:
            print("Error: Cynthion device not found")
            print(f"Looking for VID:PID = {self.VENDOR_ID:04x}:{self.PRODUCT_ID:04x}")
            return False
        
        try:
            # Detach kernel driver if necessary
            if self.device.is_kernel_driver_active(0):
                self.device.detach_kernel_driver(0)
            
            # Set configuration
            self.device.set_configuration()
            print(f"Connected to Cynthion device")
            return True
            
        except usb.core.USBError as e:
            print(f"Error connecting to device: {e}")
            return False
    
    def write_register(self, reg_addr: int, value: int) -> bool:
        """Write a value to a control register."""
        try:
            # USB control transfer to write register
            # bmRequestType: 0x40 = Host-to-device, vendor, device
            # bRequest: 0x01 = Write register
            # wValue: register address
            # wIndex: 0
            # data: register value
            self.device.ctrl_transfer(
                bmRequestType=0x40,
                bRequest=0x01,
                wValue=reg_addr,
                wIndex=0,
                data_or_wLength=[value]
            )
            return True
        except usb.core.USBError as e:
            print(f"Error writing register 0x{reg_addr:02x}: {e}")
            return False
    
    def read_register(self, reg_addr: int) -> Optional[int]:
        """Read a value from a control register."""
        try:
            # USB control transfer to read register
            # bmRequestType: 0xC0 = Device-to-host, vendor, device
            # bRequest: 0x02 = Read register
            # wValue: register address
            # wIndex: 0
            # data_or_wLength: number of bytes to read
            data = self.device.ctrl_transfer(
                bmRequestType=0xC0,
                bRequest=0x02,
                wValue=reg_addr,
                wIndex=0,
                data_or_wLength=1
            )
            return data[0]
        except usb.core.USBError as e:
            print(f"Error reading register 0x{reg_addr:02x}: {e}")
            return None
    
    def enable_host_mode(self) -> bool:
        """Enable USB host mode."""
        print("Enabling USB host mode...")
        return self.write_register(self.REG_HOST_MODE_ENABLE, 1)
    
    def disable_host_mode(self) -> bool:
        """Disable USB host mode."""
        print("Disabling USB host mode...")
        return self.write_register(self.REG_HOST_MODE_ENABLE, 0)
    
    def start_enumeration(self) -> bool:
        """Start USB device enumeration."""
        print("Starting USB enumeration...")
        # Pulse the enumeration start register
        if not self.write_register(self.REG_ENUM_START, 1):
            return False
        time.sleep(0.01)  # Short delay
        return self.write_register(self.REG_ENUM_START, 0)
    
    def check_enumeration_status(self) -> dict:
        """Check enumeration status and return device info."""
        status = {
            'done': False,
            'error': False,
            'error_code': 0,
            'vendor_id': 0,
            'product_id': 0,
            'keyboard_active': False,
            'mouse_active': False
        }
        
        # Read enumeration done flag
        done = self.read_register(self.REG_ENUM_DONE)
        if done is not None:
            status['done'] = (done != 0)
        
        # Read error flag
        error = self.read_register(self.REG_ENUM_ERROR)
        if error is not None:
            status['error'] = (error != 0)
        
        # Read error code
        error_code = self.read_register(self.REG_ENUM_ERROR_CODE)
        if error_code is not None:
            status['error_code'] = error_code
        
        # Read VID/PID if enumeration succeeded
        if status['done'] and not status['error']:
            vid_lo = self.read_register(self.REG_VENDOR_ID_LO)
            vid_hi = self.read_register(self.REG_VENDOR_ID_HI)
            pid_lo = self.read_register(self.REG_PRODUCT_ID_LO)
            pid_hi = self.read_register(self.REG_PRODUCT_ID_HI)
            
            if all(x is not None for x in [vid_lo, vid_hi, pid_lo, pid_hi]):
                status['vendor_id'] = (vid_hi << 8) | vid_lo
                status['product_id'] = (pid_hi << 8) | pid_lo
        
        # Read keyboard active status
        kbd_active = self.read_register(self.REG_KBD_ACTIVE)
        if kbd_active is not None:
            status['keyboard_active'] = (kbd_active != 0)
        
        # Read mouse active status
        mouse_active = self.read_register(self.REG_MOUSE_ACTIVE)
        if mouse_active is not None:
            status['mouse_active'] = (mouse_active != 0)
        
        return status
    
    def read_keyboard_report(self) -> Optional[bytes]:
        """Read the latest keyboard report (8 bytes)."""
        report = []
        for i in range(8):
            value = self.read_register(self.REG_KBD_REPORT_BASE + i)
            if value is None:
                return None
            report.append(value)
        return bytes(report)
    
    def read_mouse_report(self) -> Optional[dict]:
        """Read the latest mouse report."""
        buttons = self.read_register(self.REG_MOUSE_BUTTONS)
        delta_x_raw = self.read_register(self.REG_MOUSE_DELTA_X)
        delta_y_raw = self.read_register(self.REG_MOUSE_DELTA_Y)
        wheel_raw = self.read_register(self.REG_MOUSE_WHEEL)
        
        if any(x is None for x in [buttons, delta_x_raw, delta_y_raw, wheel_raw]):
            return None
        
        # Convert to signed values
        delta_x = delta_x_raw if delta_x_raw < 128 else delta_x_raw - 256
        delta_y = delta_y_raw if delta_y_raw < 128 else delta_y_raw - 256
        wheel = wheel_raw if wheel_raw < 128 else wheel_raw - 256
        
        return {
            'buttons': buttons,
            'delta_x': delta_x,
            'delta_y': delta_y,
            'wheel': wheel,
            'left_button': bool(buttons & 0x01),
            'right_button': bool(buttons & 0x02),
            'middle_button': bool(buttons & 0x04)
        }
    
    def decode_keyboard_report(self, report: bytes) -> dict:
        """Decode a USB HID keyboard report."""
        if len(report) != 8:
            return {}
        
        modifier_names = {
            0x01: "LEFT_CTRL",
            0x02: "LEFT_SHIFT",
            0x04: "LEFT_ALT",
            0x08: "LEFT_GUI",
            0x10: "RIGHT_CTRL",
            0x20: "RIGHT_SHIFT",
            0x40: "RIGHT_ALT",
            0x80: "RIGHT_GUI"
        }
        
        # HID Usage Table keycodes (simplified)
        keycode_names = {
            0x04: "A", 0x05: "B", 0x06: "C", 0x07: "D", 0x08: "E", 0x09: "F",
            0x0A: "G", 0x0B: "H", 0x0C: "I", 0x0D: "J", 0x0E: "K", 0x0F: "L",
            0x10: "M", 0x11: "N", 0x12: "O", 0x13: "P", 0x14: "Q", 0x15: "R",
            0x16: "S", 0x17: "T", 0x18: "U", 0x19: "V", 0x1A: "W", 0x1B: "X",
            0x1C: "Y", 0x1D: "Z",
            0x1E: "1", 0x1F: "2", 0x20: "3", 0x21: "4", 0x22: "5",
            0x23: "6", 0x24: "7", 0x25: "8", 0x26: "9", 0x27: "0",
            0x28: "ENTER", 0x29: "ESC", 0x2A: "BACKSPACE", 0x2B: "TAB",
            0x2C: "SPACE", 0x39: "CAPS_LOCK"
        }
        
        modifiers = []
        for bit, name in modifier_names.items():
            if report[0] & bit:
                modifiers.append(name)
        
        keys = []
        for i in range(2, 8):  # Bytes 2-7 contain keycodes
            if report[i] != 0:
                key_name = keycode_names.get(report[i], f"KEY_{report[i]:02x}")
                keys.append(key_name)
        
        return {
            'modifiers': modifiers,
            'keys': keys,
            'raw': report.hex()
        }
    
    def print_status(self):
        """Print current USB host status."""
        status = self.check_enumeration_status()
        
        print("\n=== USB Host Status ===")
        print(f"Enumeration Done: {status['done']}")
        print(f"Enumeration Error: {status['error']}")
        
        if status['error']:
            print(f"Error Code: 0x{status['error_code']:02x}")
        
        if status['done'] and not status['error']:
            print(f"Device VID:PID = {status['vendor_id']:04x}:{status['product_id']:04x}")
            print(f"Keyboard Active: {status['keyboard_active']}")
            print(f"Mouse Active: {status['mouse_active']}")
        
        print("=" * 25 + "\n")
    
    def monitor_keyboard(self, duration: Optional[int] = None):
        """Monitor keyboard events."""
        print("Monitoring keyboard events... (Ctrl+C to stop)")
        print("Waiting for key presses...\n")
        
        start_time = time.time()
        last_report = None
        
        try:
            while True:
                # Check duration limit
                if duration and (time.time() - start_time) > duration:
                    break
                
                # Read keyboard report
                report = self.read_keyboard_report()
                if report is None:
                    time.sleep(0.01)
                    continue
                
                # Check if report changed (key press/release)
                if report != last_report:
                    decoded = self.decode_keyboard_report(report)
                    
                    # Print key events
                    if decoded['modifiers'] or decoded['keys']:
                        mods_str = "+".join(decoded['modifiers']) if decoded['modifiers'] else ""
                        keys_str = " ".join(decoded['keys']) if decoded['keys'] else ""
                        
                        if mods_str and keys_str:
                            print(f"[{time.strftime('%H:%M:%S')}] {mods_str} + {keys_str}")
                        elif mods_str:
                            print(f"[{time.strftime('%H:%M:%S')}] {mods_str}")
                        elif keys_str:
                            print(f"[{time.strftime('%H:%M:%S')}] {keys_str}")
                    else:
                        # All keys released
                        if last_report and (last_report[0] != 0 or any(last_report[2:8])):
                            print(f"[{time.strftime('%H:%M:%S')}] (released)")
                    
                    last_report = report
                
                time.sleep(0.01)  # 100Hz polling
                
        except KeyboardInterrupt:
            print("\n\nStopped monitoring.")
    
    def monitor_mouse(self, duration: Optional[int] = None):
        """Monitor mouse events."""
        print("Monitoring mouse events... (Ctrl+C to stop)")
        print("Waiting for mouse movement...\n")
        
        start_time = time.time()
        last_report = None
        
        try:
            while True:
                # Check duration limit
                if duration and (time.time() - start_time) > duration:
                    break
                
                # Read mouse report
                report = self.read_mouse_report()
                if report is None:
                    time.sleep(0.01)
                    continue
                
                # Check if report changed
                report_tuple = (report['buttons'], report['delta_x'], report['delta_y'], report['wheel'])
                if report_tuple != last_report:
                    # Build status string
                    parts = []
                    
                    # Buttons
                    if report['left_button']:
                        parts.append("LEFT")
                    if report['right_button']:
                        parts.append("RIGHT")
                    if report['middle_button']:
                        parts.append("MIDDLE")
                    
                    # Movement
                    if report['delta_x'] != 0 or report['delta_y'] != 0:
                        parts.append(f"Move({report['delta_x']:+3d}, {report['delta_y']:+3d})")
                    
                    # Wheel
                    if report['wheel'] != 0:
                        parts.append(f"Wheel({report['wheel']:+3d})")
                    
                    if parts:
                        print(f"[{time.strftime('%H:%M:%S')}] {' '.join(parts)}")
                    
                    last_report = report_tuple
                
                time.sleep(0.01)  # 100Hz polling
                
        except KeyboardInterrupt:
            print("\n\nStopped monitoring.")


def main():
    parser = argparse.ArgumentParser(
        description="Control HurricaneFPGA USB Host Mode",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    parser.add_argument('--enable', action='store_true',
                       help='Enable USB host mode')
    parser.add_argument('--disable', action='store_true',
                       help='Disable USB host mode')
    parser.add_argument('--enumerate', action='store_true',
                       help='Start device enumeration')
    parser.add_argument('--status', action='store_true',
                       help='Get current status')
    parser.add_argument('--monitor', action='store_true',
                       help='Monitor keyboard events (Ctrl+C to stop)')
    parser.add_argument('--duration', type=int, metavar='SECONDS',
                       help='Monitor duration in seconds (default: infinite)')
    
    args = parser.parse_args()
    
    # Check if any action specified
    if not any([args.enable, args.disable, args.enumerate, args.status, args.monitor]):
        parser.print_help()
        sys.exit(1)
    
    # Create controller instance
    try:
        controller = CynthionUSBHost()
    except Exception as e:
        print(f"Failed to initialize controller: {e}")
        sys.exit(1)
    
    # Execute requested actions
    if args.enable:
        controller.enable_host_mode()
        time.sleep(0.1)
    
    if args.disable:
        controller.disable_host_mode()
        time.sleep(0.1)
    
    if args.enumerate:
        controller.start_enumeration()
        print("Waiting for enumeration to complete...")
        
        # Wait up to 5 seconds for enumeration
        for _ in range(50):
            time.sleep(0.1)
            status = controller.check_enumeration_status()
            if status['done']:
                print("✓ Enumeration complete!")
                if status['vendor_id'] and status['product_id']:
                    print(f"  Device: {status['vendor_id']:04x}:{status['product_id']:04x}")
                break
            if status['error']:
                print(f"✗ Enumeration failed with error code 0x{status['error_code']:02x}")
                break
        else:
            print("⚠ Enumeration timeout (device not responding?)")
    
    if args.status:
        controller.print_status()
    
    if args.monitor:
        # Auto-detect device type
        status = controller.check_enumeration_status()
        if status['keyboard_active']:
            print("Detected keyboard, starting keyboard monitor...")
            controller.monitor_keyboard(args.duration)
        elif status['mouse_active']:
            print("Detected mouse, starting mouse monitor...")
            controller.monitor_mouse(args.duration)
        else:
            print("No HID device detected. Please enumerate a device first.")


if __name__ == '__main__':
    main()
