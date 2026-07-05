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
		XCTAssertEqual(decoded.horizontalBoost, 2.2)
		XCTAssertEqual(decoded.leftTiltBoost, 1.8)
		XCTAssertEqual(decoded.deadzone, 0.0)
		XCTAssertEqual(decoded.smoothing, 1.0)
		XCTAssertTrue(decoded.adoptResetRing)
		XCTAssertTrue(decoded.diagnosticsEnabled)
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
		XCTAssertFalse(detector.register(OuraMotionSample(x: 0.72, y: 0.08, z: 1.42, timestamp: 10.02)))
		XCTAssertTrue(detector.register(OuraMotionSample(x: 0, y: 0, z: 1.0, timestamp: 10.04)))
		XCTAssertFalse(detector.register(OuraMotionSample(x: 0.05, y: 0.05, z: 1.02, timestamp: 10.35)))
	}

	func testOuraTapSequenceRecognizerResolvesSingleDoubleAndTripleTap() {
		var recognizer = OuraTapSequenceRecognizer()

		XCTAssertEqual(recognizer.registerTap(at: 1.00), .pending(1))
		XCTAssertEqual(recognizer.resolvePending(at: 1.40), .tapCount(1))

		XCTAssertEqual(recognizer.registerTap(at: 2.00), .pending(1))
		XCTAssertEqual(recognizer.registerTap(at: 2.18), .pending(2))
		XCTAssertEqual(recognizer.resolvePending(at: 2.54), .tapCount(2))

		XCTAssertEqual(recognizer.registerTap(at: 3.00), .pending(1))
		XCTAssertEqual(recognizer.registerTap(at: 3.16), .pending(2))
		XCTAssertEqual(recognizer.registerTap(at: 3.31), .pending(3))
		XCTAssertEqual(recognizer.resolvePending(at: 3.70), .tapCount(3))
	}

	func testOuraTapSequenceRecognizerCompletesFiveTapImmediately() {
		var recognizer = OuraTapSequenceRecognizer()

		XCTAssertEqual(recognizer.registerTap(at: 5.00), .pending(1))
		XCTAssertEqual(recognizer.registerTap(at: 5.12), .pending(2))
		XCTAssertEqual(recognizer.registerTap(at: 5.24), .pending(3))
		XCTAssertEqual(recognizer.registerTap(at: 5.36), .pending(4))
		XCTAssertEqual(recognizer.registerTap(at: 5.48), .completed(5))
		XCTAssertNil(recognizer.resolvePending(at: 5.90))
	}

	func testOuraTapSequenceRecognizerIgnoresDuplicateReports() {
		var recognizer = OuraTapSequenceRecognizer()

		XCTAssertEqual(recognizer.registerTap(at: 4.00), .pending(1))
		XCTAssertEqual(recognizer.registerTap(at: 4.04), .duplicate)
		XCTAssertEqual(recognizer.registerTap(at: 4.18), .pending(2))
		XCTAssertEqual(recognizer.resolvePending(at: 4.54), .tapCount(2))
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
}
