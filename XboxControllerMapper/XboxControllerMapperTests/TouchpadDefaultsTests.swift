import XCTest
@testable import ControllerKeys

@MainActor
final class TouchpadDefaultsTests: XCTestCase {
	private func assertBaseline(_ settings: JoystickSettings, file: StaticString = #filePath, line: UInt = #line) {
		XCTAssertEqual(settings.touchpadSensitivity, 0.49725684691011235, file: file, line: line)
		XCTAssertEqual(settings.touchpadAcceleration, 0.5011192064606742, file: file, line: line)
		XCTAssertEqual(settings.touchpadDeadzone, 0.0013147384129213483, file: file, line: line)
		XCTAssertEqual(settings.touchpadSmoothing, 0.40300649578651687, file: file, line: line)
		XCTAssertEqual(settings.touchpadPanSensitivity, 0.4986064782303371, file: file, line: line)
		XCTAssertEqual(settings.touchpadZoomToPanRatio, 1.9511488325140447, file: file, line: line)
		XCTAssertFalse(settings.requireActiveTouchForRegionClick, file: file, line: line)
		XCTAssertFalse(settings.disableTouchpadAsMouse, file: file, line: line)
		XCTAssertFalse(settings.touchpadInvertScrollX, file: file, line: line)
		XCTAssertFalse(settings.touchpadInvertScrollY, file: file, line: line)
		XCTAssertTrue(settings.touchpadUseNativeZoom, file: file, line: line)
	}

	func testFirstRunAndNewProfileUseExactCalibratedBaseline() {
		assertBaseline(JoystickSettings())
		assertBaseline(Profile(name: "New app").joystickSettings)
		let firstRun = Profile.createDefault()
		assertBaseline(firstRun.joystickSettings)
		let buttons: [ControllerButton] = [.touchpadButton, .touchpadTap, .rightTouchpadButton, .rightTouchpadTap]
		for button in buttons {
			XCTAssertEqual(firstRun.buttonMappings[button]?.keyCode, KeyCodeMapping.mouseLeftClick)
			XCTAssertEqual(firstRun.buttonMappings[button]?.isHoldModifier, true)
		}
	}

	func testMissingFieldsAndRoundTripUseSameBaseline() throws {
		assertBaseline(try JSONDecoder().decode(JoystickSettings.self, from: Data("{}".utf8)))
		let profile = Profile.createDefault()
		let decoded = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(profile))
		assertBaseline(decoded.joystickSettings)
		let (loaded, migrated) = ProfileConfigurationMigrationService.migrateTouchpadSettingsIfNeeded(in: [decoded])
		XCTAssertFalse(migrated)
		assertBaseline(try XCTUnwrap(loaded.first).joystickSettings)
	}

	func testExplicitSavedTuningSurvivesDecodeAndLoad() throws {
		// Includes the previous shipping baseline: upgrading must not retune it.
		for deadzone in [0.005, 0.017] {
			var custom = JoystickSettings()
			custom.touchpadSensitivity = 0.5
			custom.touchpadAcceleration = 0.5
			custom.touchpadDeadzone = deadzone
			custom.touchpadSmoothing = 0.4
			custom.touchpadPanSensitivity = 0.7
			custom.touchpadZoomToPanRatio = 2.5
			custom.requireActiveTouchForRegionClick = true
			custom.disableTouchpadAsMouse = true
			custom.touchpadInvertScrollX = true
			custom.touchpadInvertScrollY = true
			custom.touchpadUseNativeZoom = false
			let profile = Profile(name: "Custom", joystickSettings: custom)
			let decoded = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(profile))
			let (loaded, migrated) = ProfileConfigurationMigrationService.migrateTouchpadSettingsIfNeeded(in: [decoded])
			XCTAssertFalse(migrated)
			XCTAssertEqual(loaded.first?.joystickSettings, custom)
		}
	}
}
