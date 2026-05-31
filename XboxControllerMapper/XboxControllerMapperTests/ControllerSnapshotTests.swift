import XCTest
import CoreGraphics
@testable import ControllerKeys

@MainActor
final class ControllerSnapshotTests: XCTestCase {
    private var controllerService: ControllerService!

    override func setUp() {
        super.setUp()
        controllerService = ControllerService(enableHardwareMonitoring: false)
    }

    override func tearDown() {
        controllerService.cleanup()
        controllerService = nil
        super.tearDown()
    }

    // MARK: - Default Values

    func testDefaultSnapshotHasZeroValues() {
        let snap = ControllerService.ControllerSnapshot()
        XCTAssertEqual(snap.leftStick, .zero)
        XCTAssertEqual(snap.rightStick, .zero)
        XCTAssertEqual(snap.leftTrigger, 0)
        XCTAssertEqual(snap.rightTrigger, 0)
        XCTAssertFalse(snap.hasMotion)
    }

    // MARK: - Value Correctness

    func testSnapshotCapturesStorageValues() {
        controllerService.storage.lock.lock()
        controllerService.storage.leftStick = CGPoint(x: 0.5, y: -0.3)
        controllerService.storage.rightStick = CGPoint(x: -0.7, y: 0.9)
        controllerService.storage.leftTrigger = 0.6
        controllerService.storage.rightTrigger = 0.85
        controllerService.storage.isDualSense = true
        controllerService.storage.lock.unlock()

        let snap = controllerService.snapshot()

        XCTAssertEqual(snap.leftStick.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(snap.leftStick.y, -0.3, accuracy: 0.001)
        XCTAssertEqual(snap.rightStick.x, -0.7, accuracy: 0.001)
        XCTAssertEqual(snap.rightStick.y, 0.9, accuracy: 0.001)
        XCTAssertEqual(snap.leftTrigger, 0.6, accuracy: 0.001)
        XCTAssertEqual(snap.rightTrigger, 0.85, accuracy: 0.001)
        XCTAssertTrue(snap.hasMotion)
    }

    func testSnapshotCapturesHasMotionFalseWhenNeitherFlagSet() {
        controllerService.storage.lock.lock()
        controllerService.storage.isDualSense = false
        controllerService.storage.isDualShock = false
        controllerService.storage.isSteamController = false
        controllerService.storage.lock.unlock()

        let snap = controllerService.snapshot()
        XCTAssertFalse(snap.hasMotion)
    }

    func testSnapshotReportsSteamControllerHasMotion() {
        controllerService.storage.lock.lock()
        controllerService.storage.isSteamController = true
        controllerService.storage.lock.unlock()

        let snap = controllerService.snapshot()
        XCTAssertTrue(snap.hasMotion)
        XCTAssertTrue(controllerService.threadSafeHasMotion)
    }

    func testSetMotionSensorsActiveSupportsSteamRawHIDController() {
        controllerService.storage.lock.lock()
        controllerService.storage.isSteamController = true
        controllerService.storage.lock.unlock()

        controllerService.setMotionSensorsActive(true)
        XCTAssertTrue(controllerService.storage.lock.withLock { controllerService.storage.motionInputEnabled })

        controllerService.setMotionSensorsActive(false)
        XCTAssertFalse(controllerService.storage.lock.withLock { controllerService.storage.motionInputEnabled })
    }

	func testGyroAimingActivationClearsStaleMotionAndResetsSteamBias() {
		controllerService.storage.lock.withLock {
			controllerService.storage.isSteamController = true
			controllerService.storage.motionInputEnabled = true
			controllerService.storage.motionPitchAccum = 12
			controllerService.storage.motionRollAccum = -9
			controllerService.storage.motionSampleCount = 30
			controllerService.storage.steamGyroPitchBiasSum = 120
			controllerService.storage.steamGyroRollBiasSum = -240
			controllerService.storage.steamGyroYawBiasSum = 360
			controllerService.storage.steamGyroBiasSampleCount = 12
			controllerService.storage.steamGyroPitchBias = 10
			controllerService.storage.steamGyroRollBias = -20
			controllerService.storage.steamGyroYawBias = 30
			controllerService.storage.steamGyroBiasCalibrationNotBefore = 25
			controllerService.storage.steamGyroLastRawPitch = 1_000
			controllerService.storage.steamGyroLastRawRoll = -1_000
			controllerService.storage.steamGyroLastRawYaw = 500
		}

		controllerService.prepareForGyroAimingActivation()

		let snapshot = controllerService.storage.lock.withLock {
			(
				pitchAccum: controllerService.storage.motionPitchAccum,
				rollAccum: controllerService.storage.motionRollAccum,
				sampleCount: controllerService.storage.motionSampleCount,
				pitchBiasSum: controllerService.storage.steamGyroPitchBiasSum,
				rollBiasSum: controllerService.storage.steamGyroRollBiasSum,
				yawBiasSum: controllerService.storage.steamGyroYawBiasSum,
				biasSampleCount: controllerService.storage.steamGyroBiasSampleCount,
				pitchBias: controllerService.storage.steamGyroPitchBias,
				rollBias: controllerService.storage.steamGyroRollBias,
				yawBias: controllerService.storage.steamGyroYawBias,
				calibrationNotBefore: controllerService.storage.steamGyroBiasCalibrationNotBefore,
				lastRawPitch: controllerService.storage.steamGyroLastRawPitch,
				lastRawRoll: controllerService.storage.steamGyroLastRawRoll,
				lastRawYaw: controllerService.storage.steamGyroLastRawYaw
			)
		}

		XCTAssertEqual(snapshot.pitchAccum, 0)
		XCTAssertEqual(snapshot.rollAccum, 0)
		XCTAssertEqual(snapshot.sampleCount, 0)
		XCTAssertEqual(snapshot.pitchBiasSum, 0)
		XCTAssertEqual(snapshot.rollBiasSum, 0)
		XCTAssertEqual(snapshot.yawBiasSum, 0)
		XCTAssertEqual(snapshot.biasSampleCount, 0)
		XCTAssertEqual(snapshot.pitchBias, 0)
		XCTAssertEqual(snapshot.rollBias, 0)
		XCTAssertEqual(snapshot.yawBias, 0)
		XCTAssertEqual(snapshot.calibrationNotBefore, 0)
		XCTAssertNil(snapshot.lastRawPitch)
		XCTAssertNil(snapshot.lastRawRoll)
		XCTAssertNil(snapshot.lastRawYaw)
	}

	func testGyroAimingActivationPreservesCalibratedSteamBias() {
		controllerService.storage.lock.withLock {
			controllerService.storage.isSteamController = true
			controllerService.storage.motionInputEnabled = true
			controllerService.storage.motionPitchAccum = 12
			controllerService.storage.motionRollAccum = -9
			controllerService.storage.motionSampleCount = 30
		}
		controllerService.prepareForGyroAimingActivation()

		let steadyMotion = steamMotion(gyroX: -1_400, gyroY: 900, gyroZ: -600)
		for _ in 0..<61 {
			controllerService.processSteamMotion(steadyMotion)
		}

		let calibrated = controllerService.storage.lock.withLock {
			(
				sampleCount: controllerService.storage.steamGyroBiasSampleCount,
				pitchBias: controllerService.storage.steamGyroPitchBias,
				rollBias: controllerService.storage.steamGyroRollBias,
				yawBias: controllerService.storage.steamGyroYawBias,
				lastRawPitch: controllerService.storage.steamGyroLastRawPitch,
				lastRawRoll: controllerService.storage.steamGyroLastRawRoll,
				lastRawYaw: controllerService.storage.steamGyroLastRawYaw
			)
		}

		controllerService.storage.lock.withLock {
			controllerService.storage.motionPitchAccum = 5
			controllerService.storage.motionRollAccum = -7
			controllerService.storage.motionSampleCount = 3
		}
		controllerService.prepareForGyroAimingActivation(calibrationDelay: 0.25, now: 100)

		let after = controllerService.storage.lock.withLock {
			(
				pitchAccum: controllerService.storage.motionPitchAccum,
				rollAccum: controllerService.storage.motionRollAccum,
				motionSampleCount: controllerService.storage.motionSampleCount,
				sampleCount: controllerService.storage.steamGyroBiasSampleCount,
				pitchBias: controllerService.storage.steamGyroPitchBias,
				rollBias: controllerService.storage.steamGyroRollBias,
				yawBias: controllerService.storage.steamGyroYawBias,
				calibrationNotBefore: controllerService.storage.steamGyroBiasCalibrationNotBefore,
				lastRawPitch: controllerService.storage.steamGyroLastRawPitch,
				lastRawRoll: controllerService.storage.steamGyroLastRawRoll,
				lastRawYaw: controllerService.storage.steamGyroLastRawYaw
			)
		}

		XCTAssertEqual(calibrated.sampleCount, 60)
		XCTAssertEqual(after.pitchAccum, 0)
		XCTAssertEqual(after.rollAccum, 0)
		XCTAssertEqual(after.motionSampleCount, 0)
		XCTAssertEqual(after.sampleCount, calibrated.sampleCount)
		XCTAssertEqual(after.pitchBias, calibrated.pitchBias, accuracy: 0.0001)
		XCTAssertEqual(after.rollBias, calibrated.rollBias, accuracy: 0.0001)
		XCTAssertEqual(after.yawBias, calibrated.yawBias, accuracy: 0.0001)
		XCTAssertEqual(after.calibrationNotBefore, 100.25, accuracy: 0.0001)
		XCTAssertEqual(after.lastRawPitch, calibrated.lastRawPitch)
		XCTAssertEqual(after.lastRawRoll, calibrated.lastRawRoll)
		XCTAssertEqual(after.lastRawYaw, calibrated.lastRawYaw)
	}

	func testSteamGyroCalibrationSuppressesSteadyOffset() {
		controllerService.storage.lock.withLock {
			controllerService.storage.isSteamController = true
			controllerService.storage.motionInputEnabled = true
		}
		controllerService.prepareForGyroAimingActivation()

		let steadyMotion = steamMotion(gyroX: -1_400, gyroY: 900, gyroZ: -600)
		for _ in 0..<60 {
			controllerService.processSteamMotion(steadyMotion)
		}
		for _ in 0..<10 {
			controllerService.processSteamMotion(steadyMotion)
		}

		let rates = controllerService.consumeAverageMotionRates()
		XCTAssertEqual(rates.pitch, 0, accuracy: 0.0001)
		XCTAssertEqual(rates.roll, 0, accuracy: 0.0001)
	}

	func testSteamGyroCalibrationIgnoresFocusEntryHapticWindow() {
		controllerService.storage.lock.withLock {
			controllerService.storage.isSteamController = true
			controllerService.storage.motionInputEnabled = true
		}

		controllerService.prepareForGyroAimingActivation(calibrationDelay: 0.25, now: 100)

		let hapticContaminatedMotion = steamMotion(gyroX: -12_000, gyroY: -10_000, gyroZ: 8_000)
		for _ in 0..<30 {
			controllerService.processSteamMotion(hapticContaminatedMotion, uptime: 100.1)
		}

		let calibrationState = controllerService.storage.lock.withLock {
			(
				sampleCount: controllerService.storage.steamGyroBiasSampleCount,
				pitchBiasSum: controllerService.storage.steamGyroPitchBiasSum,
				rollBiasSum: controllerService.storage.steamGyroRollBiasSum,
				yawBiasSum: controllerService.storage.steamGyroYawBiasSum
			)
		}
		XCTAssertEqual(calibrationState.sampleCount, 0)
		XCTAssertEqual(calibrationState.pitchBiasSum, 0)
		XCTAssertEqual(calibrationState.rollBiasSum, 0)
		XCTAssertEqual(calibrationState.yawBiasSum, 0)

		let steadyMotion = steamMotion(gyroX: -1_400, gyroY: 900, gyroZ: -600)
		for _ in 0..<60 {
			controllerService.processSteamMotion(steadyMotion, uptime: 100.3)
		}
		for _ in 0..<10 {
			controllerService.processSteamMotion(steadyMotion, uptime: 100.5)
		}

		let rates = controllerService.consumeAverageMotionRates()
		XCTAssertEqual(rates.pitch, 0, accuracy: 0.0001)
		XCTAssertEqual(rates.roll, 0, accuracy: 0.0001)
	}

	func testSteamGyroCalibrationRejectsMovingStartupFrames() {
		controllerService.storage.lock.withLock {
			controllerService.storage.isSteamController = true
			controllerService.storage.motionInputEnabled = true
		}
		controllerService.prepareForGyroAimingActivation()

		let movingMotion = steamMotion(gyroX: -12_000, gyroY: -10_000, gyroZ: 8_000)
		for _ in 0..<80 {
			controllerService.processSteamMotion(movingMotion)
		}

		let calibrationState = controllerService.storage.lock.withLock {
			(
				sampleCount: controllerService.storage.steamGyroBiasSampleCount,
				pitchBiasSum: controllerService.storage.steamGyroPitchBiasSum,
				rollBiasSum: controllerService.storage.steamGyroRollBiasSum,
				yawBiasSum: controllerService.storage.steamGyroYawBiasSum
			)
		}
		XCTAssertEqual(calibrationState.sampleCount, 0)
		XCTAssertEqual(calibrationState.pitchBiasSum, 0)
		XCTAssertEqual(calibrationState.rollBiasSum, 0)
		XCTAssertEqual(calibrationState.yawBiasSum, 0)

		let steadyMotion = steamMotion(gyroX: -1_400, gyroY: 900, gyroZ: -600)
		for _ in 0..<61 {
			controllerService.processSteamMotion(steadyMotion)
		}
		for _ in 0..<10 {
			controllerService.processSteamMotion(steadyMotion)
		}

		let rates = controllerService.consumeAverageMotionRates()
		XCTAssertEqual(rates.pitch, 0, accuracy: 0.0001)
		XCTAssertEqual(rates.roll, 0, accuracy: 0.0001)
	}

	func testSteamGyroDoesNotSuppressIntentionalMotionAfterCalibration() {
		controllerService.storage.lock.withLock {
			controllerService.storage.isSteamController = true
			controllerService.storage.motionInputEnabled = true
		}
		controllerService.prepareForGyroAimingActivation()

		let steadyMotion = steamMotion(gyroX: -1_400, gyroY: 900, gyroZ: -600)
		for _ in 0..<61 {
			controllerService.processSteamMotion(steadyMotion)
		}

		controllerService.processSteamMotion(steamMotion(gyroX: -3_400, gyroY: 900, gyroZ: -600))
		var rates = controllerService.consumeAverageMotionRates()
		XCTAssertLessThan(rates.pitch, 0)
		XCTAssertEqual(rates.roll, 0, accuracy: 0.0001)

		controllerService.processSteamMotion(steamMotion(gyroX: 600, gyroY: 900, gyroZ: -600))
		rates = controllerService.consumeAverageMotionRates()
		XCTAssertGreaterThan(rates.pitch, 0)
		XCTAssertEqual(rates.roll, 0, accuracy: 0.0001)

		controllerService.processSteamMotion(steamMotion(gyroX: -1_400, gyroY: -1_100, gyroZ: -600))
		rates = controllerService.consumeAverageMotionRates()
		XCTAssertEqual(rates.pitch, 0, accuracy: 0.0001)
		XCTAssertGreaterThan(rates.roll, 0)

		controllerService.processSteamMotion(steamMotion(gyroX: -1_400, gyroY: 2_900, gyroZ: -600))
		rates = controllerService.consumeAverageMotionRates()
		XCTAssertEqual(rates.pitch, 0, accuracy: 0.0001)
		XCTAssertLessThan(rates.roll, 0)
	}

	func testSteamGyroBiasRecentersStationaryResidualDrift() {
		controllerService.storage.lock.withLock {
			controllerService.storage.isSteamController = true
			controllerService.storage.motionInputEnabled = true
		}
		controllerService.prepareForGyroAimingActivation()

		let steadyMotion = steamMotion(gyroX: -1_400, gyroY: 900, gyroZ: -600)
		for _ in 0..<61 {
			controllerService.processSteamMotion(steadyMotion)
		}

		let driftedMotion = steamMotion(gyroX: -1_340, gyroY: 850, gyroZ: -560)
		for _ in 0..<12 {
			controllerService.processSteamMotion(driftedMotion)
		}

		let rates = controllerService.consumeAverageMotionRates()
		let biasState = controllerService.storage.lock.withLock {
			(
				pitchBias: controllerService.storage.steamGyroPitchBias,
				rollBias: controllerService.storage.steamGyroRollBias,
				yawBias: controllerService.storage.steamGyroYawBias
			)
		}

		XCTAssertEqual(rates.pitch, 0, accuracy: 0.0001)
		XCTAssertEqual(rates.roll, 0, accuracy: 0.0001)
		XCTAssertGreaterThan(biasState.pitchBias, -1_400)
		XCTAssertGreaterThan(biasState.rollBias, -900)
		XCTAssertGreaterThan(biasState.yawBias, -450)
	}

	func testClearingAccumulatedMotionRatesDropsInactiveGyroBacklog() {
		controllerService.storage.lock.withLock {
			controllerService.storage.motionPitchAccum = 3
			controllerService.storage.motionRollAccum = -4
			controllerService.storage.motionSampleCount = 5
		}

		controllerService.clearAccumulatedMotionRates()

		let rates = controllerService.consumeAverageMotionRates()
		XCTAssertEqual(rates.pitch, 0)
		XCTAssertEqual(rates.roll, 0)
	}

    // MARK: - Atomicity (Conceptual)

    func testSnapshotValuesAreConsistent() {
        // Set both sticks together, verify snapshot captures both from the same lock acquisition
        controllerService.storage.lock.lock()
        controllerService.storage.leftStick = CGPoint(x: 1.0, y: 1.0)
        controllerService.storage.rightStick = CGPoint(x: -1.0, y: -1.0)
        controllerService.storage.leftTrigger = 1.0
        controllerService.storage.rightTrigger = 1.0
        controllerService.storage.lock.unlock()

        let snap = controllerService.snapshot()

        // All values should be from the same state — either all set or all zero
        XCTAssertEqual(snap.leftStick, CGPoint(x: 1.0, y: 1.0))
        XCTAssertEqual(snap.rightStick, CGPoint(x: -1.0, y: -1.0))
        XCTAssertEqual(snap.leftTrigger, 1.0)
        XCTAssertEqual(snap.rightTrigger, 1.0)
    }

    // MARK: - Value Type Semantics

    func testSnapshotIsValueType() {
        controllerService.storage.lock.lock()
        controllerService.storage.leftStick = CGPoint(x: 0.5, y: 0.5)
        controllerService.storage.lock.unlock()

        let snap = controllerService.snapshot()
        var copy = snap

        // Mutating the copy should not affect the original
        copy.leftStick = CGPoint(x: 0.9, y: 0.9)

        XCTAssertEqual(snap.leftStick.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(copy.leftStick.x, 0.9, accuracy: 0.001)
    }

    // MARK: - Backward Compatibility (Individual Accessors Still Work)

    func testIndividualAccessorsStillWork() {
        controllerService.storage.lock.lock()
        controllerService.storage.leftStick = CGPoint(x: 0.3, y: -0.4)
        controllerService.storage.rightStick = CGPoint(x: -0.6, y: 0.7)
        controllerService.storage.leftTrigger = 0.45
        controllerService.storage.rightTrigger = 0.55
        controllerService.storage.isSteamController = false
        controllerService.storage.isDualSense = true
        controllerService.storage.lock.unlock()

        // Verify individual threadSafe accessors still return correct values
        XCTAssertEqual(controllerService.threadSafeLeftStick.x, 0.3, accuracy: 0.001)
        XCTAssertEqual(controllerService.threadSafeLeftStick.y, -0.4, accuracy: 0.001)
        XCTAssertEqual(controllerService.threadSafeRightStick.x, -0.6, accuracy: 0.001)
        XCTAssertEqual(controllerService.threadSafeRightStick.y, 0.7, accuracy: 0.001)
        XCTAssertEqual(controllerService.threadSafeLeftTrigger, 0.45, accuracy: 0.001)
        XCTAssertEqual(controllerService.threadSafeRightTrigger, 0.55, accuracy: 0.001)
        XCTAssertTrue(controllerService.threadSafeIsDualSense)
    }

    func testSteamControllerMasksCachedPlayStationAndEliteFlags() {
        controllerService.storage.lock.lock()
        controllerService.storage.isSteamController = true
        controllerService.storage.isDualSense = true
        controllerService.storage.isDualSenseEdge = true
        controllerService.storage.isDualShock = true
        controllerService.storage.isXboxElite = true
        controllerService.storage.lock.unlock()

        XCTAssertTrue(controllerService.threadSafeIsSteamController)
        XCTAssertFalse(controllerService.threadSafeIsDualSense)
        XCTAssertFalse(controllerService.threadSafeIsDualSenseEdge)
        XCTAssertFalse(controllerService.threadSafeIsDualShock)
        XCTAssertFalse(controllerService.threadSafeIsPlayStation)
        XCTAssertFalse(controllerService.threadSafeIsXboxElite)
    }

    func testSteamTouchpadsUseSharedSurfaceForTwoPadPinch() {
        var gestures: [TouchpadGesture] = []
        controllerService.onTouchpadGesture = { gestures.append($0) }
        controllerService.storage.lock.withLock {
            controllerService.storage.isSteamController = true
        }

        controllerService.updateSteamTouchpad(side: .left, x: 0, y: 0, isTouching: true)
        controllerService.updateSteamTouchpad(side: .right, x: 0, y: 0, isTouching: true)
        controllerService.updateSteamTouchpad(side: .left, x: 0, y: 0, isTouching: true)
        controllerService.updateSteamTouchpad(side: .right, x: 0, y: 0, isTouching: true)
        controllerService.updateSteamTouchpad(side: .left, x: 0, y: 0, isTouching: true)
        controllerService.updateSteamTouchpad(side: .right, x: 0, y: 0, isTouching: true)
        gestures.removeAll()

        controllerService.updateSteamTouchpad(side: .left, x: -0.1, y: 0, isTouching: true)
        controllerService.updateSteamTouchpad(side: .right, x: 0.1, y: 0, isTouching: true)

        XCTAssertTrue(
            gestures.contains { $0.isPrimaryTouching && $0.isSecondaryTouching && $0.distanceDelta > 0.05 },
            "Moving fingers apart across both Steam pads should emit a pinch-out gesture"
        )
    }

    func testSteamRestingLeftTouchpadDoesNotSuppressRightTouchpadMouse() {
        var gestures: [TouchpadGesture] = []
        var movements: [CGPoint] = []
        controllerService.onTouchpadGesture = { gestures.append($0) }
        controllerService.onTouchpadMoved = { movements.append($0) }
        controllerService.storage.lock.withLock {
            controllerService.storage.isSteamController = true
        }

        for _ in 0..<3 {
            controllerService.updateSteamTouchpad(side: .left, x: 0, y: 0, isTouching: true)
            controllerService.updateSteamTouchpad(side: .right, x: 0, y: 0, isTouching: true)
        }
        gestures.removeAll()
        movements.removeAll()

        controllerService.updateSteamTouchpad(side: .left, x: -0.15, y: 0, isTouching: true)
        Thread.sleep(forTimeInterval: Config.touchpadSecondaryStaleInterval + 0.02)
        controllerService.updateSteamTouchpad(side: .right, x: 0.15, y: 0, isTouching: true)
        controllerService.updateSteamTouchpad(side: .right, x: 0.25, y: 0, isTouching: true)

        XCTAssertFalse(
            gestures.contains { $0.isPrimaryTouching && $0.isSecondaryTouching && abs($0.distanceDelta) > 0.01 },
            "A stale left-pad movement should not be treated as an active two-pad gesture"
        )
        XCTAssertFalse(
            movements.isEmpty,
            "Right-pad mouse movement should continue while the left finger is only resting"
        )
    }

	func testSteamLeftTouchpadJitterDoesNotSuppressRightTouchpadMouse() {
		var gestures: [TouchpadGesture] = []
		var movements: [CGPoint] = []
		controllerService.onTouchpadGesture = { gestures.append($0) }
		controllerService.onTouchpadMoved = { movements.append($0) }
		controllerService.storage.lock.withLock {
			controllerService.storage.isSteamController = true
		}

		for _ in 0..<3 {
			controllerService.updateSteamTouchpad(side: .left, x: 0, y: 0, isTouching: true)
			controllerService.updateSteamTouchpad(side: .right, x: 0, y: 0, isTouching: true)
		}
		gestures.removeAll()
		movements.removeAll()

		let jitter = Float(Config.steamTouchpadTwoPadGestureMovementDeadzone * 0.75)
		controllerService.updateSteamTouchpad(side: .left, x: jitter, y: 0, isTouching: true)
		controllerService.updateSteamTouchpad(side: .right, x: 0.15, y: 0, isTouching: true)
		controllerService.updateSteamTouchpad(side: .right, x: 0.25, y: 0, isTouching: true)

		XCTAssertTrue(
			gestures.isEmpty,
			"Small left-pad resting jitter should not enqueue inactive two-pad gesture callbacks"
		)
		XCTAssertFalse(
			movements.isEmpty,
			"Right-pad mouse movement should continue while the left pad only jitters"
		)
    }

	func testAppleTVRemoteCircularScrollWrapsAcrossNegativePi() {
		let previous = CGPoint(x: -0.80, y: 0.02)
		let current = CGPoint(x: -0.80, y: -0.02)

		let angleDelta = ControllerService.appleTVRemoteCircularScrollAngleDelta(
			previous: previous,
			current: current
		)

		XCTAssertNotNil(angleDelta)
		XCTAssertLessThan(abs(angleDelta ?? 0), 0.1)
		XCTAssertGreaterThan(angleDelta ?? 0, 0)
	}

	func testAppleTVRemoteCircularScrollEmitsAngleDeltaAndSuppressesMouseMovement() {
		var scrollDeltas: [CGFloat] = []
		var movements: [CGPoint] = []
		controllerService.onAppleTVRemoteCircularScroll = { scrollDeltas.append($0) }
		controllerService.onTouchpadMoved = { movements.append($0) }
		controllerService.storage.lock.withLock {
			controllerService.storage.isAppleTVRemote = true
		}

		controllerService.updateTouchpad(x: 0.80, y: 0.00, isTouching: true)
		controllerService.updateTouchpad(x: 0.80, y: 0.00, isTouching: true)
		controllerService.updateTouchpad(x: 0.80, y: 0.00, isTouching: true)
		controllerService.updateTouchpad(x: 0.78, y: 0.16, isTouching: true)

		XCTAssertEqual(scrollDeltas.count, 1)
		XCTAssertGreaterThan(scrollDeltas[0], 0)
		XCTAssertTrue(movements.isEmpty)
	}

	func testAppleTVRemoteCircularScrollKeepsOwnershipThroughCenterBrushUntilLift() {
		var scrollDeltas: [CGFloat] = []
		var movements: [CGPoint] = []
		controllerService.onAppleTVRemoteCircularScroll = { scrollDeltas.append($0) }
		controllerService.onTouchpadMoved = { movements.append($0) }
		controllerService.storage.lock.withLock {
			controllerService.storage.isAppleTVRemote = true
		}

		controllerService.updateTouchpad(x: 0.80, y: 0.00, isTouching: true)
		controllerService.updateTouchpad(x: 0.80, y: 0.00, isTouching: true)
		controllerService.updateTouchpad(x: 0.80, y: 0.00, isTouching: true)
		controllerService.updateTouchpad(x: 0.78, y: 0.16, isTouching: true)
		controllerService.updateTouchpad(x: 0.12, y: 0.04, isTouching: true)
		controllerService.updateTouchpad(x: 0.14, y: 0.05, isTouching: true)
		controllerService.updateTouchpad(x: 0.16, y: 0.06, isTouching: true)

		XCTAssertEqual(scrollDeltas.count, 1)
		XCTAssertTrue(
			movements.isEmpty,
			"An active circular scroll gesture should keep ownership through center brushes"
		)

		controllerService.updateTouchpad(x: 0, y: 0, isTouching: false)
		controllerService.updateTouchpad(x: 0.10, y: 0.10, isTouching: true)
		controllerService.updateTouchpad(x: 0.10, y: 0.10, isTouching: true)
		controllerService.updateTouchpad(x: 0.10, y: 0.10, isTouching: true)
		controllerService.updateTouchpad(x: 0.24, y: 0.10, isTouching: true)
		controllerService.updateTouchpad(x: 0.28, y: 0.10, isTouching: true)

		XCTAssertFalse(
			movements.isEmpty,
			"Mouse movement should be available again after touch-up starts a new touch session"
		)
	}

	func testAppleTVRemoteTouchStartingInsideDoesNotBecomeCircularScrollAfterMovingOutward() {
		var scrollDeltas: [CGFloat] = []
		var movements: [CGPoint] = []
		controllerService.onAppleTVRemoteCircularScroll = { scrollDeltas.append($0) }
		controllerService.onTouchpadMoved = { movements.append($0) }
		controllerService.storage.lock.withLock {
			controllerService.storage.isAppleTVRemote = true
		}

		controllerService.updateTouchpad(x: 0.10, y: 0.00, isTouching: true)
		controllerService.updateTouchpad(x: 0.10, y: 0.00, isTouching: true)
		controllerService.updateTouchpad(x: 0.10, y: 0.00, isTouching: true)
		controllerService.updateTouchpad(x: 0.35, y: 0.00, isTouching: true)
		controllerService.updateTouchpad(x: 0.60, y: 0.00, isTouching: true)
		controllerService.updateTouchpad(x: 0.75, y: 0.00, isTouching: true)
		controllerService.updateTouchpad(x: 0.72, y: 0.20, isTouching: true)
		controllerService.updateTouchpad(x: 0.66, y: 0.36, isTouching: true)

		XCTAssertTrue(
			scrollDeltas.isEmpty,
			"A touch that starts inside the clickpad should not switch to ring scroll after moving outward"
		)
		XCTAssertFalse(
			movements.isEmpty,
			"The same continuous inside-origin touch should keep controlling mouse movement"
		)
	}

	func testAppleTVRemoteCircularScrollDisabledKeepsOuterRingMouseMovement() {
		var scrollDeltas: [CGFloat] = []
		var movements: [CGPoint] = []
		controllerService.onAppleTVRemoteCircularScroll = { scrollDeltas.append($0) }
		controllerService.onTouchpadMoved = { movements.append($0) }
		controllerService.storage.lock.withLock {
			controllerService.storage.isAppleTVRemote = true
			controllerService.storage.appleTVRemoteCircularScrollEnabled = false
		}

		controllerService.updateTouchpad(x: 0.80, y: 0.00, isTouching: true)
		controllerService.updateTouchpad(x: 0.80, y: 0.00, isTouching: true)
		controllerService.updateTouchpad(x: 0.80, y: 0.00, isTouching: true)
		controllerService.updateTouchpad(x: 0.78, y: 0.16, isTouching: true)
		controllerService.updateTouchpad(x: 0.72, y: 0.30, isTouching: true)

		XCTAssertTrue(scrollDeltas.isEmpty)
		XCTAssertFalse(
			movements.isEmpty,
			"Disabling Apple TV edge scroll should let outer-ring swipes keep moving the mouse"
		)
	}

	func testAppleTVRemoteRadialOuterMovementDoesNotCircularScroll() {
		let angleDelta = ControllerService.appleTVRemoteCircularScrollAngleDelta(
			previous: CGPoint(x: 0.65, y: 0.00),
			current: CGPoint(x: 0.85, y: 0.00)
		)

		XCTAssertNil(angleDelta)
	}

    func testSnapshotAndIndividualAccessorsAgree() {
        controllerService.storage.lock.lock()
        controllerService.storage.leftStick = CGPoint(x: 0.12, y: 0.34)
        controllerService.storage.rightStick = CGPoint(x: 0.56, y: 0.78)
        controllerService.storage.leftTrigger = 0.9
        controllerService.storage.rightTrigger = 0.1
        controllerService.storage.isDualSense = false
        controllerService.storage.isSteamController = false
        controllerService.storage.lock.unlock()

        let snap = controllerService.snapshot()

        XCTAssertEqual(snap.leftStick, controllerService.threadSafeLeftStick)
        XCTAssertEqual(snap.rightStick, controllerService.threadSafeRightStick)
        XCTAssertEqual(snap.leftTrigger, controllerService.threadSafeLeftTrigger)
        XCTAssertEqual(snap.rightTrigger, controllerService.threadSafeRightTrigger)
        XCTAssertEqual(
            snap.hasMotion,
            controllerService.threadSafeHasMotion
        )
    }

	private func steamMotion(gyroX: Int16, gyroY: Int16, gyroZ: Int16) -> SteamControllerMotionReport {
		SteamControllerMotionReport(
			timestamp: 1,
			accelX: 0,
			accelY: 0,
			accelZ: 0,
			gyroX: gyroX,
			gyroY: gyroY,
			gyroZ: gyroZ
		)
	}
}
