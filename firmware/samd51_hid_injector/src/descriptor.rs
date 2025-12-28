/// HID Descriptor Parser
/// Parses USB HID descriptors to understand device report structures
/// Supports dynamic adaptation to any HID device

use heapless::Vec;

/// Maximum descriptor size we can parse (typical HID descriptors are 50-500 bytes)
pub const MAX_DESCRIPTOR_SIZE: usize = 1024;

/// Maximum number of report items we track
pub const MAX_REPORT_ITEMS: usize = 64;

/// HID Report Types
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ReportType {
    Input,
    Output,
    Feature,
}

/// HID Usage Page (high-level device category)
#[derive(Debug, Clone, Copy, PartialEq)]
#[repr(u8)]
pub enum UsagePage {
    GenericDesktop = 0x01,
    SimulationControls = 0x02,
    VRControls = 0x03,
    SportControls = 0x04,
    GameControls = 0x05,
    GenericDevice = 0x06,
    Keyboard = 0x07,
    LED = 0x08,
    Button = 0x09,
    Ordinal = 0x0A,
    Telephony = 0x0B,
    Consumer = 0x0C,
    Digitizer = 0x0D,
    Unknown(u16),
}

impl From<u16> for UsagePage {
    fn from(value: u16) -> Self {
        match value {
            0x01 => UsagePage::GenericDesktop,
            0x02 => UsagePage::SimulationControls,
            0x03 => UsagePage::VRControls,
            0x04 => UsagePage::SportControls,
            0x05 => UsagePage::GameControls,
            0x06 => UsagePage::GenericDevice,
            0x07 => UsagePage::Keyboard,
            0x08 => UsagePage::LED,
            0x09 => UsagePage::Button,
            0x0A => UsagePage::Ordinal,
            0x0B => UsagePage::Telephony,
            0x0C => UsagePage::Consumer,
            0x0D => UsagePage::Digitizer,
            _ => UsagePage::Unknown(value),
        }
    }
}

/// HID Usage (specific control within a usage page)
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Usage {
    pub page: UsagePage,
    pub id: u16,
}

/// Report field information
#[derive(Debug, Clone, Copy)]
pub struct ReportField {
    pub report_type: ReportType,
    pub report_id: u8,           // 0 if no report ID
    pub usage: Usage,
    pub bit_offset: u16,
    pub bit_size: u8,
    pub logical_min: i32,
    pub logical_max: i32,
    pub is_relative: bool,        // True for relative values (mouse movement)
    pub is_array: bool,           // True for arrays (keyboard keys)
}

/// Parsed HID descriptor information
#[derive(Clone)]
pub struct HidDescriptor {
    /// List of all report fields
    pub fields: Vec<ReportField, MAX_REPORT_ITEMS>,
    /// Total input report size in bytes (for each report ID)
    pub input_report_sizes: Vec<(u8, u16), 8>,
    /// Total output report size in bytes
    pub output_report_sizes: Vec<(u8, u16), 8>,
    /// Device type detection
    pub is_keyboard: bool,
    pub is_mouse: bool,
    pub is_gamepad: bool,
}

impl HidDescriptor {
    pub fn new() -> Self {
        HidDescriptor {
            fields: Vec::new(),
            input_report_sizes: Vec::new(),
            output_report_sizes: Vec::new(),
            is_keyboard: false,
            is_mouse: false,
            is_gamepad: false,
        }
    }
}

/// HID Descriptor Parser
pub struct DescriptorParser {
    descriptor: HidDescriptor,
    // Parser state
    current_usage_page: u16,
    current_usage: u16,
    current_report_id: u8,
    current_bit_offset: u16,
    logical_minimum: i32,
    logical_maximum: i32,
    report_size: u8,
    report_count: u8,
}

impl DescriptorParser {
    pub fn new() -> Self {
        DescriptorParser {
            descriptor: HidDescriptor::new(),
            current_usage_page: 0,
            current_usage: 0,
            current_report_id: 0,
            current_bit_offset: 0,
            logical_minimum: 0,
            logical_maximum: 0,
            report_size: 0,
            report_count: 0,
        }
    }

    /// Parse a HID descriptor from raw bytes
    pub fn parse(&mut self, data: &[u8]) -> Result<(), ParseError> {
        let mut i = 0;
        while i < data.len() {
            let item_header = data[i];
            i += 1;

            // Parse item header
            let size = (item_header & 0x03) as usize;
            let item_type = (item_header >> 2) & 0x03;
            let tag = (item_header >> 4) & 0x0F;

            // Handle long items (rare)
            let actual_size = if size == 3 {
                if i >= data.len() {
                    return Err(ParseError::UnexpectedEnd);
                }
                let long_size = data[i] as usize;
                i += 1;
                long_size
            } else {
                size
            };

            // Extract data value
            if i + actual_size > data.len() {
                return Err(ParseError::UnexpectedEnd);
            }

            let value = match actual_size {
                0 => 0,
                1 => data[i] as u32,
                2 => u16::from_le_bytes([data[i], data[i + 1]]) as u32,
                4 => u32::from_le_bytes([data[i], data[i + 1], data[i + 2], data[i + 3]]),
                _ => {
                    i += actual_size;
                    continue; // Skip unknown size
                }
            };
            i += actual_size;

            // Process item based on type and tag
            match item_type {
                0 => self.handle_main_item(tag, value)?,
                1 => self.handle_global_item(tag, value)?,
                2 => self.handle_local_item(tag, value)?,
                _ => {} // Reserved
            }
        }

        // Detect device types
        self.detect_device_types();

        Ok(())
    }

    /// Handle Main Items (Input, Output, Feature, Collection, End Collection)
    fn handle_main_item(&mut self, tag: u8, value: u32) -> Result<(), ParseError> {
        match tag {
            0x08 => self.add_input_item(value),      // Input
            0x09 => self.add_output_item(value),     // Output
            0x0B => self.add_feature_item(value),    // Feature
            0x0A => self.handle_collection(value),   // Collection
            0x0C => self.handle_end_collection(),    // End Collection
            _ => Ok(()),
        }
    }

    /// Handle Global Items (Usage Page, Logical Min/Max, Report Size, etc.)
    fn handle_global_item(&mut self, tag: u8, value: u32) -> Result<(), ParseError> {
        match tag {
            0x00 => self.current_usage_page = value as u16,
            0x01 => self.logical_minimum = sign_extend(value, 32),
            0x02 => self.logical_maximum = sign_extend(value, 32),
            0x07 => self.report_size = value as u8,
            0x09 => self.report_count = value as u8,
            0x08 => self.current_report_id = value as u8,
            _ => {}
        }
        Ok(())
    }

    /// Handle Local Items (Usage, Usage Min/Max)
    fn handle_local_item(&mut self, tag: u8, value: u32) -> Result<(), ParseError> {
        match tag {
            0x00 => self.current_usage = value as u16,
            _ => {}
        }
        Ok(())
    }

    /// Add an Input item (data from device to host)
    fn add_input_item(&mut self, flags: u32) -> Result<(), ParseError> {
        let is_constant = (flags & 0x01) != 0;
        let is_relative = (flags & 0x04) != 0;
        let is_array = (flags & 0x02) == 0; // Variable = not array

        // Skip constant fields (padding)
        if is_constant {
            self.current_bit_offset += (self.report_size as u16) * (self.report_count as u16);
            return Ok(());
        }

        // Add fields
        for _ in 0..self.report_count {
            let field = ReportField {
                report_type: ReportType::Input,
                report_id: self.current_report_id,
                usage: Usage {
                    page: UsagePage::from(self.current_usage_page),
                    id: self.current_usage,
                },
                bit_offset: self.current_bit_offset,
                bit_size: self.report_size,
                logical_min: self.logical_minimum,
                logical_max: self.logical_maximum,
                is_relative,
                is_array,
            };

            self.descriptor.fields.push(field).map_err(|_| ParseError::TooManyFields)?;
            self.current_bit_offset += self.report_size as u16;
        }

        // Update report size tracking
        self.update_report_size(ReportType::Input);

        Ok(())
    }

    /// Add an Output item (data from host to device)
    fn add_output_item(&mut self, _flags: u32) -> Result<(), ParseError> {
        self.current_bit_offset += (self.report_size as u16) * (self.report_count as u16);
        self.update_report_size(ReportType::Output);
        Ok(())
    }

    /// Add a Feature item (bidirectional configuration data)
    fn add_feature_item(&mut self, _flags: u32) -> Result<(), ParseError> {
        self.current_bit_offset += (self.report_size as u16) * (self.report_count as u16);
        Ok(())
    }

    fn handle_collection(&mut self, _flags: u32) -> Result<(), ParseError> {
        // Collections group related items, but we don't need deep tracking for now
        Ok(())
    }

    fn handle_end_collection(&mut self) -> Result<(), ParseError> {
        Ok(())
    }

    /// Update report size tracking
    fn update_report_size(&mut self, report_type: ReportType) {
        let size_bits = self.current_bit_offset;
        let size_bytes = ((size_bits + 7) / 8) as u16;

        let sizes = match report_type {
            ReportType::Input => &mut self.descriptor.input_report_sizes,
            ReportType::Output => &mut self.descriptor.output_report_sizes,
            _ => return,
        };

        // Update or add report size
        if let Some(entry) = sizes.iter_mut().find(|(id, _)| *id == self.current_report_id) {
            entry.1 = entry.1.max(size_bytes);
        } else {
            let _ = sizes.push((self.current_report_id, size_bytes));
        }
    }

    /// Detect device types based on usage pages
    fn detect_device_types(&mut self) {
        for field in &self.descriptor.fields {
            match field.usage.page {
                UsagePage::Keyboard => self.descriptor.is_keyboard = true,
                UsagePage::GenericDesktop => {
                    // Mouse usage IDs: 0x30=X, 0x31=Y, 0x38=Wheel
                    if field.usage.id == 0x30 || field.usage.id == 0x31 || field.usage.id == 0x38 {
                        self.descriptor.is_mouse = true;
                    }
                }
                UsagePage::Button | UsagePage::GameControls => {
                    self.descriptor.is_gamepad = true;
                }
                _ => {}
            }
        }
    }

    /// Consume parser and return descriptor
    pub fn into_descriptor(self) -> HidDescriptor {
        self.descriptor
    }
}

/// Parse errors
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ParseError {
    UnexpectedEnd,
    TooManyFields,
    InvalidData,
}

/// Sign-extend a value to i32
fn sign_extend(value: u32, bits: u32) -> i32 {
    let shift = 32 - bits;
    ((value << shift) as i32) >> shift
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_simple_mouse_descriptor() {
        // Simplified mouse descriptor
        let descriptor = [
            0x05, 0x01,        // Usage Page (Generic Desktop)
            0x09, 0x02,        // Usage (Mouse)
            0xA1, 0x01,        // Collection (Application)
            0x09, 0x01,        //   Usage (Pointer)
            0xA1, 0x00,        //   Collection (Physical)
            0x05, 0x09,        //     Usage Page (Button)
            0x19, 0x01,        //     Usage Minimum (Button 1)
            0x29, 0x03,        //     Usage Maximum (Button 3)
            0x15, 0x00,        //     Logical Minimum (0)
            0x25, 0x01,        //     Logical Maximum (1)
            0x95, 0x03,        //     Report Count (3)
            0x75, 0x01,        //     Report Size (1)
            0x81, 0x02,        //     Input (Data, Variable, Absolute)
            0x95, 0x01,        //     Report Count (1)
            0x75, 0x05,        //     Report Size (5)
            0x81, 0x03,        //     Input (Constant) - padding
            0x05, 0x01,        //     Usage Page (Generic Desktop)
            0x09, 0x30,        //     Usage (X)
            0x09, 0x31,        //     Usage (Y)
            0x15, 0x81,        //     Logical Minimum (-127)
            0x25, 0x7F,        //     Logical Maximum (127)
            0x75, 0x08,        //     Report Size (8)
            0x95, 0x02,        //     Report Count (2)
            0x81, 0x06,        //     Input (Data, Variable, Relative)
            0xC0,              //   End Collection
            0xC0,              // End Collection
        ];

        let mut parser = DescriptorParser::new();
        parser.parse(&descriptor).unwrap();
        
        let desc = parser.descriptor();
        assert!(desc.is_mouse);
        assert!(!desc.is_keyboard);
    }
}
