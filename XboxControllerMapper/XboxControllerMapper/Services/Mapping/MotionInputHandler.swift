import Foundation
import CoreGraphics

/// Handles DualSense motion gesture detection and execution (tilt/shake gestures).
///
/// Extracted from MappingEngine to reduce its responsibilities.
extension MappingEngine {

    /// Process a completed motion gesture from the DualSense gyroscope
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
}
