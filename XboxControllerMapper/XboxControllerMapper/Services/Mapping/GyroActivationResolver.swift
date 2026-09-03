import Foundation
import CoreGraphics

/// The three bindable gyro-control actions (virtual — they emit no OS key events).
enum GyroButtonAction: Equatable {
    /// Tap: flip the gyro toggle latch on/off.
    case toggle
    /// Gyro active while the button is held.
    case hold
    /// Gyro suppressed while the button is held (ratchet).
    case pause

    init?(keyCode: CGKeyCode) {
        switch keyCode {
        case KeyCodeMapping.gyroToggle: self = .toggle
        case KeyCodeMapping.gyroHold: self = .hold
        case KeyCodeMapping.gyroPause: self = .pause
        default: return nil
        }
    }
}

/// Decides whether gyro aiming drives the mouse this tick.
///
/// Pure function of the profile's activation mode plus the engine's gyro state
/// (toggle latch, held Gyro Hold / Gyro Pause buttons) and the focus-modifier
/// state. Called from the joystick poll loop; also the unit-test surface for
/// activation semantics.
enum GyroActivationResolver {
    /// - Parameters:
    ///   - mode: The profile's `gyroActivationMode`.
    ///   - isFocusActive: Whether the focus-mode modifier is currently held.
    ///   - toggledOn: The latch flipped by the Gyro Toggle action. Initial value
    ///     comes from `mode.initialToggledOn` (true only for `.alwaysOn`).
    ///   - holdButtonsDown: Any button with a Gyro Hold mapping is held.
    ///   - pauseButtonsDown: Any button with a Gyro Pause mapping is held.
    static func isActive(
        mode: GyroActivationMode,
        isFocusActive: Bool,
        toggledOn: Bool,
        holdButtonsDown: Bool,
        pauseButtonsDown: Bool
    ) -> Bool {
        // Ratchet always wins: pausing exists so the user can reposition the
        // controller without the cursor moving, no matter what else is active.
        guard !pauseButtonsDown else { return false }

        let base: Bool
        switch mode {
        case .focusModifier:
            // Legacy behavior, with the toggle latch as an additive on-switch.
            base = isFocusActive || toggledOn
        case .alwaysOn:
            // Latch starts true; Gyro Toggle can park it off (kill switch).
            base = toggledOn
        case .gyroButton:
            // Latch starts false; only Gyro Toggle / Gyro Hold activate.
            base = toggledOn
        }
        return base || holdButtonsDown
    }
}
