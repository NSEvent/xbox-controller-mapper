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
