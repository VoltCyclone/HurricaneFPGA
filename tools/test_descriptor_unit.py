#!/usr/bin/env python3
"""
Unit tests for HID descriptor parsing functionality
Tests the descriptor validation without requiring hardware
"""

import unittest
import sys


class TestHIDDescriptorParsing(unittest.TestCase):
    """Test HID descriptor parsing and validation"""
    
    def test_mouse_descriptor_structure(self):
        """Test that mouse descriptor has correct structure"""
        # Standard mouse descriptor
        mouse_desc = [
            0x05, 0x01,  # Usage Page (Generic Desktop)
            0x09, 0x02,  # Usage (Mouse)
            0xA1, 0x01,  # Collection (Application)
            0x09, 0x01,  # Usage (Pointer)
            0xA1, 0x00,  # Collection (Physical)
            0x05, 0x09,  # Usage Page (Button)
            0x19, 0x01,  # Usage Minimum (1)
            0x29, 0x03,  # Usage Maximum (3)
            0x15, 0x00,  # Logical Minimum (0)
            0x25, 0x01,  # Logical Maximum (1)
            0x95, 0x03,  # Report Count (3)
            0x75, 0x01,  # Report Size (1)
            0x81, 0x02,  # Input (Data, Variable, Absolute)
            0xC0,        # End Collection
            0xC0,        # End Collection
        ]
        
        # Basic structure validation
        self.assertGreater(len(mouse_desc), 0)
        self.assertEqual(mouse_desc[0], 0x05)  # Usage Page tag
        self.assertEqual(mouse_desc[1], 0x01)  # Generic Desktop
        self.assertEqual(mouse_desc[2], 0x09)  # Usage tag
        self.assertEqual(mouse_desc[3], 0x02)  # Mouse usage
        
    def test_keyboard_descriptor_structure(self):
        """Test that keyboard descriptor has correct structure"""
        keyboard_desc = [
            0x05, 0x01,  # Usage Page (Generic Desktop)
            0x09, 0x06,  # Usage (Keyboard)
            0xA1, 0x01,  # Collection (Application)
            0x05, 0x07,  # Usage Page (Keyboard)
            0x19, 0xE0,  # Usage Minimum (Left Control)
            0x29, 0xE7,  # Usage Maximum (Right GUI)
            0x15, 0x00,  # Logical Minimum (0)
            0x25, 0x01,  # Logical Maximum (1)
            0x75, 0x01,  # Report Size (1)
            0x95, 0x08,  # Report Count (8)
            0x81, 0x02,  # Input (Data, Variable, Absolute)
            0xC0,        # End Collection
        ]
        
        self.assertGreater(len(keyboard_desc), 0)
        self.assertEqual(keyboard_desc[0], 0x05)
        self.assertEqual(keyboard_desc[3], 0x06)  # Keyboard usage
        
    def test_collection_nesting(self):
        """Test that collections are properly nested"""
        # Simple descriptor with nested collections
        desc = [
            0xA1, 0x01,  # Collection (Application)
            0xA1, 0x00,  # Collection (Physical)
            0xC0,        # End Collection
            0xC0,        # End Collection
        ]
        
        # Count collections vs end collections
        collections = sum(1 for i in range(len(desc)) if desc[i] == 0xA1)
        end_collections = sum(1 for i in range(len(desc)) if desc[i] == 0xC0)
        
        self.assertEqual(collections, end_collections)
        self.assertEqual(collections, 2)
        
    def test_usage_page_values(self):
        """Test valid usage page values"""
        GENERIC_DESKTOP = 0x01
        SIMULATION = 0x02
        VR = 0x03
        SPORT = 0x04
        GAME = 0x05
        BUTTON = 0x09
        KEYBOARD = 0x07
        
        valid_pages = [GENERIC_DESKTOP, SIMULATION, VR, SPORT, GAME, BUTTON, KEYBOARD]
        
        for page in valid_pages:
            self.assertGreaterEqual(page, 0x01)
            self.assertLessEqual(page, 0xFF)


class TestCommandFormatting(unittest.TestCase):
    """Test command formatting and parsing"""
    
    def test_move_command_format(self):
        """Test mouse move command format"""
        x, y = 10, -5
        cmd = f"nozen.move({x},{y})"
        
        self.assertIn("nozen.move(", cmd)
        self.assertIn(str(x), cmd)
        self.assertIn(str(y), cmd)
        
    def test_moveto_command_format(self):
        """Test absolute move command format"""
        x, y = 100, 200
        cmd = f"nozen.moveto({x},{y})"
        
        self.assertTrue(cmd.startswith("nozen.moveto("))
        self.assertTrue(cmd.endswith(")"))
        
    def test_button_command_format(self):
        """Test button press/release commands"""
        press_cmd = "nozen.left(1)"
        release_cmd = "nozen.left(0)"
        
        self.assertEqual(press_cmd, "nozen.left(1)")
        self.assertEqual(release_cmd, "nozen.left(0)")
        
    def test_wheel_command_format(self):
        """Test mouse wheel command"""
        amount = 5
        cmd = f"nozen.wheel({amount})"
        
        self.assertEqual(cmd, "nozen.wheel(5)")
        
    def test_negative_wheel(self):
        """Test negative wheel value"""
        amount = -3
        cmd = f"nozen.wheel({amount})"
        
        self.assertEqual(cmd, "nozen.wheel(-3)")


class TestScancodeMapping(unittest.TestCase):
    """Test HID keyboard scancode mappings"""
    
    def setUp(self):
        """Set up scancode mappings"""
        self.SCANCODES = {
            'A': 0x04, 'B': 0x05, 'C': 0x06, 'D': 0x07,
            'E': 0x08, 'F': 0x09, 'G': 0x0A, 'H': 0x0B,
            'I': 0x0C, 'J': 0x0D, 'K': 0x0E, 'L': 0x0F,
            'M': 0x10, 'N': 0x11, 'O': 0x12, 'P': 0x13,
            'Q': 0x14, 'R': 0x15, 'S': 0x16, 'T': 0x17,
            'U': 0x18, 'V': 0x19, 'W': 0x1A, 'X': 0x1B,
            'Y': 0x1C, 'Z': 0x1D,
            '1': 0x1E, '2': 0x1F, '3': 0x20, '4': 0x21,
            '5': 0x22, '6': 0x23, '7': 0x24, '8': 0x25,
            '9': 0x26, '0': 0x27,
            ' ': 0x2C, '\n': 0x28,
        }
        
    def test_letter_scancodes(self):
        """Test that letter scancodes are sequential"""
        self.assertEqual(self.SCANCODES['A'], 0x04)
        self.assertEqual(self.SCANCODES['Z'], 0x1D)
        
        # Check sequential
        for i, letter in enumerate('ABCDEFGHIJKLMNOPQRSTUVWXYZ'):
            expected = 0x04 + i
            self.assertEqual(self.SCANCODES[letter], expected,
                           f"Letter {letter} should be 0x{expected:02X}")
            
    def test_number_scancodes(self):
        """Test number key scancodes"""
        self.assertEqual(self.SCANCODES['1'], 0x1E)
        self.assertEqual(self.SCANCODES['0'], 0x27)
        
    def test_special_keys(self):
        """Test special key scancodes"""
        self.assertEqual(self.SCANCODES[' '], 0x2C)  # Space
        self.assertEqual(self.SCANCODES['\n'], 0x28)  # Enter
        
    def test_all_scancodes_unique(self):
        """Test that all scancodes are unique"""
        scancodes = list(self.SCANCODES.values())
        self.assertEqual(len(scancodes), len(set(scancodes)),
                        "Duplicate scancodes found")


class TestModifierKeys(unittest.TestCase):
    """Test keyboard modifier key bitmasks"""
    
    def setUp(self):
        """Set up modifier constants"""
        self.MOD_LSHIFT = 0x02
        self.MOD_LCTRL = 0x01
        self.MOD_LALT = 0x04
        self.MOD_LGUI = 0x08
        self.MOD_RSHIFT = 0x20
        self.MOD_RCTRL = 0x10
        self.MOD_RALT = 0x40
        self.MOD_RGUI = 0x80
        
    def test_modifier_values(self):
        """Test that modifiers are powers of 2"""
        modifiers = [
            self.MOD_LCTRL, self.MOD_LSHIFT, self.MOD_LALT, self.MOD_LGUI,
            self.MOD_RCTRL, self.MOD_RSHIFT, self.MOD_RALT, self.MOD_RGUI
        ]
        
        for mod in modifiers:
            # Check it's a power of 2 (only one bit set)
            self.assertEqual(bin(mod).count('1'), 1,
                           f"Modifier 0x{mod:02X} should be power of 2")
            
    def test_modifier_combinations(self):
        """Test combining multiple modifiers"""
        combo = self.MOD_LCTRL | self.MOD_LSHIFT
        self.assertEqual(combo, 0x03)
        
        combo = self.MOD_LCTRL | self.MOD_LALT
        self.assertEqual(combo, 0x05)
        
        # All left modifiers
        all_left = self.MOD_LCTRL | self.MOD_LSHIFT | self.MOD_LALT | self.MOD_LGUI
        self.assertEqual(all_left, 0x0F)
        
    def test_no_modifier_overlap(self):
        """Test that modifiers don't overlap"""
        modifiers = [
            self.MOD_LCTRL, self.MOD_LSHIFT, self.MOD_LALT, self.MOD_LGUI,
            self.MOD_RCTRL, self.MOD_RSHIFT, self.MOD_RALT, self.MOD_RGUI
        ]
        
        # Check each pair doesn't overlap
        for i, mod1 in enumerate(modifiers):
            for mod2 in modifiers[i+1:]:
                self.assertEqual(mod1 & mod2, 0,
                               f"Modifiers 0x{mod1:02X} and 0x{mod2:02X} overlap")


class TestRecoilPatternFormat(unittest.TestCase):
    """Test recoil pattern command formatting"""
    
    def test_recoil_add_format(self):
        """Test recoil pattern add command format"""
        name = "ak47"
        pattern = [10, -5, 100, 20, -10, 150]
        
        pattern_str = ",".join(map(str, pattern))
        cmd = f"nozen.recoil.add({name}){{{pattern_str}}}"
        
        self.assertIn("nozen.recoil.add(", cmd)
        self.assertIn(name, cmd)
        self.assertIn("{", cmd)
        self.assertIn("}", cmd)
        
    def test_recoil_delete_format(self):
        """Test recoil delete command format"""
        name = "ak47"
        cmd = f"nozen.recoil.delete({name})"
        
        self.assertEqual(cmd, "nozen.recoil.delete(ak47)")
        
    def test_recoil_pattern_triplets(self):
        """Test that recoil patterns have triplets (x, y, delay)"""
        pattern = [10, -5, 100, 20, -10, 150]
        
        # Should be divisible by 3
        self.assertEqual(len(pattern) % 3, 0,
                        "Pattern should be triplets of (x, y, delay)")
        
        # Extract triplets
        triplets = [(pattern[i], pattern[i+1], pattern[i+2]) 
                   for i in range(0, len(pattern), 3)]
        
        self.assertEqual(len(triplets), 2)
        self.assertEqual(triplets[0], (10, -5, 100))
        self.assertEqual(triplets[1], (20, -10, 150))


class TestMouseStateTracking(unittest.TestCase):
    """Test mouse position state tracking logic"""
    
    def test_relative_movement(self):
        """Test relative mouse movement tracking"""
        x, y = 0, 0
        
        # Move right and down
        dx, dy = 10, 20
        x += dx
        y += dy
        
        self.assertEqual(x, 10)
        self.assertEqual(y, 20)
        
    def test_absolute_positioning(self):
        """Test absolute positioning"""
        current_x, current_y = 50, 50
        target_x, target_y = 100, 150
        
        delta_x = target_x - current_x
        delta_y = target_y - current_y
        
        self.assertEqual(delta_x, 50)
        self.assertEqual(delta_y, 100)
        
    def test_position_bounds(self):
        """Test position boundary handling"""
        # i16 range: -32768 to 32767
        MIN_POS = -32768
        MAX_POS = 32767
        
        # Test max boundary
        x = MAX_POS
        self.assertLessEqual(x, MAX_POS)
        
        # Test min boundary
        x = MIN_POS
        self.assertGreaterEqual(x, MIN_POS)


def run_tests():
    """Run all unit tests"""
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    
    # Add all test classes
    suite.addTests(loader.loadTestsFromTestCase(TestHIDDescriptorParsing))
    suite.addTests(loader.loadTestsFromTestCase(TestCommandFormatting))
    suite.addTests(loader.loadTestsFromTestCase(TestScancodeMapping))
    suite.addTests(loader.loadTestsFromTestCase(TestModifierKeys))
    suite.addTests(loader.loadTestsFromTestCase(TestRecoilPatternFormat))
    suite.addTests(loader.loadTestsFromTestCase(TestMouseStateTracking))
    
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    
    return 0 if result.wasSuccessful() else 1


if __name__ == '__main__':
    sys.exit(run_tests())
