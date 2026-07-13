import XCTest
@testable import ControllerKeys

final class JoystickSettingsPointerLockCodableTests: XCTestCase {

    func testDefaultIsAuto() {
        XCTAssertEqual(JoystickSettings().pointerLockMouseMode, .auto)
        XCTAssertEqual(JoystickSettings.default.pointerLockMouseMode, .auto)
    }

    func testDecodingLegacyJSONWithoutKey_defaultsToAuto() throws {
        let settings = try JSONDecoder().decode(JoystickSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings.pointerLockMouseMode, .auto,
                       "Profiles saved by older builds must gain auto mode")
    }

    func testEncodeDecodeRoundTrip_allModes() throws {
        for mode in PointerLockMouseMode.allCases {
            var settings = JoystickSettings()
            settings.pointerLockMouseMode = mode
            let data = try JSONEncoder().encode(settings)
            let decoded = try JSONDecoder().decode(JoystickSettings.self, from: data)
            XCTAssertEqual(decoded.pointerLockMouseMode, mode)
        }
    }

    func testUnknownRawValue_degradesToAuto() throws {
        let json = #"{"pointerLockMouseMode": "hyperspace"}"#
        let settings = try JSONDecoder().decode(JoystickSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.pointerLockMouseMode, .auto,
                       "A mode from a newer build must not throw out the whole profile on downgrade")
    }

    func testValidationUnaffectedByMode() {
        var settings = JoystickSettings()
        settings.pointerLockMouseMode = .always
        XCTAssertTrue(settings.isValid())
    }
}

final class JoystickSettingsAnalogPrecisionCodableTests: XCTestCase {

    func testDefaultIsOffAndLegacyDecodeKeepsNormalSpeed() throws {
		let settings = try JSONDecoder().decode(JoystickSettings.self, from: Data("{}".utf8))

		XCTAssertEqual(settings.analogPrecisionTriggerMode, .off)
		XCTAssertEqual(settings.analogPrecisionMultiplier(leftTrigger: 1.0, rightTrigger: 1.0), 1.0)
    }

    func testEncodeDecodeRoundTripAllTriggerModes() throws {
		for mode in AnalogPrecisionTriggerMode.allCases {
			var settings = JoystickSettings()
			settings.analogPrecisionTriggerMode = mode
			settings.analogPrecisionMinimumSpeed = 0.25
			settings.analogPrecisionDeadzone = 0.1
			settings.analogPrecisionCurve = 0.75

			let data = try JSONEncoder().encode(settings)
			let decoded = try JSONDecoder().decode(JoystickSettings.self, from: data)

			XCTAssertEqual(decoded.analogPrecisionTriggerMode, mode)
			XCTAssertEqual(decoded.analogPrecisionMinimumSpeed, 0.25)
			XCTAssertEqual(decoded.analogPrecisionDeadzone, 0.1)
			XCTAssertEqual(decoded.analogPrecisionCurve, 0.75)
		}
    }

    func testUnknownTriggerModeDegradesToOff() throws {
		let json = #"{"analogPrecisionTriggerMode": "pressurePlate"}"#
		let settings = try JSONDecoder().decode(JoystickSettings.self, from: Data(json.utf8))

		XCTAssertEqual(settings.analogPrecisionTriggerMode, .off)
    }

    func testAnalogPrecisionMultiplierUsesSelectedTrigger() {
		var settings = JoystickSettings()
		settings.analogPrecisionTriggerMode = .left
		settings.analogPrecisionMinimumSpeed = 0.2
		settings.analogPrecisionDeadzone = 0.1
		settings.analogPrecisionCurve = 0.0

		XCTAssertEqual(settings.analogPrecisionMultiplier(leftTrigger: 0.1, rightTrigger: 1.0), 1.0)
		XCTAssertEqual(settings.analogPrecisionMultiplier(leftTrigger: 1.0, rightTrigger: 0.0), 0.2, accuracy: 1e-10)

		settings.analogPrecisionTriggerMode = .right
		XCTAssertEqual(settings.analogPrecisionMultiplier(leftTrigger: 1.0, rightTrigger: 0.1), 1.0)
		XCTAssertEqual(settings.analogPrecisionMultiplier(leftTrigger: 0.0, rightTrigger: 1.0), 0.2, accuracy: 1e-10)
    }

    func testEitherTriggerUsesDeeperPullAndIsMonotonic() {
		var settings = JoystickSettings()
		settings.analogPrecisionTriggerMode = .either
		settings.analogPrecisionMinimumSpeed = 0.15
		settings.analogPrecisionDeadzone = 0.0
		settings.analogPrecisionCurve = 0.35

		let shallow = settings.analogPrecisionMultiplier(leftTrigger: 0.2, rightTrigger: 0.1)
		let medium = settings.analogPrecisionMultiplier(leftTrigger: 0.2, rightTrigger: 0.5)
		let full = settings.analogPrecisionMultiplier(leftTrigger: 0.0, rightTrigger: 1.0)

		XCTAssertGreaterThan(shallow, medium)
		XCTAssertGreaterThan(medium, full)
		XCTAssertEqual(full, 0.15, accuracy: 1e-10)
    }

    func testDecodingClampsAnalogPrecisionRanges() throws {
		let json = """
		{
		  "analogPrecisionTriggerMode": "either",
		  "analogPrecisionMinimumSpeed": 0.01,
		  "analogPrecisionDeadzone": 2.0,
		  "analogPrecisionCurve": -1.0
		}
		"""

		let settings = try JSONDecoder().decode(JoystickSettings.self, from: Data(json.utf8))

		XCTAssertEqual(settings.analogPrecisionMinimumSpeed, 0.05)
		XCTAssertEqual(settings.analogPrecisionDeadzone, 0.95)
		XCTAssertEqual(settings.analogPrecisionCurve, 0.0)
		XCTAssertTrue(settings.isValid())
    }
}
