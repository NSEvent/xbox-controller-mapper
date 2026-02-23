import Foundation
import GameController

extension ControllerService {
    /// Enables gyroscope sensors and sets up motion gesture detection.
    /// Called from setupInputHandlers() for DualSense controllers.
    func setupMotionHandlers() {
        guard let controller = connectedController,
              let motion = controller.motion else { return }

        motion.sensorsActive = true

        motion.valueChangedHandler = { [weak self] motion in
            guard let self = self else { return }
            let pitch = motion.rotationRate.x
            let roll = motion.rotationRate.z

            // Accumulate rates for gyro aiming (averaged by MappingEngine each poll tick)
            self.storage.lock.lock()
            self.storage.motionPitchAccum += pitch
            self.storage.motionRollAccum += roll
            self.storage.motionSampleCount += 1
            self.storage.lock.unlock()

            // X axis = pitch (tilt back/forward), Z axis = roll (steer left/right)
            self.processMotionUpdate(pitchVelocity: pitch, rollVelocity: roll)
        }
    }

    /// Peak-detection state machine for gyroscope snap gestures.
    /// Processes pitch (tilt) and roll (steer) axes independently via MotionGestureDetector.
    /// Runs on the GameController callback thread (nonisolated).
    nonisolated func processMotionUpdate(pitchVelocity: Double, rollVelocity: Double) {
        let now = ProcessInfo.processInfo.systemUptime

        storage.lock.lock()
        let gestures = storage.motionGestureDetector.processAll((pitchVelocity, rollVelocity), at: now)
        let callback = storage.onMotionGesture
        storage.lock.unlock()

        guard let callback = callback else { return }

        for gesture in gestures {
            callback(gesture)
        }
    }

    /// Resets motion gesture state. Called from controllerDisconnected().
    /// Caller must hold storage.lock.
    func resetMotionStateLocked() {
        storage.motionGestureDetector.reset()
        storage.motionPitchAccum = 0
        storage.motionRollAccum = 0
        storage.motionSampleCount = 0
    }
}
