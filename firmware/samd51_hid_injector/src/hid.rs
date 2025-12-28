/// HID Report Helpers
/// Utilities for constructing and parsing HID reports

/// Standard USB HID Keyboard Report (8 bytes)
#[repr(C)]
pub struct KeyboardReport {
    pub modifier: u8,     // Bit 0=LCtrl, 1=LShift, 2=LAlt, 3=LGui, 4=RCtrl, 5=RShift, 6=RAlt, 7=RGui
    pub reserved: u8,     // Reserved (always 0)
    pub keys: [u8; 6],   // Up to 6 simultaneous key presses (HID scancodes)
}

impl KeyboardReport {
    /// Create empty keyboard report (all keys released)
    pub fn empty() -> Self {
        KeyboardReport {
            modifier: 0,
            reserved: 0,
            keys: [0; 6],
        }
    }
    
    /// Create keyboard report with single key press
    pub fn single_key(scancode: u8, modifiers: u8) -> Self {
        KeyboardReport {
            modifier: modifiers,
            reserved: 0,
            keys: [scancode, 0, 0, 0, 0, 0],
        }
    }
    
    /// Convert to byte array for transmission
    pub fn to_bytes(&self) -> [u8; 8] {
        [
            self.modifier,
            self.reserved,
            self.keys[0],
            self.keys[1],
            self.keys[2],
            self.keys[3],
            self.keys[4],
            self.keys[5],
        ]
    }
}

/// Standard USB HID Mouse Report (5 bytes)
#[repr(C)]
pub struct MouseReport {
    pub buttons: u8,      // Bit 0=Left, 1=Right, 2=Middle, 3-7=Extra buttons
    pub x: i8,            // X movement (-127 to +127)
    pub y: i8,            // Y movement (-127 to +127)
    pub wheel: i8,        // Wheel movement (-127 to +127)
    pub pan: i8,          // Horizontal wheel (optional, 0 if not supported)
}

impl MouseReport {
    /// Create empty mouse report (no movement)
    pub fn empty() -> Self {
        MouseReport {
            buttons: 0,
            x: 0,
            y: 0,
            wheel: 0,
            pan: 0,
        }
    }
    
    /// Create mouse report with button click
    pub fn click(button: u8) -> Self {
        MouseReport {
            buttons: 1 << button,
            x: 0,
            y: 0,
            wheel: 0,
            pan: 0,
        }
    }
    
    /// Create mouse report with movement
    pub fn move_to(x: i8, y: i8) -> Self {
        MouseReport {
            buttons: 0,
            x,
            y,
            wheel: 0,
            pan: 0,
        }
    }
    
    /// Convert to byte array for transmission
    pub fn to_bytes(&self) -> [u8; 5] {
        [
            self.buttons,
            self.x as u8,
            self.y as u8,
            self.wheel as u8,
            self.pan as u8,
        ]
    }
}

/// HID Keyboard Scancode Constants
pub mod scancodes {
    // Letters A-Z
    pub const A: u8 = 0x04;
    pub const B: u8 = 0x05;
    pub const C: u8 = 0x06;
    pub const D: u8 = 0x07;
    pub const E: u8 = 0x08;
    pub const F: u8 = 0x09;
    pub const G: u8 = 0x0A;
    pub const H: u8 = 0x0B;
    pub const I: u8 = 0x0C;
    pub const J: u8 = 0x0D;
    pub const K: u8 = 0x0E;
    pub const L: u8 = 0x0F;
    pub const M: u8 = 0x10;
    pub const N: u8 = 0x11;
    pub const O: u8 = 0x12;
    pub const P: u8 = 0x13;
    pub const Q: u8 = 0x14;
    pub const R: u8 = 0x15;
    pub const S: u8 = 0x16;
    pub const T: u8 = 0x17;
    pub const U: u8 = 0x18;
    pub const V: u8 = 0x19;
    pub const W: u8 = 0x1A;
    pub const X: u8 = 0x1B;
    pub const Y: u8 = 0x1C;
    pub const Z: u8 = 0x1D;
    
    // Numbers 1-9, 0
    pub const KEY_1: u8 = 0x1E;
    pub const KEY_2: u8 = 0x1F;
    pub const KEY_3: u8 = 0x20;
    pub const KEY_4: u8 = 0x21;
    pub const KEY_5: u8 = 0x22;
    pub const KEY_6: u8 = 0x23;
    pub const KEY_7: u8 = 0x24;
    pub const KEY_8: u8 = 0x25;
    pub const KEY_9: u8 = 0x26;
    pub const KEY_0: u8 = 0x27;
    
    // Special keys
    pub const ENTER: u8 = 0x28;
    pub const ESCAPE: u8 = 0x29;
    pub const BACKSPACE: u8 = 0x2A;
    pub const TAB: u8 = 0x2B;
    pub const SPACE: u8 = 0x2C;
    
    // Modifier bits
    pub const MOD_LCTRL: u8 = 0x01;
    pub const MOD_LSHIFT: u8 = 0x02;
    pub const MOD_LALT: u8 = 0x04;
    pub const MOD_LGUI: u8 = 0x08;
    pub const MOD_RCTRL: u8 = 0x10;
    pub const MOD_RSHIFT: u8 = 0x20;
    pub const MOD_RALT: u8 = 0x40;
    pub const MOD_RGUI: u8 = 0x80;
}

#[cfg(test)]
mod tests {
    use super::*;
    use super::scancodes::*;

    #[test]
    fn test_keyboard_report_empty() {
        let report = KeyboardReport::empty();
        assert_eq!(report.modifier, 0);
        assert_eq!(report.reserved, 0);
        assert_eq!(report.keys, [0; 6]);
        
        let bytes = report.to_bytes();
        assert_eq!(bytes.len(), 8);
        assert_eq!(bytes, [0, 0, 0, 0, 0, 0, 0, 0]);
    }

    #[test]
    fn test_keyboard_report_single_key() {
        let report = KeyboardReport::single_key(A, 0);
        assert_eq!(report.modifier, 0);
        assert_eq!(report.keys[0], A);
        assert_eq!(report.keys[1], 0);
        
        let bytes = report.to_bytes();
        assert_eq!(bytes[0], 0); // modifier
        assert_eq!(bytes[2], A); // first key
    }

    #[test]
    fn test_keyboard_report_with_modifiers() {
        let report = KeyboardReport::single_key(A, MOD_LSHIFT | MOD_LCTRL);
        assert_eq!(report.modifier, MOD_LSHIFT | MOD_LCTRL);
        assert_eq!(report.keys[0], A);
        
        let bytes = report.to_bytes();
        assert_eq!(bytes[0], MOD_LSHIFT | MOD_LCTRL);
        assert_eq!(bytes[2], A);
    }

    #[test]
    fn test_keyboard_report_multiple_modifiers() {
        let modifiers = MOD_LCTRL | MOD_LALT | MOD_LGUI;
        let report = KeyboardReport::single_key(C, modifiers);
        assert_eq!(report.modifier, modifiers);
    }

    #[test]
    fn test_mouse_report_empty() {
        let report = MouseReport::empty();
        assert_eq!(report.buttons, 0);
        assert_eq!(report.x, 0);
        assert_eq!(report.y, 0);
        assert_eq!(report.wheel, 0);
        assert_eq!(report.pan, 0);
        
        let bytes = report.to_bytes();
        assert_eq!(bytes.len(), 5);
        assert_eq!(bytes, [0, 0, 0, 0, 0]);
    }

    #[test]
    fn test_mouse_report_click() {
        // Test left button (bit 0)
        let report = MouseReport::click(0);
        assert_eq!(report.buttons, 1);
        assert_eq!(report.to_bytes()[0], 1);
        
        // Test right button (bit 1)
        let report = MouseReport::click(1);
        assert_eq!(report.buttons, 2);
        assert_eq!(report.to_bytes()[0], 2);
        
        // Test middle button (bit 2)
        let report = MouseReport::click(2);
        assert_eq!(report.buttons, 4);
        assert_eq!(report.to_bytes()[0], 4);
    }

    #[test]
    fn test_mouse_report_movement() {
        let report = MouseReport::move_to(10, -5);
        assert_eq!(report.buttons, 0);
        assert_eq!(report.x, 10);
        assert_eq!(report.y, -5);
        assert_eq!(report.wheel, 0);
        
        let bytes = report.to_bytes();
        assert_eq!(bytes[0], 0); // no buttons
        assert_eq!(bytes[1], 10); // x
        assert_eq!(bytes[2] as i8, -5); // y
    }

    #[test]
    fn test_mouse_report_extreme_values() {
        let report = MouseReport::move_to(127, -127);
        assert_eq!(report.x, 127);
        assert_eq!(report.y, -127);
        
        let bytes = report.to_bytes();
        assert_eq!(bytes[1], 127);
        assert_eq!(bytes[2] as i8, -127);
    }

    #[test]
    fn test_mouse_report_wheel() {
        let mut report = MouseReport::empty();
        report.wheel = 3;
        
        let bytes = report.to_bytes();
        assert_eq!(bytes[3] as i8, 3);
    }

    #[test]
    fn test_scancode_constants() {
        // Verify some key scancode values
        assert_eq!(A, 0x04);
        assert_eq!(Z, 0x1D);
        assert_eq!(KEY_0, 0x27);
        assert_eq!(SPACE, 0x2C);
        assert_eq!(ENTER, 0x28);
    }

    #[test]
    fn test_modifier_constants() {
        assert_eq!(MOD_LCTRL, 0x01);
        assert_eq!(MOD_LSHIFT, 0x02);
        assert_eq!(MOD_LALT, 0x04);
        assert_eq!(MOD_LGUI, 0x08);
    }
}
