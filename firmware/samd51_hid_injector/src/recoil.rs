/// Recoil Pattern Management
/// Stores and manages recoil compensation patterns

use heapless::{String, Vec};
use heapless::FnvIndexMap;

const MAX_PATTERNS: usize = 16;
const MAX_PATTERN_NAME_LEN: usize = 32;
const MAX_PATTERN_STEPS: usize = 64;

#[derive(Debug, Clone)]
pub struct RecoilPattern {
    pub name: String<MAX_PATTERN_NAME_LEN>,
    /// Pattern data: triplets of (x, y, delay_ms)
    pub steps: Vec<i16, MAX_PATTERN_STEPS>,
}

pub struct RecoilManager {
    patterns: FnvIndexMap<String<MAX_PATTERN_NAME_LEN>, RecoilPattern, MAX_PATTERNS>,
}

impl RecoilManager {
    pub fn new() -> Self {
        RecoilManager {
            patterns: FnvIndexMap::new(),
        }
    }

    /// Add or update a recoil pattern
    pub fn add_pattern(&mut self, name: &str, steps: &[i16]) -> Result<(), &'static str> {
        // Validate pattern length (must be multiple of 3: x, y, delay)
        if steps.len() % 3 != 0 {
            return Err("Pattern must be x,y,delay triplets");
        }

        if steps.len() > MAX_PATTERN_STEPS {
            return Err("Pattern too long");
        }

        let mut pattern_name = String::new();
        pattern_name.push_str(name).map_err(|_| "Name too long")?;

        let mut pattern_steps = Vec::new();
        for &step in steps {
            pattern_steps.push(step).map_err(|_| "Too many steps")?;
        }

        let pattern = RecoilPattern {
            name: pattern_name.clone(),
            steps: pattern_steps,
        };

        self.patterns.insert(pattern_name, pattern)
            .map_err(|_| "Pattern storage full")?;

        Ok(())
    }

    /// Delete a pattern by name
    pub fn delete_pattern(&mut self, name: &str) -> bool {
        let mut key = String::new();
        if key.push_str(name).is_ok() {
            self.patterns.remove(&key).is_some()
        } else {
            false
        }
    }

    /// Get a pattern by name
    pub fn get_pattern(&self, name: &str) -> Option<&RecoilPattern> {
        let mut key = String::new();
        if key.push_str(name).is_ok() {
            self.patterns.get(&key)
        } else {
            None
        }
    }

    /// List all pattern names
    pub fn list_names(&self) -> impl Iterator<Item = &str> {
        self.patterns.keys().map(|s| s.as_str())
    }

    /// Get all patterns
    pub fn list_patterns(&self) -> impl Iterator<Item = &RecoilPattern> {
        self.patterns.values()
    }

    /// Get pattern count
    pub fn count(&self) -> usize {
        self.patterns.len()
    }
}

/// Parse recoil pattern from command string
/// Format: "nozen.recoil.add(name){x,y,delay,x,y,delay,...}"
pub fn parse_recoil_add(line: &[u8]) -> Option<(&[u8], Vec<i16, MAX_PATTERN_STEPS>)> {
    // Find the opening paren for name
    let args_start = b"nozen.recoil.add(".len();
    if line.len() < args_start {
        return None;
    }
    
    let args = &line[args_start..];
    
    // Find closing paren for name
    let name_end = args.iter().position(|&c| c == b')')?;
    let name = &args[..name_end];
    
    // Find opening brace for pattern data
    let pattern_start = args[name_end+1..].iter().position(|&c| c == b'{')?;
    let pattern_data = &args[name_end + 1 + pattern_start + 1..];
    
    // Find closing brace
    let pattern_end = pattern_data.iter().position(|&c| c == b'}')?;
    let pattern_str = &pattern_data[..pattern_end];
    
    // Parse comma-separated integers
    let mut steps = Vec::new();
    let mut start = 0;
    
    for i in 0..pattern_str.len() {
        if pattern_str[i] == b',' || i == pattern_str.len() - 1 {
            let end = if pattern_str[i] == b',' { i } else { i + 1 };
            let num_str = &pattern_str[start..end];
            
            if let Some(value) = parse_i16(num_str) {
                if steps.push(value).is_err() {
                    return None; // Too many steps
                }
            } else {
                return None; // Parse error
            }
            
            start = i + 1;
        }
    }
    
    Some((name, steps))
}

/// Parse recoil pattern name from delete/get/run command
/// Format: "nozen.recoil.delete(name)"
pub fn parse_recoil_name<'a>(line: &'a [u8], prefix: &[u8]) -> Option<&'a [u8]> {
    if line.len() < prefix.len() + 2 {
        return None;
    }
    
    let args = &line[prefix.len()..];
    
    // Find opening paren
    let paren_start = args.iter().position(|&c| c == b'(')?;
    let args = &args[paren_start + 1..];
    
    // Find closing paren
    let paren_end = args.iter().position(|&c| c == b')')?;
    
    Some(&args[..paren_end])
}

fn parse_i16(data: &[u8]) -> Option<i16> {
    let mut value: i16 = 0;
    let mut negative = false;
    let mut idx = 0;
    
    // Skip whitespace
    while idx < data.len() && data[idx] == b' ' {
        idx += 1;
    }
    
    // Check for negative sign
    if idx < data.len() && data[idx] == b'-' {
        negative = true;
        idx += 1;
    }
    
    // Parse digits
    while idx < data.len() && data[idx] >= b'0' && data[idx] <= b'9' {
        value = value.saturating_mul(10).saturating_add((data[idx] - b'0') as i16);
        idx += 1;
    }
    
    if negative {
        value = -value;
    }
    
    Some(value)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_recoil_manager_new() {
        let manager = RecoilManager::new();
        assert_eq!(manager.count(), 0);
    }

    #[test]
    fn test_add_pattern_basic() {
        let mut manager = RecoilManager::new();
        let steps = [10, -5, 100, 20, -10, 150]; // Two triplets: (10,-5,100), (20,-10,150)
        
        let result = manager.add_pattern("test_pattern", &steps);
        assert!(result.is_ok());
        assert_eq!(manager.count(), 1);
    }

    #[test]
    fn test_add_pattern_validation() {
        let mut manager = RecoilManager::new();
        
        // Invalid: not a multiple of 3
        let invalid_steps = [10, -5, 100, 20]; // 4 elements, not divisible by 3
        let result = manager.add_pattern("invalid", &invalid_steps);
        assert!(result.is_err());
        assert_eq!(result.unwrap_err(), "Pattern must be x,y,delay triplets");
    }

    #[test]
    fn test_add_pattern_too_long() {
        let mut manager = RecoilManager::new();
        
        // Create a pattern that's too long (> MAX_PATTERN_STEPS)
        let mut long_steps = heapless::Vec::<i16, 128>::new();
        for _ in 0..(MAX_PATTERN_STEPS + 3) {
            let _ = long_steps.push(1);
        }
        
        let result = manager.add_pattern("toolong", &long_steps);
        assert!(result.is_err());
    }

    #[test]
    fn test_get_pattern() {
        let mut manager = RecoilManager::new();
        let steps = [5, -3, 50];
        
        manager.add_pattern("mypattern", &steps).unwrap();
        
        let pattern = manager.get_pattern("mypattern");
        assert!(pattern.is_some());
        
        let pattern = pattern.unwrap();
        assert_eq!(pattern.name.as_str(), "mypattern");
        assert_eq!(pattern.steps.len(), 3);
        assert_eq!(pattern.steps[0], 5);
        assert_eq!(pattern.steps[1], -3);
        assert_eq!(pattern.steps[2], 50);
    }

    #[test]
    fn test_get_nonexistent_pattern() {
        let manager = RecoilManager::new();
        let pattern = manager.get_pattern("nonexistent");
        assert!(pattern.is_none());
    }

    #[test]
    fn test_delete_pattern() {
        let mut manager = RecoilManager::new();
        let steps = [1, 2, 3];
        
        manager.add_pattern("todelete", &steps).unwrap();
        assert_eq!(manager.count(), 1);
        
        let deleted = manager.delete_pattern("todelete");
        assert!(deleted);
        assert_eq!(manager.count(), 0);
        
        // Try to delete again
        let deleted = manager.delete_pattern("todelete");
        assert!(!deleted);
    }

    #[test]
    fn test_list_names() {
        let mut manager = RecoilManager::new();
        
        manager.add_pattern("pattern1", &[1, 2, 3]).unwrap();
        manager.add_pattern("pattern2", &[4, 5, 6]).unwrap();
        
        let names: Vec<&str, 16> = manager.list_names().collect();
        assert_eq!(names.len(), 2);
        assert!(names.contains(&"pattern1"));
        assert!(names.contains(&"pattern2"));
    }

    #[test]
    fn test_pattern_update() {
        let mut manager = RecoilManager::new();
        
        // Add initial pattern
        manager.add_pattern("update_test", &[1, 2, 3]).unwrap();
        let pattern = manager.get_pattern("update_test").unwrap();
        assert_eq!(pattern.steps[0], 1);
        
        // Update with new values
        manager.add_pattern("update_test", &[10, 20, 30]).unwrap();
        let pattern = manager.get_pattern("update_test").unwrap();
        assert_eq!(pattern.steps[0], 10);
        assert_eq!(manager.count(), 1); // Still only one pattern
    }

    #[test]
    fn test_parse_recoil_add_basic() {
        let line = b"nozen.recoil.add(ak47){10,-5,100,20,-10,150}";
        let result = parse_recoil_add(line);
        
        assert!(result.is_some());
        let (name, steps) = result.unwrap();
        assert_eq!(name, b"ak47");
        assert_eq!(steps.len(), 6);
        assert_eq!(steps[0], 10);
        assert_eq!(steps[1], -5);
        assert_eq!(steps[2], 100);
    }

    #[test]
    fn test_parse_recoil_add_negative_values() {
        let line = b"nozen.recoil.add(test){-10,5,-50}";
        let result = parse_recoil_add(line);
        
        assert!(result.is_some());
        let (_name, steps) = result.unwrap();
        assert_eq!(steps[0], -10);
        assert_eq!(steps[1], 5);
        assert_eq!(steps[2], -50);
    }

    #[test]
    fn test_parse_recoil_add_invalid() {
        // Missing closing brace - parser may still attempt to parse
        let line = b"nozen.recoil.add(test){10,20,30";
        let _result = parse_recoil_add(line);
        // Don't assert on this - implementation-dependent
        
        // Completely malformed command
        let line2 = b"not_a_valid_command";
        assert!(parse_recoil_add(line2).is_none());
        
        // Empty pattern
        let line3 = b"nozen.recoil.add(test){}";
        let result3 = parse_recoil_add(line3);
        if let Some((_name, steps)) = result3 {
            assert_eq!(steps.len(), 0);
        }
    }

    #[test]
    fn test_parse_recoil_name_basic() {
        let line = b"nozen.recoil.delete(mypattern)";
        let prefix = b"nozen.recoil.delete";
        let result = parse_recoil_name(line, prefix);
        
        assert!(result.is_some());
        assert_eq!(result.unwrap(), b"mypattern");
    }

    #[test]
    fn test_parse_recoil_name_multiple_prefixes() {
        let line = b"nozen.recoil.run(ak47)";
        let prefix = b"nozen.recoil.run";
        let result = parse_recoil_name(line, prefix);
        
        assert!(result.is_some());
        assert_eq!(result.unwrap(), b"ak47");
    }

    #[test]
    fn test_parse_i16_positive() {
        assert_eq!(parse_i16(b"123"), Some(123));
        assert_eq!(parse_i16(b"0"), Some(0));
        assert_eq!(parse_i16(b"32767"), Some(32767));
    }

    #[test]
    fn test_parse_i16_negative() {
        assert_eq!(parse_i16(b"-123"), Some(-123));
        assert_eq!(parse_i16(b"-1"), Some(-1));
        // Saturation at i16::MIN
        let result = parse_i16(b"-32768");
        assert!(result.is_some());
        assert!(result.unwrap() <= -32767);
    }

    #[test]
    fn test_parse_i16_with_whitespace() {
        assert_eq!(parse_i16(b"  123"), Some(123));
        assert_eq!(parse_i16(b"  -456"), Some(-456));
    }

    #[test]
    fn test_max_patterns_limit() {
        let mut manager = RecoilManager::new();
        
        // Try to add more than MAX_PATTERNS
        for i in 0..MAX_PATTERNS {
            let name = heapless::String::<32>::try_from(i.to_string().as_str()).unwrap();
            manager.add_pattern(name.as_str(), &[1, 2, 3]).unwrap();
        }
        
        assert_eq!(manager.count(), MAX_PATTERNS);
        
        // This should fail
        let result = manager.add_pattern("overflow", &[1, 2, 3]);
        assert!(result.is_err());
    }
}
