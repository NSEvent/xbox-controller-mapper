import XCTest
@testable import ControllerKeys

/// Coverage for the per-stick tuning model: independent left/right response,
/// legacy-config migration, new-format round-trips, downgrade dual-write, and
/// the response curves that moved onto `StickTuning`.
final class PerStickTuningTests: XCTestCase {

    /// The headline fix (Discord feedback): two sticks both in mouse mode can have
    /// independent sensitivity. Previously both read one shared `mouseSensitivity`.
    func testLeftAndRightMouseSensitivityAreIndependent() {
        var settings = JoystickSettings()
        settings.leftStick.mode = .mouse
        settings.rightStick.mode = .mouse
        settings.leftStick.mouseSensitivity = 0.1
        settings.rightStick.mouseSensitivity = 0.9

        XCTAssertNotEqual(settings.leftStick.mouseSensitivity, settings.rightStick.mouseSensitivity)
        XCTAssertLessThan(
            settings.leftStick.mouseMultiplier,
            settings.rightStick.mouseMultiplier,
            "A lower-sensitivity left stick must yield a smaller mouse multiplier than the right."
        )
    }

    /// A legacy config (shared function-keyed fields) fans the same mouse/scroll values
    /// into BOTH sticks, preserving the old behavior while becoming independently editable.
    func testLegacyConfigMigratesIntoBothSticks() throws {
        let json = #"""
        {
            "mouseSensitivity": 0.3,
            "scrollSensitivity": 0.7,
            "mouseDeadzone": 0.2,
            "scrollDeadzone": 0.25,
            "leftStickMode": "mouse",
            "rightStickMode": "scroll"
        }
        """#.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(JoystickSettings.self, from: json)

        // Both sticks inherit the shared legacy values...
        XCTAssertEqual(decoded.leftStick.mouseSensitivity, 0.3, accuracy: 1e-9)
        XCTAssertEqual(decoded.rightStick.mouseSensitivity, 0.3, accuracy: 1e-9)
        XCTAssertEqual(decoded.leftStick.scrollSensitivity, 0.7, accuracy: 1e-9)
        XCTAssertEqual(decoded.rightStick.scrollSensitivity, 0.7, accuracy: 1e-9)
        XCTAssertEqual(decoded.leftStick.mouseDeadzone, 0.2, accuracy: 1e-9)
        XCTAssertEqual(decoded.rightStick.scrollDeadzone, 0.25, accuracy: 1e-9)
        // ...but keep their own modes.
        XCTAssertEqual(decoded.leftStick.mode, .mouse)
        XCTAssertEqual(decoded.rightStick.mode, .scroll)
    }

    /// New-format encode/decode preserves independent per-stick tuning.
    func testNewFormatRoundTripPreservesIndependentSticks() throws {
        var settings = JoystickSettings()
        settings.leftStick.mouseSensitivity = 0.15
        settings.rightStick.mouseSensitivity = 0.85
        settings.rightStick.mode = .mouse

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(JoystickSettings.self, from: data)

        XCTAssertEqual(decoded.leftStick.mouseSensitivity, 0.15, accuracy: 1e-9)
        XCTAssertEqual(decoded.rightStick.mouseSensitivity, 0.85, accuracy: 1e-9)
        XCTAssertEqual(decoded.rightStick.mode, .mouse)
    }

    /// Encoding writes the legacy flat keys too (downgrade safety): an older build reads
    /// the left stick's mouse values and the right stick's scroll values.
    func testEncodeWritesLegacyCompatibilityKeys() throws {
        var settings = JoystickSettings()
        settings.leftStick.mouseSensitivity = 0.42
        settings.rightStick.scrollSensitivity = 0.66

        let data = try JSONEncoder().encode(settings)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["mouseSensitivity"] as? Double, 0.42, "Legacy key mirrors left stick's mouse sensitivity.")
        XCTAssertEqual(object["scrollSensitivity"] as? Double, 0.66, "Legacy key mirrors right stick's scroll sensitivity.")
        XCTAssertNotNil(object["leftStick"], "New per-stick representation is also written.")
        XCTAssertNotNil(object["rightStick"], "New per-stick representation is also written.")
    }

    /// Response curves moved onto StickTuning keep the documented mapping.
    func testStickTuningResponseCurves() {
        var tuning = StickTuning(mode: .mouse)
        tuning.mouseSensitivity = 0.0
        XCTAssertEqual(tuning.mouseMultiplier, 2.0, accuracy: 1e-9)
        tuning.mouseSensitivity = 1.0
        XCTAssertEqual(tuning.mouseMultiplier, 120.0, accuracy: 1e-9)
        tuning.scrollSensitivity = 1.0
        XCTAssertEqual(tuning.scrollMultiplier, 30.0, accuracy: 1e-9)
        tuning.mouseAcceleration = 0.5
        XCTAssertEqual(tuning.mouseAccelerationExponent, 2.0, accuracy: 1e-9)
        tuning.scrollAcceleration = 1.0
        XCTAssertEqual(tuning.scrollAccelerationExponent, 2.5, accuracy: 1e-9)
    }
}
