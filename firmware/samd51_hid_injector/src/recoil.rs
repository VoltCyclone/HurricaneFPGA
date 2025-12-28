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
