import CoreBluetooth
import XCTest
@testable import ControllerKeys

final class OuraRingInputTests: XCTestCase {
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
		XCTAssertNil(recognizer.resolvePending(at: 1.60))
		XCTAssertEqual(recognizer.resolvePending(at: 1.66), .tapCount(1))

		XCTAssertEqual(recognizer.registerTap(at: 2.00), .pending(1))
		XCTAssertEqual(recognizer.registerTap(at: 2.48), .pending(2))
		XCTAssertNil(recognizer.resolvePending(at: 3.10))
		XCTAssertEqual(recognizer.resolvePending(at: 3.14), .tapCount(2))

		XCTAssertEqual(recognizer.registerTap(at: 4.00), .pending(1))
		XCTAssertEqual(recognizer.registerTap(at: 4.42), .pending(2))
		XCTAssertEqual(recognizer.registerTap(at: 4.88), .pending(3))
		XCTAssertEqual(recognizer.resolvePending(at: 5.54), .tapCount(3))
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
		XCTAssertEqual(recognizer.resolvePending(at: 4.84), .tapCount(2))
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
		XCTAssertTrue(recognizer.registerMotion(OuraMotionSample(x: 0.10, y: 0.96, z: -0.12, timestamp: 40.50)))
		XCTAssertFalse(recognizer.registerMotion(OuraMotionSample(x: 0.11, y: 0.95, z: -0.12, timestamp: 40.80)))
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
		XCTAssertGreaterThan(tiltedUp.projectedInput.y, 0.30)
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
		[0.3289, -0.1077, -1.0258, -0.0741, 0.4714],
		[0.3344, -0.1062, -0.993, -0.0874, 0.4581],
		[0.3362, -0.0998, -0.993, -0.0885, 0.4522],
		[0.3934, -0.1071, -1.003, -0.1419, 0.4626],
		[0.4206, -0.1195, -1.0117, -0.1672, 0.4773],
		[0.3788, -0.1106, -0.9883, -0.1318, 0.4606],
		[0.3155, -0.1046, -0.959, -0.0774, 0.4444],
		[0.1657, -0.2803, -1.0421, 0.0707, 0.6382],
		[0.1074, -0.372, -1.0868, 0.1292, 0.7399],
		[-1.4954, -0.4946, -0.9825, 1.6372, 0.8165],
		[-2.8005, -0.4616, -1.026, 2.9096, 0.8015],
		[-5.2286, -1.6188, -2.2172, 5.4343, 2.3112],
		[-3.2869, -1.9898, -1.717, 3.4029, 2.4761],
		[-0.5117, -3.7496, -0.6576, 0.2966, 3.7336],
		[1.0694, -4.4159, -0.0387, -1.4448, 4.131],
		[4.4558, -3.6502, -0.014, -4.6428, 3.4082],
		[4.9974, -2.756, -0.6223, -4.9293, 2.7945],
		[1.6608, -1.5441, -1.1815, -1.4577, 1.8669],
		[0.8806, -1.2191, -0.9087, -0.7416, 1.4652],
		[0.0879, -0.2876, -0.4667, 0.003, 0.437],
		[0.0487, -0.1057, -0.3646, 0.033, 0.2305],
		[0.1011, 0.1356, -0.4382, 0.0237, 0.032],
		[0.1242, 0.1296, -0.5672, 0.0328, 0.0843],
		[0.2603, 0.0349, -0.7416, -0.0645, 0.2357],
		[0.3673, 0.017, -0.8058, -0.1535, 0.2756],
		[0.4887, -0.11, -0.9082, -0.2575, 0.4311],
		[0.4832, -0.1498, -0.9394, -0.2483, 0.4794],
		[0.4205, -0.2464, -1.0292, -0.1749, 0.6019],
		[0.4415, -0.2622, -1.0261, -0.1974, 0.6156],
		[0.4625, -0.2781, -1.023, -0.22, 0.6292],
		[0.5279, -0.2471, -0.9653, -0.2943, 0.5794],
		[0.2504, -0.2783, -0.9714, -0.0282, 0.6108]
	]

	private static let tapWindow: [[Double]] = [
		[0.25, -0.3359, -1.3675, 0.15, 0.5308],
		[0.0511, -0.0038, -1.3278, 0.3425, 0.1965],
		[0.0861, 0.2827, -1.5375, 0.3834, -0.0565],
		[0.1093, -0.4281, -0.806, 0.1148, 0.5406],
		[0.1324, -0.2275, -0.6629, 0.0592, 0.3214],
		[0.242, 0.3024, -0.901, 0.0478, -0.1684],
		[0.2661, 0.3274, -0.8791, 0.0194, -0.1963],
		[0.1597, 0.3437, -0.9246, 0.135, -0.2058],
		[0.1307, 0.2725, -0.8162, 0.1276, -0.1511],
		[0.0367, -0.5208, -0.0232, -0.0507, 0.5186],
		[0.0935, -0.8996, -0.1498, -0.084, 0.9118],
		[-0.9428, 0.8333, -4.3955, 2.232, -0.1863],
		[-0.9153, 0.008, -1.8233, 1.4117, 0.2568],
		[0.092, -0.3949, -0.8976, 0.1597, 0.521],
		[0.1732, -0.338, -0.926, 0.0931, 0.4688],
		[0.142, -0.1504, -1.1082, 0.1847, 0.3097],
		[0.4731, 0.6336, -1.3209, -0.0347, -0.4351],
		[0.107, -0.4189, -0.7482, 0.1004, 0.5231],
		[0.107, -0.6798, -0.5107, 0.019, 0.7468],
		[0.0209, 0.136, -1.0451, 0.2941, 0.0172],
		[0.0948, 0.1814, -0.9946, 0.2106, -0.0351],
		[0.1688, 0.2269, -0.944, 0.1271, -0.0875],
		[0.2427, 0.2724, -0.8935, 0.0436, -0.1398],
		[0.0647, 0.2239, -1.2746, 0.3236, -0.0365],
		[0.0921, 0.2314, -1.1145, 0.2507, -0.0671],
		[0.1945, 0.2151, -1.065, 0.1376, -0.0582],
		[0.1977, 0.205, -1.0293, 0.1236, -0.0534],
		[0.1593, 0.1909, -1.01, 0.154, -0.0423],
		[0.1431, 0.1724, -0.96, 0.1539, -0.0312],
		[0.1546, 0.2022, -0.9075, 0.1287, -0.0682],
		[0.1639, 0.2157, -0.922, 0.1247, -0.0795],
		[0.134, 0.2168, -0.9259, 0.1544, -0.0801]
	]
}
