import CoreGraphics

/// Filters the oscillating cursor position reported by NSEvent.mouseLocation during
/// Accessibility Zoom.
///
/// When Accessibility Zoom is active, `NSEvent.mouseLocation` alternates between two
/// positions on consecutive reads:
///   - **Virtual (absolute)**: The cursor's position in the unzoomed virtual screen
///   - **Physical (visual)**: Where the cursor actually appears on the zoomed display
///
/// Overlay panels (action feedback, focus ring) sit above the zoom layer and need
/// the physical position to track the cursor visually. This filter identifies virtual
/// readings by comparing them to the known tracked position, allowing callers to
/// discard them and use only physical readings.
struct CursorOscillationFilter {

    /// Determines if an NSEvent.mouseLocation reading is a "virtual" reading
    /// (matching the tracked absolute cursor position) rather than a "physical"
    /// reading (the actual visual cursor position on screen).
    ///
    /// - Parameters:
    ///   - mouseLocation: The value from `NSEvent.mouseLocation` (NS coordinates,
    ///     bottom-left origin).
    ///   - trackedCGPosition: The tracked cursor position in CG coordinates
    ///     (top-left origin, +Y down), as maintained by InputSimulator.
    ///   - screenHeight: The main screen height for CG → NS coordinate conversion.
    ///   - tolerance: Maximum distance (in points) for a reading to be considered
    ///     virtual. Defaults to 10.
    /// - Returns: `true` if the reading matches the virtual position (should be
    ///   discarded for overlay placement); `false` if it's a physical reading
    ///   (should be used).
    static func isVirtualReading(
        mouseLocation: CGPoint,
        trackedCGPosition: CGPoint,
        screenHeight: CGFloat,
        tolerance: CGFloat = 10
    ) -> Bool {
        // Convert tracked CG position to NS coordinates for comparison
        let virtualNS = CGPoint(
            x: trackedCGPosition.x,
            y: screenHeight - trackedCGPosition.y
        )
        return abs(mouseLocation.x - virtualNS.x) < tolerance
            && abs(mouseLocation.y - virtualNS.y) < tolerance
    }
}
