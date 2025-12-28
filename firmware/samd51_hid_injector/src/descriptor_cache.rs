/// HID Descriptor Cache
/// Stores parsed descriptors for active USB devices
/// Supports multiple devices with 128KB SAMD51 RAM

use heapless::Vec;
use crate::descriptor::{HidDescriptor, DescriptorParser, ParseError, MAX_DESCRIPTOR_SIZE};

/// Maximum number of cached device descriptors
pub const MAX_CACHED_DEVICES: usize = 8;

/// Cached descriptor entry
#[derive(Clone)]
pub struct CachedDescriptor {
    pub device_address: u8,
    pub interface_num: u8,
    pub descriptor: HidDescriptor,
    pub raw_descriptor: Vec<u8, MAX_DESCRIPTOR_SIZE>,
    pub timestamp: u32,  // For LRU eviction
}

/// Descriptor cache manager
pub struct DescriptorCache {
    entries: Vec<CachedDescriptor, MAX_CACHED_DEVICES>,
    current_time: u32,
}

impl DescriptorCache {
    /// Create new cache
    pub fn new() -> Self {
        DescriptorCache {
            entries: Vec::new(),
            current_time: 0,
        }
    }

    /// Add or update a descriptor in cache
    pub fn add(&mut self, device_address: u8, interface_num: u8, raw_descriptor: &[u8]) 
        -> Result<(), ParseError> {
        
        // Parse descriptor
        let mut parser = DescriptorParser::new();
        parser.parse(raw_descriptor)?;
        let descriptor = parser.into_descriptor();

        // Copy raw descriptor
        let mut raw_vec = Vec::new();
        for &byte in raw_descriptor.iter().take(MAX_DESCRIPTOR_SIZE) {
            let _ = raw_vec.push(byte);
        }

        self.current_time += 1;

        // Check if already exists
        if let Some(entry) = self.entries.iter_mut()
            .find(|e| e.device_address == device_address && e.interface_num == interface_num) {
            // Update existing
            entry.descriptor = descriptor;
            entry.raw_descriptor = raw_vec;
            entry.timestamp = self.current_time;
            return Ok(());
        }

        // Add new entry
        let entry = CachedDescriptor {
            device_address,
            interface_num,
            descriptor,
            raw_descriptor: raw_vec,
            timestamp: self.current_time,
        };

        if self.entries.is_full() {
            // Evict least recently used
            self.evict_lru();
        }

        self.entries.push(entry).map_err(|_| ParseError::InvalidData)?;
        
        Ok(())
    }

    /// Get cached descriptor
    pub fn get(&mut self, device_address: u8, interface_num: u8) -> Option<&HidDescriptor> {
        self.current_time += 1;
        
        if let Some(entry) = self.entries.iter_mut()
            .find(|e| e.device_address == device_address && e.interface_num == interface_num) {
            entry.timestamp = self.current_time;
            Some(&entry.descriptor)
        } else {
            None
        }
    }

    /// Get raw descriptor bytes
    pub fn get_raw(&self, device_address: u8, interface_num: u8) -> Option<&[u8]> {
        self.entries.iter()
            .find(|e| e.device_address == device_address && e.interface_num == interface_num)
            .map(|e| e.raw_descriptor.as_slice())
    }

    /// Remove descriptor from cache
    pub fn remove(&mut self, device_address: u8, interface_num: u8) -> bool {
        if let Some(pos) = self.entries.iter()
            .position(|e| e.device_address == device_address && e.interface_num == interface_num) {
            self.entries.remove(pos);
            true
        } else {
            false
        }
    }

    /// Clear all cached descriptors
    pub fn clear(&mut self) {
        self.entries.clear();
    }

    /// Get number of cached descriptors
    pub fn count(&self) -> usize {
        self.entries.len()
    }

    /// Check if cache is empty
    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    /// Evict least recently used entry
    fn evict_lru(&mut self) {
        if let Some((idx, _)) = self.entries.iter()
            .enumerate()
            .min_by_key(|(_, e)| e.timestamp) {
            self.entries.remove(idx);
        }
    }

    /// Get statistics about cached devices
    pub fn get_stats(&self) -> CacheStats {
        let mut stats = CacheStats {
            total_devices: self.entries.len(),
            keyboards: 0,
            mice: 0,
            gamepads: 0,
            other: 0,
        };

        for entry in &self.entries {
            if entry.descriptor.is_keyboard {
                stats.keyboards += 1;
            }
            if entry.descriptor.is_mouse {
                stats.mice += 1;
            }
            if entry.descriptor.is_gamepad {
                stats.gamepads += 1;
            }
            if !entry.descriptor.is_keyboard 
                && !entry.descriptor.is_mouse 
                && !entry.descriptor.is_gamepad {
                stats.other += 1;
            }
        }

        stats
    }
}

/// Cache statistics
#[derive(Debug, Clone, Copy)]
pub struct CacheStats {
    pub total_devices: usize,
    pub keyboards: usize,
    pub mice: usize,
    pub gamepads: usize,
    pub other: usize,
}

impl CacheStats {
    /// Format as string for display
    pub fn format(&self) -> heapless::String<128> {
        use core::fmt::Write;
        let mut s = heapless::String::new();
        let _ = write!(s, "Devices:{} K:{} M:{} G:{} O:{}", 
            self.total_devices,
            self.keyboards,
            self.mice,
            self.gamepads,
            self.other
        );
        s
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cache_basic() {
        let mut cache = DescriptorCache::new();
        
        // Simple mouse descriptor
        let descriptor = [
            0x05, 0x01, 0x09, 0x02, 0xA1, 0x01,
            0x09, 0x01, 0xA1, 0x00, 0x05, 0x09,
            0x19, 0x01, 0x29, 0x03, 0x15, 0x00,
            0x25, 0x01, 0x95, 0x03, 0x75, 0x01,
            0x81, 0x02, 0xC0, 0xC0,
        ];

        // Add to cache
        let result = cache.add(1, 0, &descriptor);
        assert!(result.is_ok());

        // Retrieve from cache
        let cached = cache.get(1, 0);
        assert!(cached.is_some());
        assert!(cached.unwrap().is_mouse);
    }

    #[test]
    fn test_cache_eviction() {
        let mut cache = DescriptorCache::new();
        let descriptor = [0x05, 0x01, 0x09, 0x02];

        // Fill cache beyond capacity
        for i in 0..MAX_CACHED_DEVICES + 1 {
            let _ = cache.add(i as u8, 0, &descriptor);
        }

        // Should have evicted oldest entry
        assert_eq!(cache.count(), MAX_CACHED_DEVICES);
    }
}
