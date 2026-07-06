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
