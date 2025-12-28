/// Mouse Position State Tracking
/// Tracks absolute mouse position for moveto() commands

pub struct MouseState {
    pub x: i16,
    pub y: i16,
}

impl MouseState {
    pub fn new() -> Self {
        MouseState { x: 0, y: 0 }
    }

    /// Update position with relative movement
    pub fn update_relative(&mut self, dx: i16, dy: i16) {
        self.x = self.x.saturating_add(dx);
        self.y = self.y.saturating_add(dy);
    }

    /// Calculate delta to reach absolute position
    pub fn delta_to(&self, target_x: i16, target_y: i16) -> (i16, i16) {
        (target_x - self.x, target_y - self.y)
    }

    /// Set absolute position (after moveto)
    pub fn set_position(&mut self, x: i16, y: i16) {
        self.x = x;
        self.y = y;
    }

    /// Get current position
    pub fn position(&self) -> (i16, i16) {
        (self.x, self.y)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_mouse_state_new() {
        let state = MouseState::new();
        assert_eq!(state.x, 0);
        assert_eq!(state.y, 0);
        assert_eq!(state.position(), (0, 0));
    }

    #[test]
    fn test_update_relative_positive() {
        let mut state = MouseState::new();
        state.update_relative(10, 20);
        assert_eq!(state.position(), (10, 20));
        
        state.update_relative(5, 3);
        assert_eq!(state.position(), (15, 23));
    }

    #[test]
    fn test_update_relative_negative() {
        let mut state = MouseState::new();
        state.update_relative(-10, -5);
        assert_eq!(state.position(), (-10, -5));
        
        state.update_relative(5, 2);
        assert_eq!(state.position(), (-5, -3));
    }

    #[test]
    fn test_update_relative_saturation() {
        let mut state = MouseState::new();
        
        // Test positive saturation
        state.set_position(32760, 32760);
        state.update_relative(100, 100);
        assert_eq!(state.position(), (32767, 32767)); // Should saturate at i16::MAX
        
        // Test negative saturation
        state.set_position(-32760, -32760);
        state.update_relative(-100, -100);
        assert_eq!(state.position(), (-32768, -32768)); // Should saturate at i16::MIN
    }

    #[test]
    fn test_set_position() {
        let mut state = MouseState::new();
        state.set_position(100, 200);
        assert_eq!(state.position(), (100, 200));
        
        state.set_position(-50, -75);
        assert_eq!(state.position(), (-50, -75));
    }

    #[test]
    fn test_delta_to_basic() {
        let mut state = MouseState::new();
        state.set_position(10, 20);
        
        let (dx, dy) = state.delta_to(30, 50);
        assert_eq!(dx, 20); // 30 - 10
        assert_eq!(dy, 30); // 50 - 20
    }

    #[test]
    fn test_delta_to_negative() {
        let mut state = MouseState::new();
        state.set_position(100, 100);
        
        let (dx, dy) = state.delta_to(50, 25);
        assert_eq!(dx, -50); // 50 - 100
        assert_eq!(dy, -75); // 25 - 100
    }

    #[test]
    fn test_delta_to_zero() {
        let mut state = MouseState::new();
        state.set_position(50, 50);
        
        let (dx, dy) = state.delta_to(50, 50);
        assert_eq!(dx, 0);
        assert_eq!(dy, 0);
    }

    #[test]
    fn test_movement_sequence() {
        let mut state = MouseState::new();
        
        // Start at origin
        assert_eq!(state.position(), (0, 0));
        
        // Move right and down
        state.update_relative(10, 5);
        assert_eq!(state.position(), (10, 5));
        
        // Move left and up
        state.update_relative(-3, -2);
        assert_eq!(state.position(), (7, 3));
        
        // Jump to absolute position
        state.set_position(100, 100);
        assert_eq!(state.position(), (100, 100));
        
        // Calculate delta to new target
        let (dx, dy) = state.delta_to(150, 200);
        assert_eq!(dx, 50);
        assert_eq!(dy, 100);
        
        // Apply that delta
        state.update_relative(dx, dy);
        assert_eq!(state.position(), (150, 200));
    }

    #[test]
    fn test_extreme_positions() {
        let mut state = MouseState::new();
        
        state.set_position(i16::MAX, i16::MAX);
        assert_eq!(state.position(), (i16::MAX, i16::MAX));
        
        state.set_position(i16::MIN, i16::MIN);
        assert_eq!(state.position(), (i16::MIN, i16::MIN));
    }
}
