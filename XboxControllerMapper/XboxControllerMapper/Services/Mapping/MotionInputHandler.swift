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
    /// - Parameter consumingPress: when true (the orchestration intercept for a
    ///   primary button mapping), the press is marked consumed in the SAME locked
    ///   section as the gyro state change, so a concurrent transient reset can
    ///   never observe one without the other. Press-only contexts (chords,
    ///   sequences) leave it false — they manage their own press state.
    nonisolated func handleGyroActionPressed(
        _ button: ControllerButton,
        action: GyroButtonAction,
        consumingPress: Bool = false
    ) {
        switch action {
        case .toggle:
            let latchedOn = state.lock.withLock { () -> Bool in
                if consumingPress { _ = state.pressConsumedByAction.insert(button) }
                return state.toggleGyroLatchLocked()
            }
            inputLogService?.log(buttons: [button], type: .singlePress, action: latchedOn ? "Gyro On" : "Gyro Off")
        case .hold:
            state.lock.withLock {
                if consumingPress { _ = state.pressConsumedByAction.insert(button) }
                _ = state.gyroHoldButtons.insert(button)
            }
            inputLogService?.log(buttons: [button], type: .singlePress, action: "Gyro Hold")
        case .pause:
            state.lock.withLock {
                if consumingPress { _ = state.pressConsumedByAction.insert(button) }
                _ = state.gyroPauseButtons.insert(button)
            }
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

    /// "Pointer (Hold)": Wiimote tilt/IR pointer control while held. Engages
    /// on the first held binding, disengages when the last one releases —
    /// mirrors the gyro hold set so a disconnect-time synthetic release also
    /// cleans up.
    nonisolated func handleWiimotePointerPressed(_ button: ControllerButton, toggle: Bool = false) {
        state.lock.withLock {
            _ = state.pressConsumedByAction.insert(button)
            if toggle {
                state.wiimotePointerToggledOn.toggle()
            } else {
                _ = state.wiimotePointerButtons.insert(button)
            }
        }
        syncWiimotePointerEngagement()
        inputLogService?.log(buttons: [button], type: .singlePress, action: "Pointer")
    }

    /// Cheap enough to call unconditionally from the release chain.
    nonisolated func handleWiimotePointerReleased(_ button: ControllerButton) {
        let removed = state.lock.withLock {
            state.wiimotePointerButtons.remove(button) != nil
        }
        if removed { syncWiimotePointerEngagement() }
    }

    /// Re-align the service's pointer engagement after any state reset that
    /// clears wiimotePointerButtons out-of-band (profile switch, disconnect).
    /// Idempotent — disengage no-ops when already disengaged.
    nonisolated func syncWiimotePointerEngagement() {
        // Read the latest state when the main queue executes this update.
        // A queued press must never re-engage after disable/profile cleanup.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let engaged = self.state.lock.withLock {
                self.state.isEnabled && !self.state.isLocked
                    && (self.state.wiimotePointerToggledOn || !self.state.wiimotePointerButtons.isEmpty)
            }
            self.controllerService.setWiimotePointerEngaged(engaged)
        }
    }
}
