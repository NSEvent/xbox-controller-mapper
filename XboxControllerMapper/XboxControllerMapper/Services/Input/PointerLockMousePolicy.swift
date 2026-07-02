import Foundation
import CoreGraphics

/// How controller/touchpad mouse movement is posted when a game captures the mouse.
///
/// Browser pointer-lock games (Pointer Lock API) and native FPS games hide the
/// system cursor and consume relative mouse deltas for unlimited 360° aiming.
/// The absolute-position mouse path clamps to screen bounds, so aiming dies at
/// the screen edge. Relative mode instead posts delta-only mouse events at the
/// current cursor position: apps receive movement 1:1, the cursor stays pinned,
/// and pointer lock stays engaged.
enum PointerLockMouseMode: String, Codable, CaseIterable, Sendable {
    /// Relative movement while the system cursor is hidden (pointer lock hides it).
    case auto
    /// Never use relative movement (legacy absolute-only behavior).
    case off
    /// Always use relative movement. The cursor never moves from controller input;
    /// intended for per-app game profiles.
    case always

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .off: return "Off"
        case .always: return "Always"
        }
    }
}

/// Pure policy for when mouse movement should be posted as relative deltas.
struct PointerLockMousePolicy {
    /// Cursor-visibility is a WindowServer query; poll it at most this often.
    static let cursorVisibilityPollInterval: CFTimeInterval = 0.25

    /// Returns true when movement should bypass the absolute tracked/clamped path
    /// and post delta-only events.
    ///
    /// - Accessibility Zoom always wins: its viewport panning and IOHID click
    ///   targeting need the absolute path.
    /// - An active Universal Control relay session wins: edge handoff routes
    ///   movement to the remote Mac.
    /// - `appInitiatedCursorHide` guards the `auto` heuristic against the app's own
    ///   cursor hide (on-screen keyboard navigation mode), which would otherwise
    ///   read as a pointer-lock game. It does not suppress `always`.
    /// - `cursorVisible == nil` means detection is unavailable (symbol no longer
    ///   resolvable); `auto` then behaves like `off` and only `always` engages.
    static func shouldUseRelativeMovement(
        mode: PointerLockMouseMode,
        cursorVisible: Bool?,
        zoomActive: Bool,
        universalControlRelayActive: Bool,
        appInitiatedCursorHide: Bool
    ) -> Bool {
        guard !zoomActive, !universalControlRelayActive else { return false }
        switch mode {
        case .off:
            return false
        case .always:
            return true
        case .auto:
            return cursorVisible == false && !appInitiatedCursorHide
        }
    }

    /// Throttles the cursor-visibility poll to `cursorVisibilityPollInterval`.
    static func shouldRefreshCursorVisibility(
        now: CFTimeInterval,
        lastPoll: CFTimeInterval?
    ) -> Bool {
        guard let lastPoll else { return true }
        return now - lastPoll >= cursorVisibilityPollInterval
    }
}

/// Global cursor visibility via `CGCursorIsVisible`.
///
/// The function is marked unavailable in the macOS 26 SDK but is still exported
/// at runtime (CoreGraphics re-exports SkyLight's `SLCursorIsVisible`), so it is
/// resolved with `dlsym`. Verified 2026-07-02: it flips to hidden the moment a
/// browser engages the Pointer Lock API and restores on release. If Apple drops
/// the export, `isCursorVisible()` returns nil and auto-detection degrades to
/// the manual `always` mode.
enum CursorVisibility {
    private typealias CursorVisibleFn = @convention(c) () -> boolean_t

    private static let resolvedFn: CursorVisibleFn? = {
        for name in ["CGCursorIsVisible", "SLCursorIsVisible"] {
            if let symbol = dlsym(dlopen(nil, RTLD_NOW), name) {
                return unsafeBitCast(symbol, to: CursorVisibleFn.self)
            }
        }
        NSLog("[CursorVisibility] CGCursorIsVisible/SLCursorIsVisible unavailable - pointer-lock auto-detection disabled")
        return nil
    }()

    static var isDetectionSupported: Bool { resolvedFn != nil }

    /// nil when detection is unavailable on this OS.
    static func isCursorVisible() -> Bool? {
        guard let fn = resolvedFn else { return nil }
        return fn() != 0
    }
}
