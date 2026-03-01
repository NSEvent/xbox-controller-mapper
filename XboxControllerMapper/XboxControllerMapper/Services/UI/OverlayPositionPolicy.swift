import CoreGraphics

/// Computes the cursor's screen position for overlay panel placement.
///
/// During Accessibility Zoom, system APIs (`NSEvent.mouseLocation`, `CGEvent.location`)
/// are unreliable — they oscillate between the virtual (absolute) and visual (physical)
/// cursor positions on alternating reads, causing overlay panels to flash between two
/// locations. Instead, this policy computes the physical display position mathematically
/// from the known cursor virtual position, zoom level, and screen geometry.
///
/// The zoom viewport follows the cursor but clamps at screen edges:
///   - In the center of the screen the cursor appears at physical center
///   - Near edges the cursor shifts toward the edge of the physical display
struct OverlayPositionPolicy {

    /// Returns the cursor location in NS screen coordinates for overlay panel placement.
    ///
    /// - Parameters:
    ///   - zoomActive: Whether Accessibility Zoom is currently enabled
    ///   - zoomLevel: The current zoom magnification (1.0 = no zoom, 2.0 = 2×, etc.)
    ///   - trackedCursorPosition: The cursor's absolute position in CG coordinates
    ///     (top-left origin, +Y down), as maintained by InputSimulator. May be nil if
    ///     the cursor hasn't been moved by the controller yet.
    ///   - fallbackCursorLocation: Position from `NSEvent.mouseLocation` (NS coords).
    ///     Only used when zoom is inactive or no tracked position is available at zoom 1×.
    ///   - screenFrame: The main screen's frame in NS coordinates (`NSScreen.main.frame`)
    static func cursorScreenPosition(
        zoomActive: Bool,
        zoomLevel: CGFloat,
        trackedCursorPosition: CGPoint?,
        fallbackCursorLocation: CGPoint,
        screenFrame: CGRect
    ) -> CGPoint {
        // When zoom is not active or effectively 1×, system APIs are reliable
        guard zoomActive, zoomLevel > 1.0 else {
            return fallbackCursorLocation
        }

        // When zoom is active but we have no tracked position (cursor hasn't been
        // moved by the controller), approximate as screen center since the zoom
        // viewport follows the cursor
        guard let tracked = trackedCursorPosition else {
            return CGPoint(x: screenFrame.midX, y: screenFrame.midY)
        }

        let screenW = screenFrame.width
        let screenH = screenFrame.height

        // The zoom viewport shows a (screenW/zoom × screenH/zoom) region of the
        // virtual screen, centered on the cursor — but clamped so the viewport
        // never extends past screen edges.
        let halfViewW = screenW / (2 * zoomLevel)
        let halfViewH = screenH / (2 * zoomLevel)
        let viewportCenterX = max(halfViewW, min(screenW - halfViewW, tracked.x))
        let viewportCenterY = max(halfViewH, min(screenH - halfViewH, tracked.y))

        // Map from virtual position to physical display position:
        //   physical = (virtual - viewportCenter) × zoom + screenCenter
        let physicalX = (tracked.x - viewportCenterX) * zoomLevel + screenW / 2
        let physicalY = (tracked.y - viewportCenterY) * zoomLevel + screenH / 2

        // Convert from CG physical (top-left origin) to NS screen coords (bottom-left origin)
        return CGPoint(
            x: screenFrame.origin.x + physicalX,
            y: screenFrame.origin.y + screenFrame.height - physicalY
        )
    }
}
