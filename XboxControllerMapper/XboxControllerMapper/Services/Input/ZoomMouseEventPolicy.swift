import Foundation

/// Pure policy that determines how mouse events should be posted.
///
/// During Accessibility Zoom, mouse-down/up/drag events need
/// kIOHIDSetCursorPosition to keep click targeting correct without the zoom
/// compositor's software cursor flashing at the virtual/absolute position.
/// Plain mouse moves stay on the CGEvent path; Universal Control can at least
/// begin handoff there, while IOHID relative moves stay trapped on the local edge.
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

    /// Returns true when IOHIDPostEvent should force the cursor position.
    static func shouldSetCursorPositionInIOHIDEvent(zoomActive: Bool, category: MouseEventCategory) -> Bool {
        guard zoomActive else { return false }
        switch category {
        case .move:
            return false
        case .drag, .buttonDown, .buttonUp:
            return true
        }
    }
}
