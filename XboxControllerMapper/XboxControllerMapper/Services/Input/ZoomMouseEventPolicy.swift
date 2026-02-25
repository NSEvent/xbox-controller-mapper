import Foundation

/// Pure policy that determines whether mouse events should be posted via IOHIDPostEvent
/// (zoom-safe) or standard CGEvent during Accessibility Zoom.
///
/// During Accessibility Zoom, posting CGEvent mouse-down/up/drag events causes the zoom
/// compositor's software cursor to briefly flash at the virtual/absolute position. The flash
/// offset scales with zoom level. IOHIDPostEvent with kIOHIDSetCursorPosition avoids this
/// by delivering events at the IOKit level, below the zoom compositor.
///
/// Mouse-move events (.mouseMoved) do NOT cause the flash and can safely use CGEvent.
struct ZoomMouseEventPolicy {
    enum MouseEventCategory {
        case move       // .mouseMoved (no button held)
        case drag       // .leftMouseDragged, .rightMouseDragged, .otherMouseDragged
        case buttonDown // .leftMouseDown, .rightMouseDown, .otherMouseDown
        case buttonUp   // .leftMouseUp, .rightMouseUp, .otherMouseUp
    }

    /// Returns true if the event should be posted via IOHIDPostEvent instead of CGEvent.
    /// When false, the normal CGEvent path should be used.
    static func shouldUseIOHIDPostEvent(zoomActive: Bool, category: MouseEventCategory) -> Bool {
        guard zoomActive else { return false }
        switch category {
        case .move:
            return false
        case .drag, .buttonDown, .buttonUp:
            return true
        }
    }
}
