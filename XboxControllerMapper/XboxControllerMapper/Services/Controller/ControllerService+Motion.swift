import Foundation
import GameController

extension ControllerService {
    /// Enables gyroscope sensors and sets up motion gesture detection.
    /// Called from setupInputHandlers() for PlayStation controllers. For DualSense,
    /// motion data flows through the GameController framework (this handler).
    /// For DS4, GCMotion.rotationRate is always zero on macOS — DS4 motion is
    /// parsed from raw HID input reports in parseDualShock4Motion instead, so
    /// this handler is a no-op for DS4 but still installed to enable sensors.
    func setupMotionHandlers() {
        guard let controller = connectedController,
              let motion = controller.motion else { return }

        motion.valueChangedHandler = { [weak self] motion in
            guard let self = self else { return }
            let shouldProcessMotion = self.storage.lock.withLock { self.storage.motionInputEnabled }
            PerformanceProbe.shared.recordMotionCallback(rawOnly: !shouldProcessMotion)
            guard shouldProcessMotion else { return }
            let pitch = motion.rotationRate.x
            let roll = motion.rotationRate.z

            // DS4 reports zero through GCMotion; DS4 path uses HID parsing instead.
            if pitch == 0 && roll == 0 { return }

            self.storage.lock.lock()
            self.storage.motionPitchAccum += pitch
            self.storage.motionRollAccum += roll
            self.storage.motionSampleCount += 1
            self.storage.lock.unlock()

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

    nonisolated func processSteamMotion(_ motion: SteamControllerMotionReport) {
        let shouldProcessMotion = storage.lock.withLock { storage.motionInputEnabled }
        PerformanceProbe.shared.recordMotionCallback(rawOnly: !shouldProcessMotion)
        guard shouldProcessMotion else { return }

        let scale = (Double.pi / 32768.0) * Config.steamGyroAimingSensitivityMultiplier
        let rawPitch = Double(motion.gyroX) * scale
        let rawRoll = Self.steamHorizontalAimRate(gyroY: motion.gyroY, gyroZ: motion.gyroZ) * scale

        let biasCalibrationFrames = 60
        let (pitch, roll): (Double, Double) = storage.lock.withLock {
            if storage.steamGyroBiasSampleCount < biasCalibrationFrames {
                storage.steamGyroPitchBiasSum += rawPitch
                storage.steamGyroRollBiasSum += rawRoll
                storage.steamGyroBiasSampleCount += 1
                if storage.steamGyroBiasSampleCount == biasCalibrationFrames {
                    storage.steamGyroPitchBias = storage.steamGyroPitchBiasSum / Double(biasCalibrationFrames)
                    storage.steamGyroRollBias = storage.steamGyroRollBiasSum / Double(biasCalibrationFrames)
                }
                return (0, 0)
            }
            return (rawPitch - storage.steamGyroPitchBias, rawRoll - storage.steamGyroRollBias)
        }
        if pitch == 0 && roll == 0 { return }

        storage.lock.lock()
        storage.motionPitchAccum += pitch
        storage.motionRollAccum += roll
        storage.motionSampleCount += 1
        storage.lock.unlock()

        processMotionUpdate(pitchVelocity: pitch, rollVelocity: roll)
    }

    nonisolated static func steamHorizontalAimRate(gyroY: Int16, gyroZ: Int16) -> Double {
        let rollAxis = -Double(gyroY)
        let yawAxis = Double(gyroZ) * Config.steamGyroAimingYawBlend

        guard rollAxis != 0, yawAxis != 0 else {
            return rollAxis + yawAxis
        }

        if (rollAxis > 0) == (yawAxis > 0) {
            return rollAxis + yawAxis
        }

        return abs(rollAxis) >= abs(yawAxis) ? rollAxis : yawAxis
    }

    func setMotionSensorsActive(_ active: Bool) {
        guard let motion = connectedController?.motion else {
            guard threadSafeIsSteamController else { return }
            storage.lock.withLock {
                storage.motionInputEnabled = active
                if !active {
                    resetMotionStateLocked()
                }
            }
            if Config.performanceProbeEnabled {
                NSLog(
                    "[PerfProbe] motion_activation scenario=%@ requested=%d actual=%d",
                    Config.performanceScenarioLabel,
                    active ? 1 : 0,
                    active ? 1 : 0
                )
            }
            return
        }

        if motion.sensorsActive != active {
            motion.sensorsActive = active
        }

        storage.lock.withLock {
            storage.motionInputEnabled = active
        }

        if Config.performanceProbeEnabled {
            NSLog(
                "[PerfProbe] motion_activation scenario=%@ requested=%d actual=%d",
                Config.performanceScenarioLabel,
                active ? 1 : 0,
                motion.sensorsActive ? 1 : 0
            )
        }

        guard !active else { return }
        storage.lock.withLock {
            resetMotionStateLocked()
        }
    }

    /// Resets motion gesture state. Called from controllerDisconnected().
    /// Caller must hold storage.lock.
    func resetMotionStateLocked() {
        storage.motionInputEnabled = false
        storage.motionGestureDetector.reset()
        storage.motionPitchAccum = 0
        storage.motionRollAccum = 0
        storage.motionSampleCount = 0
        storage.ds4GyroPitchBiasSum = 0
        storage.ds4GyroRollBiasSum = 0
        storage.ds4GyroBiasSampleCount = 0
        storage.ds4GyroPitchBias = 0
        storage.ds4GyroRollBias = 0
        storage.steamGyroPitchBiasSum = 0
        storage.steamGyroRollBiasSum = 0
        storage.steamGyroBiasSampleCount = 0
        storage.steamGyroPitchBias = 0
        storage.steamGyroRollBias = 0
    }
}
