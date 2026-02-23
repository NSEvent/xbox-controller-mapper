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
    /// Processes pitch (tilt) and roll (steer) axes independently.
    /// Runs on the GameController callback thread (nonisolated).
    nonisolated func processMotionUpdate(pitchVelocity: Double, rollVelocity: Double) {
        let now = ProcessInfo.processInfo.systemUptime

        storage.lock.lock()

        let pitchActivation = storage.gestureActivationThreshold
        let rollActivation = storage.gestureRollActivationThreshold
        let pitchMinPeak = storage.gestureMinPeakVelocity
        let rollMinPeak = storage.gestureRollMinPeakVelocity

        let pitchResult = processAxis(
            state: &storage.pitchGesture,
            velocity: pitchVelocity,
            activationThreshold: pitchActivation,
            now: now
        )
        let rollResult = processAxis(
            state: &storage.rollGesture,
            velocity: rollVelocity,
            activationThreshold: rollActivation,
            now: now
        )

        let callback = storage.onMotionGesture
        storage.lock.unlock()

        guard let callback = callback else { return }

        if let (peakVelocity, peakSign) = pitchResult,
           peakVelocity >= pitchMinPeak {
            let gestureType: MotionGestureType = peakSign > 0 ? .tiltBack : .tiltForward
            callback(gestureType)
        }

        if let (peakVelocity, peakSign) = rollResult,
           peakVelocity >= rollMinPeak {
            let gestureType: MotionGestureType = peakSign > 0 ? .steerLeft : .steerRight
            callback(gestureType)
        }
    }

    /// Runs the peak-detection state machine for a single axis.
    /// Caller must hold storage.lock.
    /// Returns (peakVelocity, peakSign) if a gesture completed, nil otherwise.
    nonisolated private func processAxis(
        state: inout ControllerStorage.AxisGestureState,
        velocity: Double,
        activationThreshold: Double,
        now: TimeInterval
    ) -> (Double, Double)? {
        let absVelocity = abs(velocity)

        switch state.state {
        case .idle:
            // Use a longer cooldown if this motion is in the opposite direction of the last gesture.
            // This prevents the return/recoil from triggering the reverse gesture.
            let currentSign: Double = velocity > 0 ? 1.0 : -1.0
            let isOppositeDirection = state.lastGestureSign != 0 && currentSign != state.lastGestureSign
            let requiredCooldown = isOppositeDirection
                ? storage.gestureOppositeDirectionCooldown
                : storage.gestureCooldown
            let cooldownElapsed = (now - state.lastGestureTime) >= requiredCooldown

            if absVelocity >= activationThreshold && cooldownElapsed {
                state.state = .tracking
                state.peakVelocity = absVelocity
                state.peakSign = currentSign
                state.startTime = now
            }
            return nil

        case .tracking:
            let duration = now - state.startTime

            // Discard if too slow (long, deliberate motion)
            if duration > Config.gestureMaxDuration {
                state.state = .idle
                return nil
            }

            // Update peak if velocity increased
            if absVelocity > state.peakVelocity {
                state.peakVelocity = absVelocity
                state.peakSign = velocity > 0 ? 1.0 : -1.0
            }

            // Check if velocity dropped below completion threshold
            let completionThreshold = state.peakVelocity * Config.gestureCompletionRatio
            if absVelocity < completionThreshold {
                let result = (state.peakVelocity, state.peakSign)

                // Enter settling state — wait for controller to calm down
                state.state = .settling
                state.lastGestureTime = now
                state.lastGestureSign = state.peakSign

                return result
            }

            return nil

        case .settling:
            // Wait for controller to return to near-rest before allowing new gestures.
            // Prevents the return/recoil motion from triggering the opposite gesture.
            if absVelocity < Config.gestureSettlingThreshold {
                let cooldownElapsed = (now - state.lastGestureTime) >= storage.gestureCooldown
                if cooldownElapsed {
                    state.state = .idle
                }
            }
            return nil
        }
    }

    /// Resets motion gesture state. Called from controllerDisconnected().
    /// Caller must hold storage.lock.
    func resetMotionStateLocked() {
        storage.pitchGesture = ControllerStorage.AxisGestureState()
        storage.rollGesture = ControllerStorage.AxisGestureState()
        storage.motionPitchAccum = 0
        storage.motionRollAccum = 0
        storage.motionSampleCount = 0
    }
}
