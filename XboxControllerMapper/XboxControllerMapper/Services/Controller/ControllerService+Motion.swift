import Foundation
import GameController

private enum SteamGyroBias {
	static let calibrationFrames = 60
	static let stableDeltaThresholdCounts = 1_000.0
	static let calibrationMagnitudeLimitCounts = 8_000.0
	static let recenterResidualThresholdCounts = 220.0
	static let outputZeroThresholdCounts = 90.0
	static let recenterAlpha = 0.02
}

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

	nonisolated func processSteamMotion(
		_ motion: SteamControllerMotionReport,
		uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
	) {
        let shouldProcessMotion = storage.lock.withLock { storage.motionInputEnabled }
        PerformanceProbe.shared.recordMotionCallback(rawOnly: !shouldProcessMotion)
        guard shouldProcessMotion else { return }

        let rawPitchCounts = Double(motion.gyroX)
		let rawRollCounts = -Double(motion.gyroY)
		let rawYawCounts = Double(motion.gyroZ) * Config.steamGyroAimingYawBlend

        let (pitchCounts, rollCounts): (Double, Double) = storage.lock.withLock {
			if uptime < storage.steamGyroBiasCalibrationNotBefore {
				return (0, 0)
			}
			guard let lastRawPitch = storage.steamGyroLastRawPitch,
				  let lastRawRoll = storage.steamGyroLastRawRoll,
				  let lastRawYaw = storage.steamGyroLastRawYaw else {
				storage.steamGyroLastRawPitch = rawPitchCounts
				storage.steamGyroLastRawRoll = rawRollCounts
				storage.steamGyroLastRawYaw = rawYawCounts
				return (0, 0)
			}

			let rawDelta = Self.steamGyroVectorMagnitude(
				rawPitchCounts - lastRawPitch,
				rawRollCounts - lastRawRoll,
				rawYawCounts - lastRawYaw
			)
			let rawMagnitude = Self.steamGyroVectorMagnitude(rawPitchCounts, rawRollCounts, rawYawCounts)
			storage.steamGyroLastRawPitch = rawPitchCounts
			storage.steamGyroLastRawRoll = rawRollCounts
			storage.steamGyroLastRawYaw = rawYawCounts

			if storage.steamGyroBiasSampleCount < SteamGyroBias.calibrationFrames {
				guard rawDelta <= SteamGyroBias.stableDeltaThresholdCounts,
					  rawMagnitude <= SteamGyroBias.calibrationMagnitudeLimitCounts else {
					resetSteamGyroBiasCalibrationSamplesLocked()
					return (0, 0)
				}

				storage.steamGyroPitchBiasSum += rawPitchCounts
				storage.steamGyroRollBiasSum += rawRollCounts
				storage.steamGyroYawBiasSum += rawYawCounts
				storage.steamGyroBiasSampleCount += 1
				if storage.steamGyroBiasSampleCount == SteamGyroBias.calibrationFrames {
					storage.steamGyroPitchBias = storage.steamGyroPitchBiasSum / Double(SteamGyroBias.calibrationFrames)
					storage.steamGyroRollBias = storage.steamGyroRollBiasSum / Double(SteamGyroBias.calibrationFrames)
					storage.steamGyroYawBias = storage.steamGyroYawBiasSum / Double(SteamGyroBias.calibrationFrames)
				}
				return (0, 0)
			}

			var correctedPitch = rawPitchCounts - storage.steamGyroPitchBias
			var correctedRoll = rawRollCounts - storage.steamGyroRollBias
			var correctedYaw = rawYawCounts - storage.steamGyroYawBias
			let residualMagnitude = Self.steamGyroVectorMagnitude(correctedPitch, correctedRoll, correctedYaw)
			if rawDelta <= SteamGyroBias.stableDeltaThresholdCounts,
			   residualMagnitude <= SteamGyroBias.recenterResidualThresholdCounts {
				storage.steamGyroPitchBias += correctedPitch * SteamGyroBias.recenterAlpha
				storage.steamGyroRollBias += correctedRoll * SteamGyroBias.recenterAlpha
				storage.steamGyroYawBias += correctedYaw * SteamGyroBias.recenterAlpha
				correctedPitch = rawPitchCounts - storage.steamGyroPitchBias
				correctedRoll = rawRollCounts - storage.steamGyroRollBias
				correctedYaw = rawYawCounts - storage.steamGyroYawBias
			}
			if Self.steamGyroVectorMagnitude(correctedPitch, correctedRoll, correctedYaw) <= SteamGyroBias.outputZeroThresholdCounts {
				return (0, 0)
			}

			return (correctedPitch, Self.steamHorizontalAimRate(rollAxis: correctedRoll, yawAxis: correctedYaw))
        }
        if pitchCounts == 0 && rollCounts == 0 { return }

        let pitch = Self.steamGyroRotationRate(
            counts: pitchCounts,
            multiplier: Config.steamGyroAimingSensitivityMultiplier
        )
        let roll = Self.steamGyroRotationRate(
            counts: rollCounts,
            multiplier: Config.steamGyroAimingSensitivityMultiplier
        )
        let gesturePitch = Self.steamGyroRotationRate(
            counts: pitchCounts,
            multiplier: Config.steamGyroGestureSensitivityMultiplier
        )
        let gestureRoll = Self.steamGyroRotationRate(
            counts: rollCounts,
            multiplier: Config.steamGyroGestureSensitivityMultiplier
        )

        storage.lock.lock()
        storage.motionPitchAccum += pitch
        storage.motionRollAccum += roll
        storage.motionSampleCount += 1
        storage.lock.unlock()

        processMotionUpdate(pitchVelocity: gesturePitch, rollVelocity: gestureRoll)
    }

	nonisolated func clearAccumulatedMotionRates() {
		storage.lock.withLock {
			clearAccumulatedMotionRatesLocked()
		}
	}

	nonisolated func prepareForGyroAimingActivation(
		calibrationDelay: TimeInterval = 0,
		now: TimeInterval = ProcessInfo.processInfo.systemUptime
		) {
			storage.lock.withLock {
				clearAccumulatedMotionRatesLocked()
				if storage.isSteamController {
					if storage.steamGyroBiasSampleCount < SteamGyroBias.calibrationFrames {
						resetSteamGyroBiasStateLocked()
					}
					storage.steamGyroBiasCalibrationNotBefore = calibrationDelay > 0
						? now + calibrationDelay
						: 0
				}
			}
		}

    nonisolated static func steamGyroRotationRate(counts: Double, multiplier: Double) -> Double {
        counts * (Double.pi / 32768.0) * multiplier
    }

    nonisolated static func steamHorizontalAimRate(gyroY: Int16, gyroZ: Int16) -> Double {
        let rollAxis = -Double(gyroY)
        let yawAxis = Double(gyroZ) * Config.steamGyroAimingYawBlend
		return steamHorizontalAimRate(rollAxis: rollAxis, yawAxis: yawAxis)
    }

    nonisolated static func steamHorizontalAimRate(rollAxis: Double, yawAxis: Double) -> Double {
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
		clearAccumulatedMotionRatesLocked()
        storage.ds4GyroPitchBiasSum = 0
        storage.ds4GyroRollBiasSum = 0
        storage.ds4GyroBiasSampleCount = 0
        storage.ds4GyroPitchBias = 0
        storage.ds4GyroRollBias = 0
		resetSteamGyroBiasStateLocked()
	}

	nonisolated private func clearAccumulatedMotionRatesLocked() {
		storage.motionPitchAccum = 0
		storage.motionRollAccum = 0
		storage.motionSampleCount = 0
	}

	nonisolated private func resetSteamGyroBiasStateLocked() {
		resetSteamGyroBiasCalibrationSamplesLocked()
        storage.steamGyroPitchBias = 0
        storage.steamGyroRollBias = 0
		storage.steamGyroYawBias = 0
		storage.steamGyroBiasCalibrationNotBefore = 0
		storage.steamGyroLastRawPitch = nil
		storage.steamGyroLastRawRoll = nil
		storage.steamGyroLastRawYaw = nil
    }

	nonisolated private func resetSteamGyroBiasCalibrationSamplesLocked() {
		storage.steamGyroPitchBiasSum = 0
		storage.steamGyroRollBiasSum = 0
		storage.steamGyroYawBiasSum = 0
		storage.steamGyroBiasSampleCount = 0
	}

	nonisolated private static func steamGyroVectorMagnitude(_ x: Double, _ y: Double, _ z: Double) -> Double {
		sqrt(x * x + y * y + z * z)
	}
}
