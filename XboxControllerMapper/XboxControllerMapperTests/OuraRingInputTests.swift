import CoreBluetooth
import XCTest
@testable import ControllerKeys

final class OuraRingInputTests: XCTestCase {
	func testScreenPlanePitchDirectionConsistentAcrossCenteringPoses() {
		// Regression: centering with the finger level-or-raised (neutral y > 0)
		// inverted up/down; pitching the finger up must move the projection the
		// same direction regardless of the centering pose.
		func pitchResponse(neutralY: Double) -> Double {
			var settings = OuraMotionSettings.default
			settings.enabled = true
			settings.orientation = .screenPlane
			var mapper = OuraMotionMapper(settings: settings)
			let nx = 0.05, nz = -0.95
			_ = mapper.mappingResult(forRawSample: OuraMotionSample(x: nx, y: neutralY, z: nz, timestamp: 1.0))
			let theta = 0.1
			let py = neutralY * cos(theta) - nz * sin(theta)
			let pz = neutralY * sin(theta) + nz * cos(theta)
			let result = mapper.mappingResult(forRawSample: OuraMotionSample(x: nx, y: py, z: pz, timestamp: 1.05))
			return Double(result.projectedInput.y)
		}

		let down = pitchResponse(neutralY: -0.3)
		let up = pitchResponse(neutralY: 0.3)
		XCTAssertGreaterThan(abs(down), 1e-4)
		XCTAssertGreaterThan(abs(up), 1e-4)
		XCTAssertEqual((down > 0), (up > 0), "pitch direction must not depend on centering pose")
	}

	func testOuraMotionSettingsDecodeClampsAndDefaults() throws {
		let json = #"""
		{
			"enabled": true,
			"targetStick": "right",
			"sensitivity": 5.0,
			"deadzone": -1.0,
			"smoothing": 2.0
		}
		"""#.data(using: .utf8)!

		let decoded = try JSONDecoder().decode(OuraMotionSettings.self, from: json)

		XCTAssertTrue(decoded.enabled)
		XCTAssertTrue(decoded.motionOutputEnabled)
		XCTAssertEqual(decoded.targetStick, .right)
		XCTAssertEqual(decoded.orientation, .screenPlane)
		XCTAssertEqual(decoded.sensitivity, 1.0)
		XCTAssertEqual(decoded.horizontalBoost, 1.0)
		XCTAssertEqual(decoded.leftTiltBoost, 1.0)
		XCTAssertEqual(decoded.deadzone, 0.0)
		XCTAssertEqual(decoded.smoothing, 1.0)
		XCTAssertTrue(decoded.adoptResetRing)
		XCTAssertTrue(decoded.diagnosticsEnabled)
	}

	func testOuraMotionSettingsDefaultMatchesTunedRingProfile() {
		let settings = OuraMotionSettings.default

		XCTAssertFalse(settings.enabled)
		XCTAssertTrue(settings.motionOutputEnabled)
		XCTAssertEqual(settings.targetStick, .left)
		XCTAssertEqual(settings.orientation, .screenPlane)
		XCTAssertEqual(settings.sensitivity, 0.0479656339031339, accuracy: 1e-12)
		XCTAssertEqual(settings.horizontalBoost, 1.0, accuracy: 1e-12)
		XCTAssertEqual(settings.leftTiltBoost, 1.0, accuracy: 1e-12)
		XCTAssertEqual(settings.deadzone, 0.3505420470505618, accuracy: 1e-12)
		XCTAssertEqual(settings.smoothing, 0.7516045616005551, accuracy: 1e-12)
		XCTAssertFalse(settings.invertX)
		XCTAssertFalse(settings.invertY)
		XCTAssertTrue(settings.adoptResetRing)
		XCTAssertTrue(settings.diagnosticsEnabled)
	}

	func testJoystickSettingsRoundTripPreservesOuraMotion() throws {
		var settings = JoystickSettings()
		settings.ouraMotion.enabled = true
		settings.ouraMotion.motionOutputEnabled = false
		settings.ouraMotion.targetStick = .right
		settings.ouraMotion.orientation = .legacyXY
		settings.ouraMotion.sensitivity = 0.72
		settings.ouraMotion.horizontalBoost = 2.4
		settings.ouraMotion.leftTiltBoost = 1.6
		settings.ouraMotion.invertY = true

		let data = try JSONEncoder().encode(settings)
		let decoded = try JSONDecoder().decode(JoystickSettings.self, from: data)

		XCTAssertEqual(decoded.ouraMotion, settings.ouraMotion)
		XCTAssertTrue(decoded.isValid())
	}

	func testOuraPacketDecoderRecognizesAuthFrames() {
		let nonceFrame = Data([0x2f, 0x10, 0x2c] + Array(repeating: 0x11, count: 15))
		let authFrame = Data([0x2f, 0x02, 0x2e, 0x00])
		let keyFrame = Data([0x25, 0x01, 0x00])

		XCTAssertEqual(OuraRingPacketDecoder.decode(nonceFrame), [.nonce(Data(repeating: 0x11, count: 15))])
		XCTAssertEqual(OuraRingPacketDecoder.decode(authFrame), [.authStatus(.success)])
		XCTAssertEqual(OuraRingPacketDecoder.decode(keyFrame), [.keyInstallStatus(success: true)])
	}

	func testOuraProtocolBuildsRealtimeAccelerometerCommands() {
		XCTAssertEqual(
			OuraRingProtocol.startAccelerometerCommand(durationMinutes: 10),
			Data([0x06, 0x07, 0x20, 0x00, 0x00, 0x00, 0x0a, 0x00, 0x00])
		)
		XCTAssertEqual(
			OuraRingProtocol.stopRealtimeCommand(),
			Data([0x06, 0x04, 0x00, 0x00, 0x00, 0x00])
		)
	}

	func testOuraScanMatcherRecognizesServiceAndNames() {
		XCTAssertEqual(
			OuraRingScanMatcher.match(
				peripheralName: nil,
				advertisementData: [CBAdvertisementDataServiceUUIDsKey: [OuraRingProtocol.serviceUUID]]
			),
			"service"
		)
		XCTAssertEqual(
			OuraRingScanMatcher.match(
				peripheralName: nil,
				advertisementData: [CBAdvertisementDataLocalNameKey: "Oura Ring 4"]
			),
			"local name"
		)
		XCTAssertEqual(
			OuraRingScanMatcher.match(peripheralName: "Ōura Ring", advertisementData: [:]),
			"peripheral name"
		)
		XCTAssertNil(
			OuraRingScanMatcher.match(
				peripheralName: "Keyboard",
				advertisementData: [CBAdvertisementDataLocalNameKey: "Keyboard"]
			)
		)
	}

	func testOuraPacketDecoderRecognizesTapFeaturePush() {
		let tapFrame = Data([0x2f, 0x02, 0x28, OuraRingProtocol.tapToTagFeature])

		XCTAssertEqual(OuraRingPacketDecoder.decode(tapFrame), [.tap])
	}

	func testOuraPacketDecoderRecognizesRealtimeAccelerometerFrame() throws {
		let frame = Data([
			0x33, 0x0c, 0x32, 0x01,
			0xe8, 0x03, 0x18, 0xfc, 0xf4, 0x01,
			0x00, 0x00, 0x00, 0x00, 0xe8, 0x03
		])

		let events = OuraRingPacketDecoder.decode(frame)
		guard events.count == 2 else {
			return XCTFail("Expected two accelerometer samples")
		}
		guard case .motion(let first) = events[0],
			  case .motion(let second) = events[1] else {
			return XCTFail("Expected motion samples")
		}

		XCTAssertEqual(first.x, 1.0, accuracy: 1e-9)
		XCTAssertEqual(first.y, -1.0, accuracy: 1e-9)
		XCTAssertEqual(first.z, 0.5, accuracy: 1e-9)
		XCTAssertEqual(second.x, 0.0, accuracy: 1e-9)
		XCTAssertEqual(second.y, 0.0, accuracy: 1e-9)
		XCTAssertEqual(second.z, 1.0, accuracy: 1e-9)
	}

	func testOuraPacketDecoderRecognizesMotionRecord() throws {
		let motionFrame = Data([0x47, 0x08, 0, 0, 0, 0, 0, 64, 0xc0, 0])

		guard case .motion(let sample) = OuraRingPacketDecoder.decode(motionFrame).first else {
			return XCTFail("Expected motion sample")
		}

		XCTAssertEqual(sample.x, 1.0, accuracy: 1e-9)
		XCTAssertEqual(sample.y, -1.0, accuracy: 1e-9)
		XCTAssertEqual(sample.z, 0.0, accuracy: 1e-9)
	}

	func testOuraTapDetectorDetectsSharpImpulse() {
		var detector = OuraTapDetector()

		XCTAssertFalse(detector.register(OuraMotionSample(x: 0, y: 0, z: 1.0, timestamp: 10.00)))
		XCTAssertFalse(detector.register(OuraMotionSample(x: 0.01, y: 0, z: 1.0, timestamp: 10.02)))
		XCTAssertFalse(detector.register(OuraMotionSample(x: 0.72, y: 0.08, z: 1.42, timestamp: 10.04)))
		XCTAssertTrue(detector.register(OuraMotionSample(x: 0, y: 0, z: 1.0, timestamp: 10.06)))
		XCTAssertFalse(detector.register(OuraMotionSample(x: 0.05, y: 0.05, z: 1.02, timestamp: 10.35)))
	}

	func testOuraTapSequenceRecognizerResolvesSingleDoubleAndTripleTap() {
		var recognizer = OuraTapSequenceRecognizer()

		XCTAssertEqual(recognizer.registerTap(at: 1.00), .pending(1))
		XCTAssertNil(recognizer.resolvePending(at: 1.70))
		XCTAssertEqual(recognizer.resolvePending(at: 1.76), .tapCount(1))

		XCTAssertEqual(recognizer.registerTap(at: 2.00), .pending(1))
		XCTAssertEqual(recognizer.registerTap(at: 2.48), .pending(2))
		XCTAssertNil(recognizer.resolvePending(at: 3.10))
		XCTAssertEqual(recognizer.resolvePending(at: 3.24), .tapCount(2))

		XCTAssertEqual(recognizer.registerTap(at: 4.00), .pending(1))
		XCTAssertEqual(recognizer.registerTap(at: 4.42), .pending(2))
		XCTAssertEqual(recognizer.registerTap(at: 4.88), .pending(3))
		XCTAssertEqual(recognizer.resolvePending(at: 5.64), .tapCount(3))
	}

	func testOuraTapSequenceRecognizerCompletesFiveTapImmediately() {
		var recognizer = OuraTapSequenceRecognizer()

		XCTAssertEqual(recognizer.registerTap(at: 5.00), .pending(1))
		XCTAssertEqual(recognizer.registerTap(at: 5.32), .pending(2))
		XCTAssertEqual(recognizer.registerTap(at: 5.75), .pending(3))
		XCTAssertEqual(recognizer.registerTap(at: 6.19), .pending(4))
		XCTAssertEqual(recognizer.registerTap(at: 6.62), .completed(5))
		XCTAssertNil(recognizer.resolvePending(at: 7.30))
	}

	func testOuraTapSequenceRecognizerIgnoresDuplicateReports() {
		var recognizer = OuraTapSequenceRecognizer()

		XCTAssertEqual(recognizer.registerTap(at: 4.00), .pending(1))
		XCTAssertEqual(recognizer.registerTap(at: 4.04), .duplicate)
		XCTAssertEqual(recognizer.registerTap(at: 4.18), .pending(2))
		XCTAssertEqual(recognizer.resolvePending(at: 4.94), .tapCount(2))
	}

	func testOuraTapSequenceRecognizerEchoGuardDowngradesFastPairToSingle() {
		var recognizer = OuraTapSequenceRecognizer()
		recognizer.echoGuardGap = 0.35

		// Settle echo 0.26s after a single tap — the live misfire signature.
		XCTAssertEqual(recognizer.registerTap(at: 1.00), .pending(1))
		XCTAssertEqual(recognizer.registerTap(at: 1.26), .pending(2))
		XCTAssertEqual(recognizer.resolvePending(at: 2.02), .tapCount(1))
		XCTAssertEqual(recognizer.lastResolutionEchoGap ?? -1, 0.26, accuracy: 0.001)

		// A deliberate two-beat double is untouched.
		XCTAssertEqual(recognizer.registerTap(at: 3.00), .pending(1))
		XCTAssertEqual(recognizer.registerTap(at: 3.45), .pending(2))
		XCTAssertEqual(recognizer.resolvePending(at: 4.21), .tapCount(2))
		XCTAssertNil(recognizer.lastResolutionEchoGap)
	}

	func testOuraTapSequenceRecognizerEchoGuardDropsRhythmBreakingTrailingTap() {
		var recognizer = OuraTapSequenceRecognizer()
		recognizer.echoGuardGap = 0.35

		// Slow double followed by a fast settle echo → still a double.
		XCTAssertEqual(recognizer.registerTap(at: 1.00), .pending(1))
		XCTAssertEqual(recognizer.registerTap(at: 1.45), .pending(2))
		XCTAssertEqual(recognizer.registerTap(at: 1.70), .pending(3))
		XCTAssertEqual(recognizer.resolvePending(at: 2.46), .tapCount(2))
		XCTAssertEqual(recognizer.lastResolutionEchoGap ?? -1, 0.25, accuracy: 0.001)

		// A machine-gun triple establishes its rhythm — trailing tap kept.
		XCTAssertEqual(recognizer.registerTap(at: 5.00), .pending(1))
		XCTAssertEqual(recognizer.registerTap(at: 5.24), .pending(2))
		XCTAssertEqual(recognizer.registerTap(at: 5.50), .pending(3))
		XCTAssertEqual(recognizer.resolvePending(at: 6.26), .tapCount(3))
		XCTAssertNil(recognizer.lastResolutionEchoGap)
	}

	func testOuraTapSequenceRecognizerEchoGuardDisabledByZeroGap() {
		var recognizer = OuraTapSequenceRecognizer()
		recognizer.echoGuardGap = 0

		XCTAssertEqual(recognizer.registerTap(at: 1.00), .pending(1))
		XCTAssertEqual(recognizer.registerTap(at: 1.26), .pending(2))
		XCTAssertEqual(recognizer.resolvePending(at: 2.02), .tapCount(2))
	}

	func testOuraTapMotionSuppressorExtendsAndExpires() {
		var suppressor = OuraTapMotionSuppressor()

		XCTAssertFalse(suppressor.isSuppressed(at: 10.00))

		suppressor.suppress(at: 10.00, duration: 0.50)
		XCTAssertTrue(suppressor.isSuppressed(at: 10.49))
		XCTAssertFalse(suppressor.isSuppressed(at: 10.50))

		suppressor.suppress(at: 11.00, duration: 0.20)
		suppressor.suppress(at: 11.10, duration: 0.50)
		XCTAssertTrue(suppressor.isSuppressed(at: 11.59))
		XCTAssertFalse(suppressor.isSuppressed(at: 11.60))

		suppressor.reset()
		XCTAssertFalse(suppressor.isSuppressed(at: 11.20))
	}

	func testOuraTapHoldRecognizerFiresAfterStillHold() {
		var recognizer = OuraTapHoldRecognizer()
		let anchor = OuraMotionSample(x: 0.10, y: 0.95, z: -0.12, timestamp: 40.00)

		recognizer.registerTap(at: anchor.timestamp, sample: anchor)

		XCTAssertFalse(recognizer.registerMotion(OuraMotionSample(x: 0.11, y: 0.95, z: -0.11, timestamp: 40.20)))
		XCTAssertFalse(recognizer.registerMotion(OuraMotionSample(x: 0.10, y: 0.96, z: -0.12, timestamp: 40.50)))
		XCTAssertTrue(recognizer.registerMotion(OuraMotionSample(x: 0.10, y: 0.95, z: -0.12, timestamp: 40.70)))
		XCTAssertFalse(recognizer.registerMotion(OuraMotionSample(x: 0.11, y: 0.95, z: -0.12, timestamp: 40.95)))
	}

	func testOuraTapHoldRecognizerCancelsWhenHandMoves() {
		var recognizer = OuraTapHoldRecognizer()
		let anchor = OuraMotionSample(x: 0.10, y: 0.95, z: -0.12, timestamp: 41.00)

		recognizer.registerTap(at: anchor.timestamp, sample: anchor)

		XCTAssertFalse(recognizer.registerMotion(OuraMotionSample(x: 0.58, y: 0.72, z: -0.32, timestamp: 41.20)))
		XCTAssertFalse(recognizer.registerMotion(OuraMotionSample(x: 0.10, y: 0.95, z: -0.12, timestamp: 41.70)))
	}

	func testOuraDirectionalFlickRecognizerDetectsFastReturnToStart() {
		var recognizer = OuraDirectionalFlickRecognizer()

		XCTAssertNil(recognizer.register(projectedInput: CGPoint(x: -0.22, y: 0.38), timestamp: 42.00))
		XCTAssertNil(recognizer.register(projectedInput: CGPoint(x: 0.42, y: 0.43), timestamp: 42.25))
		XCTAssertEqual(
			recognizer.register(projectedInput: CGPoint(x: -0.15, y: 0.36), timestamp: 42.50),
			.right
		)
	}

	func testOuraDirectionalFlickRecognizerRequiresReturnToStart() {
		var recognizer = OuraDirectionalFlickRecognizer()

		XCTAssertNil(recognizer.register(projectedInput: CGPoint(x: 0.20, y: -0.24), timestamp: 43.00))
		XCTAssertNil(recognizer.register(projectedInput: CGPoint(x: -0.44, y: -0.18), timestamp: 43.25))
		XCTAssertNil(recognizer.register(projectedInput: CGPoint(x: -0.36, y: -0.17), timestamp: 43.45))
		XCTAssertNil(recognizer.register(projectedInput: CGPoint(x: -0.30, y: -0.18), timestamp: 43.70))
	}

	func testOuraDirectionalFlickRecognizerIgnoresSlowSteeringMotion() {
		var recognizer = OuraDirectionalFlickRecognizer()

		XCTAssertNil(recognizer.register(projectedInput: .zero, timestamp: 44.00))
		XCTAssertNil(recognizer.register(projectedInput: CGPoint(x: 0.14, y: 0.02), timestamp: 44.08))
		XCTAssertNil(recognizer.register(projectedInput: CGPoint(x: 0.29, y: 0.02), timestamp: 44.20))
		XCTAssertNil(recognizer.register(projectedInput: CGPoint(x: 0.47, y: 0.03), timestamp: 44.36))
		XCTAssertNil(recognizer.register(projectedInput: CGPoint(x: 0.09, y: 0.02), timestamp: 44.64))
	}

	func testOuraMotionMapperAppliesDeadzoneSensitivityAndSmoothing() {
		var settings = OuraMotionSettings()
		settings.enabled = true
		settings.orientation = .legacyXY
		settings.deadzone = 0.1
		settings.sensitivity = 1.0
		settings.smoothing = 0.0

		var mapper = OuraMotionMapper(settings: settings)
		let sample = OuraMotionSample(x: 0.5, y: 0.0, z: 0.0, timestamp: 0)
		let stick = mapper.stickPosition(for: sample)

		XCTAssertGreaterThan(stick.x, 0.0)
		XCTAssertEqual(stick.y, 0.0, accuracy: 1e-9)
		XCTAssertLessThanOrEqual(stick.x, 1.0)

		let drift = OuraMotionSample(x: 0.01, y: 0.01, z: 0.0, timestamp: 0)
		let neutral = mapper.stickPosition(for: drift)
		XCTAssertEqual(neutral, .zero)
	}

	func testOuraMotionMapperAppliesHorizontalBoost() {
		var settings = OuraMotionSettings()
		settings.enabled = true
		settings.orientation = .legacyXY
		settings.deadzone = 0.0
		settings.sensitivity = 0.0
		settings.smoothing = 0.0
		settings.horizontalBoost = 1.0

		var normalMapper = OuraMotionMapper(settings: settings)
		let normalStick = normalMapper.stickPosition(for: OuraMotionSample(x: 0.2, y: 0.0, z: 0.0, timestamp: 0))

		settings.horizontalBoost = 2.2
		var boostedMapper = OuraMotionMapper(settings: settings)
		let boostedStick = boostedMapper.stickPosition(for: OuraMotionSample(x: 0.2, y: 0.0, z: 0.0, timestamp: 0))

		XCTAssertGreaterThan(abs(boostedStick.x), abs(normalStick.x))
		XCTAssertEqual(boostedStick.y, 0.0, accuracy: 1e-9)
	}

	func testOuraMotionMapperBoostsNegativeHorizontalSideForLeftTilt() {
		var settings = OuraMotionSettings()
		settings.enabled = true
		settings.orientation = .legacyXY
		settings.deadzone = 0.0
		settings.sensitivity = 0.0
		settings.smoothing = 0.0
		settings.horizontalBoost = 1.0
		settings.leftTiltBoost = 1.8

		var positiveMapper = OuraMotionMapper(settings: settings)
		let positiveStick = positiveMapper.stickPosition(for: OuraMotionSample(x: 0.2, y: 0.0, z: 0.0, timestamp: 0))

		var negativeMapper = OuraMotionMapper(settings: settings)
		let negativeStick = negativeMapper.stickPosition(for: OuraMotionSample(x: -0.2, y: 0.0, z: 0.0, timestamp: 0))

		XCTAssertGreaterThan(abs(negativeStick.x), abs(positiveStick.x))
		XCTAssertEqual(positiveStick.y, 0.0, accuracy: 1e-9)
		XCTAssertEqual(negativeStick.y, 0.0, accuracy: 1e-9)
	}

	func testOuraMotionMapperSuppressesStickWhenMotionOutputPaused() {
		var settings = OuraMotionSettings()
		settings.enabled = true
		settings.motionOutputEnabled = false
		settings.orientation = .legacyXY
		settings.deadzone = 0.0
		settings.sensitivity = 1.0
		settings.smoothing = 0.0

		var mapper = OuraMotionMapper(settings: settings)
		_ = mapper.mappingResult(forRawSample: OuraMotionSample(x: 0.0, y: 0.0, z: 0.0, timestamp: 0))
		let result = mapper.mappingResult(forRawSample: OuraMotionSample(x: 1.0, y: 1.0, z: 0.0, timestamp: 0.02))

		XCTAssertGreaterThan(result.projectedInput.x, 0.0)
		XCTAssertGreaterThan(result.projectedInput.y, 0.0)
		XCTAssertEqual(result.stick, .zero)
	}

	func testOuraMotionMapperFingerToScreenUsesZForVerticalTilt() {
		var settings = OuraMotionSettings()
		settings.enabled = true
		settings.orientation = .fingerToScreen
		settings.deadzone = 0.0
		settings.sensitivity = 0.0
		settings.smoothing = 0.0

		var mapper = OuraMotionMapper(settings: settings)
		let stick = mapper.stickPosition(for: OuraMotionSample(x: 0.0, y: 0.9, z: 0.4, timestamp: 0))

		XCTAssertEqual(stick.x, 0.0, accuracy: 1e-9)
		XCTAssertEqual(stick.y, 0.6392, accuracy: 1e-9)
	}

	func testOuraMotionMapperLegacyXYUsesYForVerticalTilt() {
		var settings = OuraMotionSettings()
		settings.enabled = true
		settings.orientation = .legacyXY
		settings.deadzone = 0.0
		settings.sensitivity = 0.0
		settings.smoothing = 0.0

		var mapper = OuraMotionMapper(settings: settings)
		let stick = mapper.stickPosition(for: OuraMotionSample(x: 0.0, y: 0.4, z: 0.9, timestamp: 0))

		XCTAssertEqual(stick.x, 0.0, accuracy: 1e-9)
		XCTAssertEqual(stick.y, 0.6392, accuracy: 1e-9)
	}

	func testOuraMotionMapperScreenPlaneUsesNeutralRelativeTilt() {
		var settings = OuraMotionSettings()
		settings.enabled = true
		settings.orientation = .screenPlane
		settings.deadzone = 0.0
		settings.sensitivity = 0.0
		settings.smoothing = 0.0

		var mapper = OuraMotionMapper(settings: settings)
		let neutral = mapper.mappingResult(forRawSample: OuraMotionSample(x: 0.0, y: 1.0, z: 0.0, timestamp: 0))
		let twistedRight = mapper.mappingResult(forRawSample: OuraMotionSample(x: -0.35, y: 0.94, z: 0.0, timestamp: 0.02))
		let tiltedUp = mapper.mappingResult(forRawSample: OuraMotionSample(x: 0.0, y: 0.94, z: -0.35, timestamp: 0.04))

		XCTAssertTrue(neutral.didEstablishCenter)
		XCTAssertEqual(neutral.stick, .zero)
		XCTAssertGreaterThan(twistedRight.projectedInput.x, 0.30)
		XCTAssertEqual(twistedRight.projectedInput.y, 0.0, accuracy: 1e-9)
		XCTAssertEqual(tiltedUp.projectedInput.x, 0.0, accuracy: 1e-9)
		// Sign flipped 2026-07-06 with the pose-independent up axis: this
		// synthetic neutral has y > 0, the pose family whose vertical
		// response was inverted in real use before the basis sign anchor.
		XCTAssertLessThan(tiltedUp.projectedInput.y, -0.30)
	}

	func testOuraTapDetectorIgnoresFastDirectionalSwipe() {
		var detector = OuraTapDetector()

		XCTAssertFalse(detector.register(OuraMotionSample(x: 0.0, y: 0.0, z: 1.0, timestamp: 20.00)))
		XCTAssertFalse(detector.register(OuraMotionSample(x: 0.9, y: 0.0, z: 1.1, timestamp: 20.02)))
		XCTAssertFalse(detector.register(OuraMotionSample(x: 1.3, y: 0.0, z: 1.1, timestamp: 20.04)))
		XCTAssertFalse(detector.register(OuraMotionSample(x: 1.7, y: 0.0, z: 1.1, timestamp: 20.06)))
	}

	func testOuraTapDetectorIgnoresBroadHandMotionBurst() {
		var detector = OuraTapDetector()
		// Real ring data: the most violent stretch of a prompted "move the
		// cursor, no gestures" trial from the 2026-07-05 labeled session
		// (Tools/oura-calibration), including the paired-timestamp BLE frame
		// structure. Broad hand motion must never register as a tap.
		let samples = [
			OuraMotionSample(x: 0.08, y: 0.46, z: -0.95, timestamp: 30.000),
			OuraMotionSample(x: 0.08, y: 0.45, z: -0.99, timestamp: 30.045),
			OuraMotionSample(x: 0.18, y: 0.46, z: -0.99, timestamp: 30.045),
			OuraMotionSample(x: 0.22, y: 0.48, z: -1.05, timestamp: 30.075),
			OuraMotionSample(x: 0.08, y: 0.52, z: -0.81, timestamp: 30.075),
			OuraMotionSample(x: 0.04, y: 0.50, z: -0.71, timestamp: 30.135),
			OuraMotionSample(x: 0.20, y: 0.43, z: -0.64, timestamp: 30.135),
			OuraMotionSample(x: 0.47, y: 0.21, z: -0.67, timestamp: 30.165),
			OuraMotionSample(x: 0.70, y: 0.18, z: -0.41, timestamp: 30.165),
			OuraMotionSample(x: 0.90, y: 0.27, z: -0.28, timestamp: 30.210),
			OuraMotionSample(x: 0.92, y: 0.27, z: -0.63, timestamp: 30.210),
			OuraMotionSample(x: 0.92, y: 0.29, z: -0.95, timestamp: 30.240),
			OuraMotionSample(x: 0.90, y: 0.34, z: -0.71, timestamp: 30.240),
			OuraMotionSample(x: 0.90, y: 0.35, z: -0.49, timestamp: 30.285),
			OuraMotionSample(x: 0.99, y: 0.32, z: -0.56, timestamp: 30.285),
			OuraMotionSample(x: 0.99, y: 0.23, z: -0.31, timestamp: 30.331),
			OuraMotionSample(x: 0.89, y: 0.17, z: -0.22, timestamp: 30.331),
			OuraMotionSample(x: 0.89, y: 0.09, z: 0.00, timestamp: 30.375)
		]

		for sample in samples {
			XCTAssertFalse(detector.register(sample))
		}
	}
}

final class OuraMotionTraceFormatTests: XCTestCase {
	func testSampleLineIsValidJSONWithExpectedFields() throws {
		let line = OuraMotionTraceFormat.sampleLine(
			wallTime: 1783272960.123456,
			sample: OuraMotionSample(x: 0.0125, y: -0.98, z: 1.4049, timestamp: 773430000.25),
			projected: CGPoint(x: 0.05, y: -0.0213)
		)

		let object = try XCTUnwrap(
			JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
		)
		XCTAssertEqual(object["type"] as? String, "sample")
		XCTAssertEqual(try XCTUnwrap(object["t"] as? Double), 1783272960.123456, accuracy: 1e-5)
		XCTAssertEqual(try XCTUnwrap(object["ct"] as? Double), 773430000.25, accuracy: 1e-5)
		XCTAssertEqual(try XCTUnwrap(object["x"] as? Double), 0.0125, accuracy: 1e-4)
		XCTAssertEqual(try XCTUnwrap(object["y"] as? Double), -0.98, accuracy: 1e-4)
		XCTAssertEqual(try XCTUnwrap(object["z"] as? Double), 1.4049, accuracy: 1e-4)
		XCTAssertEqual(try XCTUnwrap(object["px"] as? Double), 0.05, accuracy: 1e-4)
		XCTAssertEqual(try XCTUnwrap(object["py"] as? Double), -0.0213, accuracy: 1e-4)
	}

	func testEventLineWithDetailIsValidJSON() throws {
		let line = OuraMotionTraceFormat.eventLine(
			wallTime: 1783272961.5,
			timestamp: 773430001.5,
			name: "tap-candidate",
			detail: "accelerometer spike"
		)

		let object = try XCTUnwrap(
			JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
		)
		XCTAssertEqual(object["type"] as? String, "event")
		XCTAssertEqual(object["name"] as? String, "tap-candidate")
		XCTAssertEqual(object["detail"] as? String, "accelerometer spike")
		XCTAssertEqual(try XCTUnwrap(object["t"] as? Double), 1783272961.5, accuracy: 1e-5)
	}

	func testEventLineWithoutDetailOmitsField() throws {
		let line = OuraMotionTraceFormat.eventLine(
			wallTime: 1783272962.0,
			timestamp: 773430002.0,
			name: "center"
		)

		let object = try XCTUnwrap(
			JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
		)
		XCTAssertEqual(object["name"] as? String, "center")
		XCTAssertNil(object["detail"])
	}
}

final class OuraGestureEventClassifierTests: XCTestCase {
	func testImpulseDetectorConfirmsSpikeAndHonorsSeparation() {
		var detector = OuraImpulseDetector()

		XCTAssertNil(detector.register(OuraMotionSample(x: 0, y: 0, z: 1.0, timestamp: 10.00)))
		XCTAssertNil(detector.register(OuraMotionSample(x: 0.02, y: 0, z: 1.0, timestamp: 10.04)))
		XCTAssertNil(detector.register(OuraMotionSample(x: 0.9, y: 0.1, z: 1.4, timestamp: 10.08)))
		// spike confirmed one jerk-series entry later
		XCTAssertEqual(detector.register(OuraMotionSample(x: 0.05, y: 0, z: 1.0, timestamp: 10.12)), 10.08)
		// a second peak inside the 0.18s separation must not confirm
		XCTAssertNil(detector.register(OuraMotionSample(x: 0.9, y: 0.1, z: 1.4, timestamp: 10.16)))
		XCTAssertNil(detector.register(OuraMotionSample(x: 0.05, y: 0, z: 1.0, timestamp: 10.20)))
	}

	func testImpulseDetectorSkipsPairedFrameSamples() {
		var detector = OuraImpulseDetector()

		XCTAssertNil(detector.register(OuraMotionSample(x: 0, y: 0, z: 1.0, timestamp: 20.00)))
		// second sample of the same BLE frame (<1ms apart) adds no jerk entry
		XCTAssertNil(detector.register(OuraMotionSample(x: 5.0, y: 5.0, z: 5.0, timestamp: 20.0004)))
		XCTAssertNil(detector.register(OuraMotionSample(x: 0.01, y: 0, z: 1.0, timestamp: 20.04)))
		XCTAssertNil(detector.register(OuraMotionSample(x: 0.02, y: 0, z: 1.0, timestamp: 20.08)))
		XCTAssertNil(detector.register(OuraMotionSample(x: 0.03, y: 0, z: 1.0, timestamp: 20.12)))
	}

	func testMotionWindowBufferResamplesLinearRamp() throws {
		var buffer = OuraMotionWindowBuffer()
		// linear ramp: x goes 0→1 over exactly the window span around center 10.0
		let lo = 10.0 - OuraMotionWindowBuffer.preSpan
		let hi = 10.0 + OuraMotionWindowBuffer.postSpan
		for i in 0...64 {
			let t = lo + (hi - lo) * Double(i) / 64.0
			let v = Double(i) / 64.0
			buffer.append(OuraMotionSample(x: v, y: -v, z: 1.0, timestamp: t),
				projected: CGPoint(x: v * 2, y: 0))
		}

		let window = try XCTUnwrap(buffer.window(around: 10.0))
		XCTAssertEqual(window.count, OuraMotionWindowBuffer.steps)
		XCTAssertEqual(window[0][0], 0.0, accuracy: 0.02)
		XCTAssertEqual(window[31][0], 1.0, accuracy: 0.02)
		XCTAssertEqual(window[16][0], Double(16) / 31.0, accuracy: 0.04)
		XCTAssertEqual(window[16][1], -window[16][0], accuracy: 1e-9)
		XCTAssertEqual(window[16][3], window[16][0] * 2, accuracy: 1e-9)
	}

	func testMotionWindowBufferRejectsSparseCoverage() {
		var buffer = OuraMotionWindowBuffer()
		buffer.append(OuraMotionSample(x: 0, y: 0, z: 1, timestamp: 9.99), projected: .zero)
		buffer.append(OuraMotionSample(x: 0, y: 0, z: 1, timestamp: 10.01), projected: .zero)
		XCTAssertNil(buffer.window(around: 10.0))
	}

	// Process-lifetime instance: deallocating a classifier inside XCTest's
	// memory-check scope exercised an isolated-deinit runtime bug (see the
	// nonisolated note on the class); a static also mirrors production, where
	// the service holds one classifier for the app's lifetime.
	private static let sharedClassifier = OuraGestureEventClassifier()

	func testClassifierPredictsRealFlickAndTapWindows() {
		let classifier = Self.sharedClassifier
		classifier.loadIfNeeded()
		let deadline = Date().addingTimeInterval(10)
		while !classifier.isAvailable && Date() < deadline {
			RunLoop.current.run(until: Date().addingTimeInterval(0.05))
		}
		XCTAssertTrue(classifier.isAvailable, "OuraGestureClassifier.mlmodelc missing or failed to load from bundle")

		// Real windows from the 2026-07-05 labeled session (events.ndjson).
		let flickResult = classifier.classify(window: Self.flickLeftWindow)
		XCTAssertEqual(flickResult?.event, .flickLeft)
		XCTAssertGreaterThan(flickResult?.confidence ?? 0, 0.97, "real flicks measured ≥0.98 confidence")
		XCTAssertEqual(classifier.classify(window: Self.tapWindow)?.event, .tap)
	}

	private static let flickLeftWindow: [[Double]] = [
		[0.2383, -0.2868, -0.9815, -0.139, 0.4406],
		[0.2455, -0.2836, -0.9862, -0.1461, 0.4461],
		[0.2287, -0.2772, -0.9762, -0.1306, 0.4442],
		[0.2119, -0.2707, -0.9661, -0.1152, 0.4423],
		[0.2046, -0.2611, -0.9455, -0.1101, 0.4358],
		[0.1905, -0.2589, -0.9405, -0.0968, 0.4341],
		[0.1346, -0.2594, -0.9581, -0.0397, 0.4454],
		[0.0935, -0.273, -0.9781, 0.0037, 0.4487],
		[0.0525, -0.2866, -0.9981, 0.0471, 0.4519],
		[-0.0714, -0.2693, -1.0847, 0.1759, 0.5225],
		[-0.1802, -0.2766, -1.1164, 0.287, 0.5381],
		[-0.2889, -0.284, -1.1481, 0.3982, 0.5538],
		[-1.0676, -0.2884, -1.2029, 1.1772, 0.587],
		[-1.1045, -0.4403, -1.0634, 1.2135, 0.3809],
		[-0.2479, -0.8955, -0.7008, 0.3653, -0.2002],
		[0.0813, -0.8462, -0.649, 0.0304, -0.198],
		[0.4105, -0.7969, -0.5972, -0.3045, -0.1958],
		[0.9689, -0.6454, -0.9311, -0.8441, 0.1397],
		[0.9961, -0.6277, -1.0119, -0.866, 0.2068],
		[1.0233, -0.6101, -1.0927, -0.8879, 0.2738],
		[0.7829, -0.435, -1.2329, -0.6502, 0.4978],
		[0.3613, -0.4554, -0.798, -0.2639, 0.1927],
		[0.3627, -0.4288, -0.8027, -0.2669, 0.2156],
		[0.3642, -0.4022, -0.8073, -0.2698, 0.2385],
		[0.4255, -0.359, -0.8462, -0.3307, 0.2966],
		[0.422, -0.3475, -0.8445, -0.3282, 0.3041],
		[0.4185, -0.3359, -0.8427, -0.3257, 0.3115],
		[0.2463, -0.3199, -0.8288, -0.1566, 0.3141],
		[0.2034, -0.2973, -0.8197, -0.1164, 0.325],
		[0.0602, -0.2369, -0.831, 0.0227, 0.3774],
		[0.0481, -0.2365, -0.838, 0.0352, 0.3825],
		[0.036, -0.236, -0.845, 0.0478, 0.3875]
	]

	private static let tapWindow: [[Double]] = [
		[0.2947, -0.3983, -1.1207, 0.0819, -0.0381],
		[0.2937, -0.2675, -1.1154, 0.0692, 0.0849],
		[0.3475, -0.2397, -1.1878, 0.0365, 0.1334],
		[0.4012, -0.212, -1.2602, 0.0037, 0.1819],
		[0.2246, -0.0494, -1.4993, 0.2263, 0.4096],
		[0.3262, -0.2055, -1.1042, 0.0293, 0.1405],
		[0.2355, -0.1592, -0.5084, -0.0618, 0.0032],
		[0.2327, -0.0507, -0.6809, -0.019, 0.1591],
		[0.2298, 0.0578, -0.8534, 0.0237, 0.3149],
		[0.2958, 0.1884, -0.9443, -0.0248, 0.4671],
		[0.2745, 0.1989, -0.8844, -0.0229, 0.4588],
		[0.2774, 0.1031, -0.7038, -0.0693, 0.3126],
		[0.288, 0.0209, -0.4989, -0.1313, 0.1719],
		[0.2987, -0.0614, -0.2941, -0.1933, 0.0311],
		[-0.0968, -0.3795, -0.6882, 0.3274, -0.1518],
		[-0.2021, 0.5632, -2.9792, 1.0057, 1.4437],
		[-0.3074, 1.5059, -5.2701, 1.684, 3.0393],
		[-0.0471, -0.649, -1.0909, 0.4222, -0.2859],
		[0.2931, -0.245, -1.1167, 0.0681, 0.1068],
		[0.3067, -0.2571, -1.1249, 0.0587, 0.0977],
		[0.3202, -0.2693, -1.1331, 0.0493, 0.0886],
		[0.3203, 0.0835, -1.1701, 0.0272, 0.4358],
		[0.307, -0.0, -1.0317, 0.0074, 0.3142],
		[0.2937, -0.0835, -0.8934, -0.0124, 0.1925],
		[0.2242, -0.1538, -0.7263, 0.0119, 0.0747],
		[0.2327, -0.135, -0.7696, 0.0146, 0.1058],
		[0.2411, -0.1162, -0.813, 0.0174, 0.137],
		[0.2636, -0.0599, -0.8783, 0.0098, 0.2105],
		[0.2613, -0.0436, -0.9004, 0.0168, 0.2327],
		[0.2591, -0.0274, -0.9225, 0.0238, 0.2549],
		[0.2917, 0.0042, -1.016, 0.017, 0.3134],
		[0.2862, -0.0358, -0.9589, 0.0094, 0.2579]
	]
}

final class OuraAutoRecenterMonitorTests: XCTestCase {
	private func makeMonitor() -> OuraAutoRecenterMonitor {
		var monitor = OuraAutoRecenterMonitor()
		monitor.enabled = true
		return monitor
	}

	private let neutral = OuraMotionSample(x: 0, y: 0.7, z: 0.7, timestamp: 0)

	/// Feeds still samples at `pose` from `start` at ~48Hz for `duration`;
	/// returns the first snap, if any.
	private func feedStill(
		_ monitor: inout OuraAutoRecenterMonitor,
		pose: (Double, Double, Double),
		from start: CFAbsoluteTime,
		duration: CFTimeInterval
	) -> (neutral: OuraMotionSample, driftDegrees: Double)? {
		var t = start
		while t < start + duration {
			let sample = OuraMotionSample(x: pose.0, y: pose.1, z: pose.2, timestamp: t)
			if let snap = monitor.register(sample, neutral: neutral) {
				return snap
			}
			t += 0.021
		}
		return nil
	}

	func testStaleCenterAtRestSnapsAfterConfirmWindow() {
		var monitor = makeMonitor()
		// 60° away from neutral, |a| ≈ 0.99 — provably stale at rest.
		let snap = feedStill(&monitor, pose: (0.7, 0.7, 0), from: 10.0, duration: 2.5)
		XCTAssertNotNil(snap)
		XCTAssertEqual(snap?.driftDegrees ?? 0, 60, accuracy: 3)
		XCTAssertEqual(snap?.neutral.x ?? 0, 0.7, accuracy: 0.01)
		// The snap must not fire before the confirm window has elapsed.
		XCTAssertGreaterThanOrEqual(snap?.neutral.timestamp ?? 0, 10.0 + monitor.confirmDuration)
	}

	func testActiveMotionNeverSnaps() {
		var monitor = makeMonitor()
		var t: CFAbsoluteTime = 10.0
		var flip = false
		while t < 14.0 {
			// Inter-sample delta ~0.06 — above the stillness bar.
			let x = 0.7 + (flip ? 0.035 : -0.035)
			XCTAssertNil(monitor.register(
				OuraMotionSample(x: x, y: 0.7, z: 0, timestamp: t), neutral: neutral))
			flip.toggle()
			t += 0.021
		}
	}

	func testDriftBelowThresholdDoesNotSnap() {
		var monitor = makeMonitor()
		// ~8° from neutral — inside the healthy band.
		let pose = (0.0, 0.7 * cos(8 * Double.pi / 180) - 0.7 * sin(8 * Double.pi / 180),
			0.7 * sin(8 * Double.pi / 180) + 0.7 * cos(8 * Double.pi / 180))
		XCTAssertNil(feedStill(&monitor, pose: pose, from: 10.0, duration: 3.0))
	}

	func testNonGravityMagnitudeDoesNotSnap() {
		var monitor = makeMonitor()
		// Large angle but |a| = 0.42 — not a pure-gravity rest window.
		XCTAssertNil(feedStill(&monitor, pose: (0.3, 0.3, 0), from: 10.0, duration: 3.0))
	}

	func testHoldOffDefersSnapUntilExpiry() {
		var monitor = makeMonitor()
		monitor.holdOff(until: 13.0)
		XCTAssertNil(feedStill(&monitor, pose: (0.7, 0.7, 0), from: 10.0, duration: 2.9))
		let snap = feedStill(&monitor, pose: (0.7, 0.7, 0), from: 12.9, duration: 0.5)
		XCTAssertNotNil(snap)
		XCTAssertGreaterThanOrEqual(snap?.neutral.timestamp ?? 0, 13.0)
	}

	func testCooldownBlocksBackToBackSnaps() {
		var monitor = makeMonitor()
		XCTAssertNotNil(feedStill(&monitor, pose: (0.7, 0.7, 0), from: 10.0, duration: 2.0))
		// New still pose right after — still stale vs neutral, but inside cooldown.
		XCTAssertNil(feedStill(&monitor, pose: (0, 0, 1), from: 12.1, duration: 2.5))
		// After the cooldown expires the ongoing still run may snap again.
		XCTAssertNotNil(feedStill(&monitor, pose: (0, 0, 1), from: 14.7, duration: 2.5))
	}

	func testDisabledMonitorNeverSnaps() {
		var monitor = makeMonitor()
		monitor.enabled = false
		XCTAssertNil(feedStill(&monitor, pose: (0.7, 0.7, 0), from: 10.0, duration: 4.0))
	}

	func testMapperSnapsStaleCenterAndZeroesProjection() {
		var settings = OuraMotionSettings.default
		settings.enabled = true
		settings.orientation = .screenPlane
		var mapper = OuraMotionMapper(settings: settings)
		mapper.autoRecenterMonitor.enabled = true

		// First sample establishes the center at (0, 0.7, 0.7).
		let first = mapper.mappingResult(forRawSample: OuraMotionSample(x: 0, y: 0.7, z: 0.7, timestamp: 0))
		XCTAssertTrue(first.didEstablishCenter)

		// Hand comes to rest 60° away — projection reads a large phantom
		// deflection until the monitor snaps.
		var t: CFAbsoluteTime = 0.021
		var snapDrift: Double?
		var lastProjection = CGPoint.zero
		while t < 3.0 {
			let result = mapper.mappingResult(forRawSample: OuraMotionSample(x: 0.7, y: 0.7, z: 0, timestamp: t))
			if let drift = result.autoRecenterDriftDegrees {
				snapDrift = drift
			}
			lastProjection = result.projectedInput
			t += 0.021
		}
		XCTAssertEqual(snapDrift ?? 0, 60, accuracy: 3)
		XCTAssertLessThan(hypot(lastProjection.x, lastProjection.y), 0.05,
			"projection should read neutral after the snap")
	}
}
