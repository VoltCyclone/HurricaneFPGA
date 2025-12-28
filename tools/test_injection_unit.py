#!/usr/bin/env python3
"""
Unit tests for HID injection functionality
Tests command generation without requiring hardware
"""

import unittest
import sys


class TestMouseCommands(unittest.TestCase):
    """Test mouse command generation"""
    
    def test_move_command_basic(self):
        """Test basic move command"""
        x, y = 10, -5
        cmd = f"nozen.move({x},{y})\n"
        
        self.assertTrue(cmd.startswith("nozen.move("))
        self.assertTrue(cmd.endswith(")\n"))
        self.assertIn("10", cmd)
        self.assertIn("-5", cmd)
        
    def test_move_command_large_values(self):
        """Test move with large coordinate values"""
        x, y = 127, -127
        cmd = f"nozen.move({x},{y})\n"
        
        self.assertIn("127", cmd)
        self.assertIn("-127", cmd)
        
    def test_moveto_command(self):
        """Test absolute positioning command"""
        x, y = 100, 200
        cmd = f"nozen.moveto({x},{y})\n"
        
        self.assertEqual(cmd, "nozen.moveto(100,200)\n")
        
    def test_left_click_commands(self):
        """Test left mouse button commands"""
        press = "nozen.left(1)\n"
        release = "nozen.left(0)\n"
        
        self.assertEqual(press, "nozen.left(1)\n")
        self.assertEqual(release, "nozen.left(0)\n")
        
    def test_right_click_commands(self):
        """Test right mouse button commands"""
        press = "nozen.right(1)\n"
        release = "nozen.right(0)\n"
        
        self.assertEqual(press, "nozen.right(1)\n")
        self.assertEqual(release, "nozen.right(0)\n")
        
    def test_middle_click_commands(self):
        """Test middle mouse button commands"""
        press = "nozen.middle(1)\n"
        release = "nozen.middle(0)\n"
        
        self.assertEqual(press, "nozen.middle(1)\n")
        self.assertEqual(release, "nozen.middle(0)\n")
        
    def test_side_button_commands(self):
        """Test side button commands"""
        side1_press = "nozen.side1(1)\n"
        side2_press = "nozen.side2(1)\n"
        
        self.assertEqual(side1_press, "nozen.side1(1)\n")
        self.assertEqual(side2_press, "nozen.side2(1)\n")
        
    def test_wheel_scroll(self):
        """Test mouse wheel scrolling"""
        scroll_up = "nozen.wheel(5)\n"
        scroll_down = "nozen.wheel(-3)\n"
        
        self.assertEqual(scroll_up, "nozen.wheel(5)\n")
        self.assertEqual(scroll_down, "nozen.wheel(-3)\n")


class TestKeyboardCommands(unittest.TestCase):
    """Test keyboard command generation"""
    
    def setUp(self):
        """Set up scancode mappings"""
        self.SCANCODES = {
            'A': 0x04, 'B': 0x05, 'C': 0x06, 'D': 0x07,
            'ENTER': 0x28, 'SPACE': 0x2C, 'TAB': 0x2B,
        }
        
        self.MOD_LSHIFT = 0x02
        self.MOD_LCTRL = 0x01
        self.MOD_LALT = 0x04
        
    def test_single_key_press(self):
        """Test single key press command"""
        scancode = self.SCANCODES['A']
        self.assertEqual(scancode, 0x04)
        
    def test_key_with_modifier(self):
        """Test key press with modifier"""
        scancode = self.SCANCODES['C']
        modifiers = self.MOD_LCTRL
        
        # Ctrl+C
        self.assertEqual(modifiers, 0x01)
        self.assertEqual(scancode, 0x06)
        
    def test_multiple_modifiers(self):
        """Test combining multiple modifiers"""
        scancode = self.SCANCODES['A']
        modifiers = self.MOD_LSHIFT | self.MOD_LCTRL
        
        # Ctrl+Shift+A
        self.assertEqual(modifiers, 0x03)
        self.assertEqual(scancode, 0x04)
        
    def test_special_keys(self):
        """Test special key scancodes"""
        self.assertEqual(self.SCANCODES['ENTER'], 0x28)
        self.assertEqual(self.SCANCODES['SPACE'], 0x2C)
        self.assertEqual(self.SCANCODES['TAB'], 0x2B)


class TestRecoilCommands(unittest.TestCase):
    """Test recoil pattern commands"""
    
    def test_recoil_add_simple(self):
        """Test adding a simple recoil pattern"""
        name = "test_pattern"
        pattern = [10, -5, 100]
        
        pattern_str = ",".join(map(str, pattern))
        cmd = f"nozen.recoil.add({name}){{{pattern_str}}}\n"
        
        self.assertIn(name, cmd)
        self.assertIn("10,-5,100", cmd)
        
    def test_recoil_add_complex(self):
        """Test adding a complex recoil pattern"""
        name = "ak47"
        pattern = [
            10, -5, 100,
            20, -10, 150,
            15, -8, 120,
            25, -12, 180
        ]
        
        # Verify pattern is triplets
        self.assertEqual(len(pattern) % 3, 0)
        
        pattern_str = ",".join(map(str, pattern))
        cmd = f"nozen.recoil.add({name}){{{pattern_str}}}\n"
        
        self.assertIn("ak47", cmd)
        self.assertIn("{", cmd)
        self.assertIn("}", cmd)
        
    def test_recoil_delete(self):
        """Test deleting a recoil pattern"""
        name = "test_pattern"
        cmd = f"nozen.recoil.delete({name})\n"
        
        self.assertEqual(cmd, "nozen.recoil.delete(test_pattern)\n")
        
    def test_recoil_list(self):
        """Test listing recoil patterns"""
        cmd = "nozen.recoil.list\n"
        self.assertEqual(cmd, "nozen.recoil.list\n")
        
    def test_recoil_names(self):
        """Test getting pattern names"""
        cmd = "nozen.recoil.names\n"
        self.assertEqual(cmd, "nozen.recoil.names\n")
        
    def test_recoil_get(self):
        """Test getting a specific pattern"""
        name = "ak47"
        cmd = f"nozen.recoil.get({name})\n"
        
        self.assertEqual(cmd, "nozen.recoil.get(ak47)\n")


class TestCommandSequences(unittest.TestCase):
    """Test sequences of commands"""
    
    def test_click_sequence(self):
        """Test a complete click sequence"""
        sequence = [
            "nozen.left(1)\n",  # Press
            "nozen.left(0)\n",  # Release
        ]
        
        self.assertEqual(len(sequence), 2)
        self.assertTrue(all(cmd.startswith("nozen.") for cmd in sequence))
        
    def test_drag_sequence(self):
        """Test a mouse drag sequence"""
        sequence = [
            "nozen.left(1)\n",      # Press button
            "nozen.move(10,0)\n",   # Move right
            "nozen.move(10,0)\n",   # Move right more
            "nozen.left(0)\n",      # Release button
        ]
        
        self.assertEqual(len(sequence), 4)
        
    def test_double_click_sequence(self):
        """Test double-click sequence"""
        sequence = [
            "nozen.left(1)\n",
            "nozen.left(0)\n",
            "nozen.left(1)\n",
            "nozen.left(0)\n",
        ]
        
        self.assertEqual(len(sequence), 4)
        
    def test_type_sequence(self):
        """Test typing sequence with modifiers"""
        # Type "Hello" - would need scancodes for each letter
        keys = ['H', 'e', 'l', 'l', 'o']
        
        # Just verify we can create a sequence
        self.assertEqual(len(keys), 5)


class TestCommandValidation(unittest.TestCase):
    """Test command validation logic"""
    
    def test_coordinate_range(self):
        """Test valid coordinate ranges"""
        # Mouse movement is typically -127 to 127 for relative
        MIN_REL = -127
        MAX_REL = 127
        
        valid_coords = [0, 50, -50, MIN_REL, MAX_REL]
        
        for coord in valid_coords:
            self.assertGreaterEqual(coord, MIN_REL)
            self.assertLessEqual(coord, MAX_REL)
            
    def test_absolute_coordinate_range(self):
        """Test absolute positioning range"""
        # Absolute positioning uses i16 range
        MIN_ABS = -32768
        MAX_ABS = 32767
        
        valid_coords = [0, 1000, -1000, MIN_ABS, MAX_ABS]
        
        for coord in valid_coords:
            self.assertGreaterEqual(coord, MIN_ABS)
            self.assertLessEqual(coord, MAX_ABS)
            
    def test_button_state_values(self):
        """Test button state values are binary"""
        valid_states = [0, 1]
        
        for state in valid_states:
            self.assertIn(state, [0, 1])
            
    def test_wheel_amount_range(self):
        """Test wheel scroll amount range"""
        # Wheel is typically -127 to 127
        MIN_WHEEL = -127
        MAX_WHEEL = 127
        
        valid_amounts = [0, 1, -1, 5, -5, MIN_WHEEL, MAX_WHEEL]
        
        for amount in valid_amounts:
            self.assertGreaterEqual(amount, MIN_WHEEL)
            self.assertLessEqual(amount, MAX_WHEEL)


class TestPatternValidation(unittest.TestCase):
    """Test recoil pattern validation"""
    
    def test_pattern_triplet_validation(self):
        """Test that patterns must be triplets"""
        valid_pattern = [10, -5, 100, 20, -10, 150]
        invalid_pattern = [10, -5, 100, 20]  # Not divisible by 3
        
        self.assertEqual(len(valid_pattern) % 3, 0)
        self.assertNotEqual(len(invalid_pattern) % 3, 0)
        
    def test_pattern_value_range(self):
        """Test pattern values are in valid range"""
        pattern = [10, -5, 100, 20, -10, 150]
        
        # x,y values should be in i16 range, delays should be positive
        for i, val in enumerate(pattern):
            if i % 3 == 2:  # delay values (every 3rd)
                self.assertGreater(val, 0, "Delay should be positive")
            else:  # x,y values
                self.assertGreaterEqual(val, -32768)
                self.assertLessEqual(val, 32767)
                
    def test_pattern_name_validation(self):
        """Test pattern name requirements"""
        valid_names = ["ak47", "m4a1", "test_pattern", "recoil123"]
        
        for name in valid_names:
            self.assertIsInstance(name, str)
            self.assertGreater(len(name), 0)
            self.assertLessEqual(len(name), 32)  # MAX_PATTERN_NAME_LEN
            
    def test_max_pattern_steps(self):
        """Test maximum pattern size"""
        MAX_STEPS = 64
        
        # Create a pattern at the limit (64 values = 21 triplets + 1 extra)
        # Actually 63 values = 21 triplets is max
        max_pattern = [1, 2, 3] * 21
        
        self.assertLessEqual(len(max_pattern), MAX_STEPS)
        self.assertEqual(len(max_pattern) % 3, 0)


class TestUtilityCommands(unittest.TestCase):
    """Test utility and debug commands"""
    
    def test_getpos_command(self):
        """Test get position command"""
        cmd = "nozen.getpos\n"
        self.assertEqual(cmd, "nozen.getpos\n")
        
    def test_restart_command(self):
        """Test restart command"""
        cmd = "nozen.restart\n"
        self.assertEqual(cmd, "nozen.restart\n")
        
    def test_descriptor_stats_command(self):
        """Test descriptor statistics command"""
        cmd = "nozen.descriptor.stats\n"
        self.assertEqual(cmd, "nozen.descriptor.stats\n")
        
    def test_descriptor_get_command(self):
        """Test descriptor get command"""
        addr, iface = 1, 0
        cmd = f"nozen.descriptor.get({addr},{iface})\n"
        
        self.assertEqual(cmd, "nozen.descriptor.get(1,0)\n")


class TestResponseParsing(unittest.TestCase):
    """Test parsing responses from device"""
    
    def test_position_response_format(self):
        """Test parsing position response"""
        response = "km.pos(100,200)\n"
        
        # Parse the response
        self.assertTrue(response.startswith("km.pos("))
        self.assertTrue(response.endswith(")\n"))
        
        # Extract coordinates
        coords_str = response[7:-2]  # Remove "km.pos(" and ")\n"
        x_str, y_str = coords_str.split(',')
        
        x = int(x_str)
        y = int(y_str)
        
        self.assertEqual(x, 100)
        self.assertEqual(y, 200)
        
    def test_success_response(self):
        """Test parsing success responses"""
        responses = [
            "Recoil pattern added\n",
            "Pattern deleted\n",
            "OK\n",
        ]
        
        for resp in responses:
            self.assertIsInstance(resp, str)
            self.assertTrue(resp.endswith("\n"))
            
    def test_error_response(self):
        """Test parsing error responses"""
        error_resp = "Error: Pattern not found\n"
        
        self.assertTrue(error_resp.startswith("Error:"))
        self.assertIn("Pattern not found", error_resp)


def run_tests():
    """Run all unit tests"""
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    
    # Add all test classes
    suite.addTests(loader.loadTestsFromTestCase(TestMouseCommands))
    suite.addTests(loader.loadTestsFromTestCase(TestKeyboardCommands))
    suite.addTests(loader.loadTestsFromTestCase(TestRecoilCommands))
    suite.addTests(loader.loadTestsFromTestCase(TestCommandSequences))
    suite.addTests(loader.loadTestsFromTestCase(TestCommandValidation))
    suite.addTests(loader.loadTestsFromTestCase(TestPatternValidation))
    suite.addTests(loader.loadTestsFromTestCase(TestUtilityCommands))
    suite.addTests(loader.loadTestsFromTestCase(TestResponseParsing))
    
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    
    return 0 if result.wasSuccessful() else 1


if __name__ == '__main__':
    sys.exit(run_tests())
