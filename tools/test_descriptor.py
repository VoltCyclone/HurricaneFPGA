#!/usr/bin/env python3
"""
HID Descriptor Test Tool
Tests the SAMD51 descriptor parsing functionality
"""

import serial
import time
import argparse
import sys

# Example HID descriptors for testing

MOUSE_DESCRIPTOR = [
    0x05, 0x01,        # Usage Page (Generic Desktop)
    0x09, 0x02,        # Usage (Mouse)
    0xA1, 0x01,        # Collection (Application)
    0x09, 0x01,        #   Usage (Pointer)
    0xA1, 0x00,        #   Collection (Physical)
    0x05, 0x09,        #     Usage Page (Button)
    0x19, 0x01,        #     Usage Minimum (Button 1)
    0x29, 0x05,        #     Usage Maximum (Button 5)
    0x15, 0x00,        #     Logical Minimum (0)
    0x25, 0x01,        #     Logical Maximum (1)
    0x95, 0x05,        #     Report Count (5)
    0x75, 0x01,        #     Report Size (1)
    0x81, 0x02,        #     Input (Data, Variable, Absolute)
    0x95, 0x01,        #     Report Count (1)
    0x75, 0x03,        #     Report Size (3)
    0x81, 0x03,        #     Input (Constant) - padding
    0x05, 0x01,        #     Usage Page (Generic Desktop)
    0x09, 0x30,        #     Usage (X)
    0x09, 0x31,        #     Usage (Y)
    0x09, 0x38,        #     Usage (Wheel)
    0x15, 0x81,        #     Logical Minimum (-127)
    0x25, 0x7F,        #     Logical Maximum (127)
    0x75, 0x08,        #     Report Size (8)
    0x95, 0x03,        #     Report Count (3)
    0x81, 0x06,        #     Input (Data, Variable, Relative)
    0xC0,              #   End Collection
    0xC0,              # End Collection
]

KEYBOARD_DESCRIPTOR = [
    0x05, 0x01,        # Usage Page (Generic Desktop)
    0x09, 0x06,        # Usage (Keyboard)
    0xA1, 0x01,        # Collection (Application)
    0x05, 0x07,        #   Usage Page (Keyboard)
    0x19, 0xE0,        #   Usage Minimum (Left Control)
    0x29, 0xE7,        #   Usage Maximum (Right GUI)
    0x15, 0x00,        #   Logical Minimum (0)
    0x25, 0x01,        #   Logical Maximum (1)
    0x75, 0x01,        #   Report Size (1)
    0x95, 0x08,        #   Report Count (8)
    0x81, 0x02,        #   Input (Data, Variable, Absolute) - Modifier byte
    0x95, 0x01,        #   Report Count (1)
    0x75, 0x08,        #   Report Size (8)
    0x81, 0x01,        #   Input (Constant) - Reserved byte
    0x95, 0x05,        #   Report Count (5)
    0x75, 0x01,        #   Report Size (1)
    0x05, 0x08,        #   Usage Page (LEDs)
    0x19, 0x01,        #   Usage Minimum (Num Lock)
    0x29, 0x05,        #   Usage Maximum (Kana)
    0x91, 0x02,        #   Output (Data, Variable, Absolute) - LED report
    0x95, 0x01,        #   Report Count (1)
    0x75, 0x03,        #   Report Size (3)
    0x91, 0x01,        #   Output (Constant) - LED padding
    0x95, 0x06,        #   Report Count (6)
    0x75, 0x08,        #   Report Size (8)
    0x15, 0x00,        #   Logical Minimum (0)
    0x25, 0x65,        #   Logical Maximum (101)
    0x05, 0x07,        #   Usage Page (Keyboard)
    0x19, 0x00,        #   Usage Minimum (0)
    0x29, 0x65,        #   Usage Maximum (101)
    0x81, 0x00,        #   Input (Data, Array) - Key array
    0xC0,              # End Collection
]

GAMEPAD_DESCRIPTOR = [
    0x05, 0x01,        # Usage Page (Generic Desktop)
    0x09, 0x05,        # Usage (Game Pad)
    0xA1, 0x01,        # Collection (Application)
    0x05, 0x09,        #   Usage Page (Button)
    0x19, 0x01,        #   Usage Minimum (Button 1)
    0x29, 0x10,        #   Usage Maximum (Button 16)
    0x15, 0x00,        #   Logical Minimum (0)
    0x25, 0x01,        #   Logical Maximum (1)
    0x75, 0x01,        #   Report Size (1)
    0x95, 0x10,        #   Report Count (16)
    0x81, 0x02,        #   Input (Data, Variable, Absolute)
    0x05, 0x01,        #   Usage Page (Generic Desktop)
    0x09, 0x30,        #   Usage (X)
    0x09, 0x31,        #   Usage (Y)
    0x09, 0x32,        #   Usage (Z)
    0x09, 0x35,        #   Usage (Rz)
    0x15, 0x00,        #   Logical Minimum (0)
    0x26, 0xFF, 0x00,  #   Logical Maximum (255)
    0x75, 0x08,        #   Report Size (8)
    0x95, 0x04,        #   Report Count (4)
    0x81, 0x02,        #   Input (Data, Variable, Absolute)
    0xC0,              # End Collection
]

class DescriptorTester:
    def __init__(self, port='/dev/ttyACM0', baudrate=115200):
        self.ser = serial.Serial(port, baudrate, timeout=1)
        time.sleep(0.5)  # Wait for device to be ready
        
    def send_command(self, cmd):
        """Send a command and wait for response"""
        self.ser.write(cmd.encode() + b'\n')
        time.sleep(0.1)
        
        # Read response
        response = b''
        while self.ser.in_waiting:
            response += self.ser.read(self.ser.in_waiting)
            time.sleep(0.05)
        
        return response.decode('utf-8', errors='ignore')
    
    def add_descriptor(self, device_addr, interface, descriptor_bytes):
        """Add a descriptor to the cache"""
        # Convert bytes to hex string
        hex_str = ','.join(f'{b:02x}' for b in descriptor_bytes)
        
        cmd = f"nozen.descriptor.add({device_addr},{interface}){{{hex_str}}}"
        print(f"Adding descriptor: addr={device_addr} iface={interface} size={len(descriptor_bytes)} bytes")
        
        response = self.send_command(cmd)
        print(f"Response: {response}")
        
        return response
    
    def get_descriptor(self, device_addr, interface):
        """Get descriptor info from cache"""
        cmd = f"nozen.descriptor.get({device_addr},{interface})"
        print(f"\nQuerying descriptor: addr={device_addr} iface={interface}")
        
        response = self.send_command(cmd)
        print(f"Response:\n{response}")
        
        return response
    
    def get_stats(self):
        """Get cache statistics"""
        cmd = "nozen.descriptor.stats"
        print("\nGetting cache statistics...")
        
        response = self.send_command(cmd)
        print(f"Stats: {response}")
        
        return response
    
    def test_mouse(self):
        """Test mouse descriptor parsing"""
        print("\n=== Testing Mouse Descriptor ===")
        self.add_descriptor(1, 0, MOUSE_DESCRIPTOR)
        self.get_descriptor(1, 0)
    
    def test_keyboard(self):
        """Test keyboard descriptor parsing"""
        print("\n=== Testing Keyboard Descriptor ===")
        self.add_descriptor(2, 0, KEYBOARD_DESCRIPTOR)
        self.get_descriptor(2, 0)
    
    def test_gamepad(self):
        """Test gamepad descriptor parsing"""
        print("\n=== Testing Gamepad Descriptor ===")
        self.add_descriptor(3, 0, GAMEPAD_DESCRIPTOR)
        self.get_descriptor(3, 0)
    
    def test_all(self):
        """Run all tests"""
        self.test_mouse()
        self.test_keyboard()
        self.test_gamepad()
        self.get_stats()
    
    def close(self):
        """Close serial connection"""
        self.ser.close()

def main():
    parser = argparse.ArgumentParser(description='HID Descriptor Parser Test Tool')
    parser.add_argument('--port', default='/dev/ttyACM0', help='Serial port (default: /dev/ttyACM0)')
    parser.add_argument('--baudrate', type=int, default=115200, help='Baud rate (default: 115200)')
    parser.add_argument('--test', choices=['mouse', 'keyboard', 'gamepad', 'all'], default='all',
                        help='Which descriptor to test')
    parser.add_argument('--stats', action='store_true', help='Only show cache statistics')
    parser.add_argument('--add', nargs=3, metavar=('ADDR', 'IFACE', 'HEX_FILE'),
                        help='Add custom descriptor from hex file')
    parser.add_argument('--get', nargs=2, type=int, metavar=('ADDR', 'IFACE'),
                        help='Get descriptor info')
    
    args = parser.parse_args()
    
    try:
        tester = DescriptorTester(args.port, args.baudrate)
        
        if args.stats:
            tester.get_stats()
        elif args.add:
            addr, iface, hex_file = args.add
            with open(hex_file, 'r') as f:
                hex_data = f.read().strip()
                # Parse hex string (supports formats: "05 01 09 02" or "05,01,09,02")
                hex_bytes = [int(b, 16) for b in hex_data.replace(',', ' ').split()]
                tester.add_descriptor(int(addr), int(iface), hex_bytes)
        elif args.get:
            addr, iface = args.get
            tester.get_descriptor(addr, iface)
        else:
            if args.test == 'mouse':
                tester.test_mouse()
            elif args.test == 'keyboard':
                tester.test_keyboard()
            elif args.test == 'gamepad':
                tester.test_gamepad()
            else:
                tester.test_all()
        
        tester.close()
        
    except serial.SerialException as e:
        print(f"Error: Could not open serial port {args.port}: {e}", file=sys.stderr)
        print("\nTip: Make sure the SAMD51 firmware is flashed and the device is connected.", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("\n\nInterrupted by user")
        sys.exit(0)

if __name__ == '__main__':
    main()
