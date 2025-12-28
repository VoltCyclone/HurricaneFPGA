#!/usr/bin/env python3
"""
Cynthion HID Injection Test Script

Matches the command format from HurricaneMAKCM ESP32 project.
Supports nozen.move(), nozen.left(), nozen.right(), etc.

Usage:
    python3 test_injection.py [device]

Examples:
    # Move mouse relative
    python3 test_injection.py --move 10 -5

    # Move mouse absolute
    python3 test_injection.py --moveto 100 200

    # Click mouse buttons
    python3 test_injection.py --left-press
    python3 test_injection.py --left-release
    python3 test_injection.py --right-click

    # Mouse wheel
    python3 test_injection.py --wheel 5

Requirements:
    pip install pyserial
"""

import serial
import time
import argparse
import sys

# HID Keyboard Scancodes (US layout)
SCANCODES = {
    'A': 0x04, 'B': 0x05, 'C': 0x06, 'D': 0x07, 'E': 0x08, 'F': 0x09,
    'G': 0x0A, 'H': 0x0B, 'I': 0x0C, 'J': 0x0D, 'K': 0x0E, 'L': 0x0F,
    'M': 0x10, 'N': 0x11, 'O': 0x12, 'P': 0x13, 'Q': 0x14, 'R': 0x15,
    'S': 0x16, 'T': 0x17, 'U': 0x18, 'V': 0x19, 'W': 0x1A, 'X': 0x1B,
    'Y': 0x1C, 'Z': 0x1D,
    '1': 0x1E, '2': 0x1F, '3': 0x20, '4': 0x21, '5': 0x22,
    '6': 0x23, '7': 0x24, '8': 0x25, '9': 0x26, '0': 0x27,
    ' ': 0x2C, '\n': 0x28, '\t': 0x2B,
}

# Modifier keys
MOD_LSHIFT = 0x02
MOD_LCTRL = 0x01
MOD_LALT = 0x04

class CynthionInjector:
    def __init__(self, device='/dev/ttyACM0', baudrate=115200):
        """Initialize connection to Cynthion SAMD51"""
        self.device = device
        self.baudrate = baudrate
        self.ser = None
        self.mouse_x = 0
        self.mouse_y = 0
        
    def connect(self):
        """Connect to device"""
        try:
            self.ser = serial.Serial(self.device, self.baudrate, timeout=0.1)
            time.sleep(0.5)  # Wait for connection to stabilize
            print(f"[+] Connected to {self.device} at {self.baudrate} baud")
            return True
        except serial.SerialException as e:
            print(f"[-] Failed to connect: {e}")
            return False
    
    def disconnect(self):
        """Disconnect from device"""
        if self.ser:
            self.ser.close()
            print("[+] Disconnected")
    
    def move(self, x, y):
        """Move mouse relative - nozen.move(x,y)"""
        cmd = f"nozen.move({x},{y})\n"
        self.ser.write(cmd.encode('ascii'))
        print(f"[>] {cmd.strip()}")
        self.mouse_x += x
        self.mouse_y += y
        time.sleep(0.01)
    
    def moveto(self, x, y):
        """Move mouse absolute - nozen.moveto(x,y)"""
        cmd = f"nozen.moveto({x},{y})\n"
        self.ser.write(cmd.encode('ascii'))
        print(f"[>] {cmd.strip()}")
        self.mouse_x = x
        self.mouse_y = y
        time.sleep(0.01)
    
    def get_pos(self):
        """Get mouse position - nozen.getpos()"""
        cmd = "nozen.getpos()\n"
        self.ser.write(cmd.encode('ascii'))
        print(f"[>] {cmd.strip()}")
        time.sleep(0.05)
        if self.ser.in_waiting:
            response = self.ser.readline().decode('ascii', errors='ignore').strip()
            print(f"[<] {response}")
            return response
    
    def left_press(self):
        """Press left button - nozen.left(1)"""
        self.ser.write(b"nozen.left(1)\n")
        print("[>] nozen.left(1)")
        time.sleep(0.01)
    
    def left_release(self):
        """Release left button - nozen.left(0)"""
        self.ser.write(b"nozen.left(0)\n")
        print("[>] nozen.left(0)")
        time.sleep(0.01)
    
    def right_press(self):
        """Press right button - nozen.right(1)"""
        self.ser.write(b"nozen.right(1)\n")
        print("[>] nozen.right(1)")
        time.sleep(0.01)
    
    def right_release(self):
        """Release right button - nozen.right(0)"""
        self.ser.write(b"nozen.right(0)\n")
        print("[>] nozen.right(0)")
        time.sleep(0.01)
    
    def middle_press(self):
        """Press middle button - nozen.middle(1)"""
        self.ser.write(b"nozen.middle(1)\n")
        print("[>] nozen.middle(1)")
        time.sleep(0.01)
    
    def middle_release(self):
        """Release middle button - nozen.middle(0)"""
        self.ser.write(b"nozen.middle(0)\n")
        print("[>] nozen.middle(0)")
        time.sleep(0.01)
    
    def side1_press(self):
        """Press forward side button - nozen.side1(1)"""
        self.ser.write(b"nozen.side1(1)\n")
        print("[>] nozen.side1(1)")
        time.sleep(0.01)
    
    def side1_release(self):
        """Release forward side button - nozen.side1(0)"""
        self.ser.write(b"nozen.side1(0)\n")
        print("[>] nozen.side1(0)")
        time.sleep(0.01)
    
    def side2_press(self):
        """Press back side button - nozen.side2(1)"""
        self.ser.write(b"nozen.side2(1)\n")
        print("[>] nozen.side2(1)")
        time.sleep(0.01)
    
    def side2_release(self):
        """Release back side button - nozen.side2(0)"""
        self.ser.write(b"nozen.side2(0)\n")
        print("[>] nozen.side2(0)")
        time.sleep(0.01)
    
    def wheel(self, movement):
        """Mouse wheel - nozen.wheel(movement)"""
        cmd = f"nozen.wheel({movement})\n"
        self.ser.write(cmd.encode('ascii'))
        print(f"[>] {cmd.strip()}")
        time.sleep(0.01)
    
    def left_click(self):
        """Click left button (press + release)"""
        self.left_press()
        time.sleep(0.05)
        self.left_release()
    
    def right_click(self):
        """Click right button (press + release)"""
        self.right_press()
        time.sleep(0.05)
        self.right_release()
    
    def middle_click(self):
        """Click middle button (press + release)"""
        self.middle_press()
        time.sleep(0.05)
        self.middle_release()
    
    def recoil_add(self, name, pattern):
        """Add recoil pattern - nozen.recoil.add(name){x,y,delay,...}"""
        pattern_str = ','.join(map(str, pattern))
        cmd = f"nozen.recoil.add({name}){{{pattern_str}}}\n"
        self.ser.write(cmd.encode('ascii'))
        print(f"[>] {cmd.strip()}")
        time.sleep(0.05)
        if self.ser.in_waiting:
            response = self.ser.readline().decode('ascii', errors='ignore').strip()
            print(f"[<] {response}")
    
    def recoil_delete(self, name):
        """Delete recoil pattern - nozen.recoil.delete(name)"""
        cmd = f"nozen.recoil.delete({name})\n"
        self.ser.write(cmd.encode('ascii'))
        print(f"[>] {cmd.strip()}")
        time.sleep(0.05)
        if self.ser.in_waiting:
            response = self.ser.readline().decode('ascii', errors='ignore').strip()
            print(f"[<] {response}")
    
    def recoil_list(self):
        """List all recoil patterns - nozen.recoil.list"""
        cmd = "nozen.recoil.list\n"
        self.ser.write(cmd.encode('ascii'))
        print(f"[>] {cmd.strip()}")
        time.sleep(0.05)
        while self.ser.in_waiting:
            response = self.ser.readline().decode('ascii', errors='ignore').strip()
            print(f"[<] {response}")
    
    def recoil_get(self, name):
        """Get specific recoil pattern - nozen.recoil.get(name)"""
        cmd = f"nozen.recoil.get({name})\n"
        self.ser.write(cmd.encode('ascii'))
        print(f"[>] {cmd.strip()}")
        time.sleep(0.05)
        if self.ser.in_waiting:
            response = self.ser.readline().decode('ascii', errors='ignore').strip()
            print(f"[<] {response}")
    
    def recoil_names(self):
        """List recoil pattern names - nozen.recoil.names"""
        cmd = "nozen.recoil.names\n"
        self.ser.write(cmd.encode('ascii'))
        print(f"[>] {cmd.strip()}")
        time.sleep(0.05)
        while self.ser.in_waiting:
            response = self.ser.readline().decode('ascii', errors='ignore').strip()
            print(f"[<] {response}")
    
    def print_message(self, message):
        """Print message - nozen.print(message)"""
        cmd = f"nozen.print({message})\n"
        self.ser.write(cmd.encode('ascii'))
        print(f"[>] {cmd.strip()}")
        time.sleep(0.05)
        if self.ser.in_waiting:
            response = self.ser.readline().decode('ascii', errors='ignore').strip()
            print(f"[<] {response}")
    
    def restart(self):
        """Restart device - nozen.restart"""
        cmd = "nozen.restart\n"
        self.ser.write(cmd.encode('ascii'))
        print(f"[>] {cmd.strip()}")
        time.sleep(0.5)
        if self.ser.in_waiting:
            response = self.ser.readline().decode('ascii', errors='ignore').strip()
            print(f"[<] {response}")
    
    def monitor_status(self):
        """Monitor status messages from FPGA"""
        print("[*] Monitoring FPGA status (Ctrl+C to stop)...")
        try:
            while True:
                if self.ser.in_waiting:
                    line = self.ser.readline().decode('ascii', errors='ignore').strip()
                    if line:
                        print(f"[<] {line}")
                time.sleep(0.1)
        except KeyboardInterrupt:
            print("\n[*] Stopped monitoring")

def main():
    parser = argparse.ArgumentParser(description='Cynthion HID Injection Tool (nozen command format)')
    parser.add_argument('--device', default='/dev/ttyACM0', help='Serial device (default: /dev/ttyACM0)')
    parser.add_argument('--baud', type=int, default=115200, help='Baud rate (default: 115200)')
    
    # Mouse movement actions
    parser.add_argument('--move', nargs=2, type=int, metavar=('X', 'Y'), help='Move mouse relative: nozen.move(x,y)')
    parser.add_argument('--moveto', nargs=2, type=int, metavar=('X', 'Y'), help='Move mouse absolute: nozen.moveto(x,y)')
    parser.add_argument('--getpos', action='store_true', help='Get mouse position: nozen.getpos()')
    
    # Mouse button actions
    parser.add_argument('--left-press', action='store_true', help='Press left button: nozen.left(1)')
    parser.add_argument('--left-release', action='store_true', help='Release left button: nozen.left(0)')
    parser.add_argument('--left-click', action='store_true', help='Click left button')
    parser.add_argument('--right-press', action='store_true', help='Press right button: nozen.right(1)')
    parser.add_argument('--right-release', action='store_true', help='Release right button: nozen.right(0)')
    parser.add_argument('--right-click', action='store_true', help='Click right button')
    parser.add_argument('--middle-press', action='store_true', help='Press middle button: nozen.middle(1)')
    parser.add_argument('--middle-release', action='store_true', help='Release middle button: nozen.middle(0)')
    parser.add_argument('--middle-click', action='store_true', help='Click middle button')
    parser.add_argument('--side1-press', action='store_true', help='Press side1 button: nozen.side1(1)')
    parser.add_argument('--side1-release', action='store_true', help='Release side1 button: nozen.side1(0)')
    parser.add_argument('--side2-press', action='store_true', help='Press side2 button: nozen.side2(1)')
    parser.add_argument('--side2-release', action='store_true', help='Release side2 button: nozen.side2(0)')
    
    # Wheel action
    parser.add_argument('--wheel', type=int, metavar='AMOUNT', help='Mouse wheel: nozen.wheel(amount)')
    
    # Recoil pattern management
    parser.add_argument('--recoil-add', nargs=2, metavar=('NAME', 'PATTERN'), help='Add recoil pattern: nozen.recoil.add(name){x,y,delay,...}')
    parser.add_argument('--recoil-delete', metavar='NAME', help='Delete recoil pattern: nozen.recoil.delete(name)')
    parser.add_argument('--recoil-list', action='store_true', help='List all recoil patterns: nozen.recoil.list')
    parser.add_argument('--recoil-get', metavar='NAME', help='Get specific recoil pattern: nozen.recoil.get(name)')
    parser.add_argument('--recoil-names', action='store_true', help='List recoil pattern names: nozen.recoil.names')
    
    # Utility commands
    parser.add_argument('--print', metavar='MESSAGE', help='Print message: nozen.print(message)')
    parser.add_argument('--restart', action='store_true', help='Restart device: nozen.restart')
    
    # Monitor
    parser.add_argument('--monitor', action='store_true', help='Monitor FPGA status messages')
    
    args = parser.parse_args()
    
    # Create injector
    injector = CynthionInjector(args.device, args.baud)
    
    if not injector.connect():
        sys.exit(1)
    
    try:
        # Execute actions
        if args.move:
            x, y = args.move
            injector.move(x, y)
        
        if args.moveto:
            x, y = args.moveto
            injector.moveto(x, y)
        
        if args.getpos:
            injector.get_pos()
        
        if args.left_press:
            injector.left_press()
        
        if args.left_release:
            injector.left_release()
        
        if args.left_click:
            injector.left_click()
        
        if args.right_press:
            injector.right_press()
        
        if args.right_release:
            injector.right_release()
        
        if args.right_click:
            injector.right_click()
        
        if args.middle_press:
            injector.middle_press()
        
        if args.middle_release:
            injector.middle_release()
        
        if args.middle_click:
            injector.middle_click()
        
        if args.side1_press:
        if args.wheel is not None:
            injector.wheel(args.wheel)
        
        if args.recoil_add:
            name, pattern_str = args.recoil_add
            # Parse pattern string: "x,y,delay,x,y,delay,..."
            pattern = [int(x.strip()) for x in pattern_str.split(',')]
            injector.recoil_add(name, pattern)
        
        if args.recoil_delete:
            injector.recoil_delete(args.recoil_delete)
        
        if args.recoil_list:
            injector.recoil_list()
        
        if args.recoil_get:
            injector.recoil_get(args.recoil_get)
        
        if args.recoil_names:
            injector.recoil_names()
        
        if args.print:
            injector.print_message(args.print)
        
        if args.restart:
            injector.restart()
        
        if args.monitor:
        if not has_action:
            parser.print_help()
            print("\nExample commands (nozen format):")
            print("  python3 test_injection.py --move 10 -5")
            print("  python3 test_injection.py --moveto 100 200")
            print("  python3 test_injection.py --getpos")
            print("  python3 test_injection.py --left-click")
            print("  python3 test_injection.py --right-press")
            print("  python3 test_injection.py --wheel 5")
            print("  python3 test_injection.py --recoil-add ak47 '2,-3,50,1,-2,50,0,-1,50'")
            print("  python3 test_injection.py --recoil-list")
            print("  python3 test_injection.py --recoil-names")
            print("  python3 test_injection.py --print 'Hello World'")
            print("  python3 test_injection.py --monitor")
            args.wheel is not None, args.monitor,
            args.recoil_add, args.recoil_delete, args.recoil_list,
            args.recoil_get, args.recoil_names,
            args.print, args.restart
        ])  injector.monitor_status()
        
        # If no actions specified, show help
        has_action = any([
            args.move, args.moveto, args.getpos,
            args.left_press, args.left_release, args.left_click,
            args.right_press, args.right_release, args.right_click,
            args.middle_press, args.middle_release, args.middle_click,
            args.side1_press, args.side1_release,
            args.side2_press, args.side2_release,
            args.wheel is not None, args.monitor
        ])
        
        if not has_action:
            parser.print_help()
            print("\nExample commands (nozen format):")
            print("  python3 test_injection.py --move 10 -5")
            print("  python3 test_injection.py --moveto 100 200")
            print("  python3 test_injection.py --getpos")
            print("  python3 test_injection.py --left-click")
            print("  python3 test_injection.py --right-press")
            print("  python3 test_injection.py --wheel 5")
            print("  python3 test_injection.py --monitor")
    
    finally:
        injector.disconnect()

if __name__ == '__main__':
    main()
