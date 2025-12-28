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
