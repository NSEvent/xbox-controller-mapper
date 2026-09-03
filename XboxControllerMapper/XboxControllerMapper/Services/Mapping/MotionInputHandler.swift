import Foundation
import CoreGraphics

/// Handles motion gesture detection and execution (tilt/shake gestures).
///
/// Extracted from MappingEngine to reduce its responsibilities.
extension MappingEngine {

    /// Process a completed motion gesture from a supported controller gyroscope.
    /// - Precondition: Must be called on inputQueue
    nonisolated func processMotionGesture(_ gestureType: MotionGestureType) {
        dispatchPrecondition(condition: .onQueue(inputQueue))
        guard let profile = state.lock.withLock({
            guard state.isEnabled, !state.isLocked else { return nil as Profile? }
            return state.activeProfile
        }) else { return }

        // Look up gesture mapping
        guard let gestureMapping = profile.gestureMappings.first(where: { $0.gestureType == gestureType }),
              gestureMapping.hasAction else {
            return
        }

        // Execute the mapped action
        let button = gestureType.controllerButton
        mappingExecutor.executeAction(gestureMapping, for: button, profile: profile, logType: .gesture)

        // Play haptic feedback
        controllerService.playHaptic(
            intensity: Config.gestureHapticIntensity,
            sharpness: Config.gestureHapticSharpness,
            duration: Config.gestureHapticDuration,
            transient: true
        )
    }

    // MARK: - Gyro Control Actions (virtual — no OS key events)

    /// Handles a press on a Gyro Toggle / Gyro Hold / Gyro Pause mapping.
    /// The joystick poll loop picks up the state change via `GyroActivationResolver`
    /// on its next tick (including calibration + haptic on the activation edge).
    nonisolated func handleGyroActionPressed(_ button: ControllerButton, action: GyroButtonAction) {
        switch action {
        case .toggle:
            let latchedOn = state.lock.withLock { state.toggleGyroLatchLocked() }
            inputLogService?.log(buttons: [button], type: .singlePress, action: latchedOn ? "Gyro On" : "Gyro Off")
        case .hold:
            state.lock.withLock { _ = state.gyroHoldButtons.insert(button) }
            inputLogService?.log(buttons: [button], type: .singlePress, action: "Gyro Hold")
        case .pause:
            state.lock.withLock { _ = state.gyroPauseButtons.insert(button) }
            inputLogService?.log(buttons: [button], type: .singlePress, action: "Gyro Pause")
        }
    }

    /// Clears hold/pause membership on button release. Toggle is tap-latched, so
    /// release is a no-op for it. Cheap enough to call unconditionally from the
    /// release chain, mirroring the UI-overlay release handlers.
    nonisolated func handleGyroActionReleased(_ button: ControllerButton) {
        state.lock.withLock {
            state.gyroHoldButtons.remove(button)
            state.gyroPauseButtons.remove(button)
        }
    }
}
