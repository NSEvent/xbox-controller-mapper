import XCTest
@testable import ControllerKeys

@MainActor
final class CommunityTouchpadProfilesTests: XCTestCase {
	private var library: URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent("community-profiles")
	}

	private func load(_ name: String) throws -> Profile {
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		return try decoder.decode(Profile.self, from: Data(contentsOf: library.appendingPathComponent(name)))
	}

	func testGeneralProfilesKeepDefaultTouchpadTuningThroughImportAndMigration() throws {
		let specialized: Set<String> = ["Anki - AnKing (USMLE).json", "Codex Micro - Apple TV Remote.json"]
		let files = try FileManager.default.contentsOfDirectory(at: library, includingPropertiesForKeys: nil)
			.filter { $0.pathExtension == "json" && !specialized.contains($0.lastPathComponent) }
		XCTAssertGreaterThanOrEqual(files.count, 38)
		let baseline = Profile.createDefault().joystickSettings
		let buttons: [ControllerButton] = [.touchpadButton, .touchpadTap, .rightTouchpadButton, .rightTouchpadTap]
		for file in files {
			let profile = ProfileTransferService.prepareForImport(try load(file.lastPathComponent))
			let (profiles, migrated) = ProfileConfigurationMigrationService.migrateTouchpadSettingsIfNeeded(in: [profile])
			XCTAssertFalse(migrated, file.lastPathComponent)
			let settings = try XCTUnwrap(profiles.first).joystickSettings
			XCTAssertEqual(settings.touchpadSensitivity, baseline.touchpadSensitivity, file.lastPathComponent)
			XCTAssertEqual(settings.touchpadAcceleration, baseline.touchpadAcceleration, file.lastPathComponent)
			XCTAssertEqual(settings.touchpadDeadzone, baseline.touchpadDeadzone, file.lastPathComponent)
			XCTAssertEqual(settings.touchpadSmoothing, baseline.touchpadSmoothing, file.lastPathComponent)
			XCTAssertEqual(settings.touchpadPanSensitivity, baseline.touchpadPanSensitivity, file.lastPathComponent)
			XCTAssertEqual(settings.touchpadZoomToPanRatio, baseline.touchpadZoomToPanRatio, file.lastPathComponent)
			XCTAssertEqual(settings.requireActiveTouchForRegionClick, baseline.requireActiveTouchForRegionClick)
			XCTAssertEqual(settings.touchpadInvertScrollX, baseline.touchpadInvertScrollX)
			XCTAssertEqual(settings.touchpadInvertScrollY, baseline.touchpadInvertScrollY)
			XCTAssertEqual(settings.touchpadUseNativeZoom, baseline.touchpadUseNativeZoom)
			XCTAssertFalse(settings.disableTouchpadAsMouse, file.lastPathComponent)
			for button in buttons {
				XCTAssertEqual(profile.buttonMappings[button]?.keyCode, KeyCodeMapping.mouseLeftClick, file.lastPathComponent)
				XCTAssertEqual(profile.buttonMappings[button]?.isHoldModifier, true, file.lastPathComponent)
			}
		}
	}

	func testSpecializedProfilesKeepTheirTouchpadActions() throws {
		let anking = try load("Anki - AnKing (USMLE).json")
		XCTAssertTrue(anking.joystickSettings.disableTouchpadAsMouse)
		XCTAssertEqual(anking.touchpadInputMode, .quadrants)
		XCTAssertEqual(anking.buttonMappings[.touchpadRegionBottomRightClick]?.keyCode, 15)
		let remote = try load("Codex Micro - Apple TV Remote.json")
		XCTAssertTrue(remote.joystickSettings.disableTouchpadAsMouse)
		XCTAssertEqual(remote.buttonMappings[.touchpadButton]?.keyCode, 61714)
	}

	func testPhotoMechanicImportsSelfContainedKeepMacroAndRatingReset() throws {
		let profile = ProfileTransferService.prepareForImport(try load("Photo Mechanic Culling.json"))
		XCTAssertFalse(profile.isDefault)
		XCTAssertEqual(profile.linkedApps, ["com.camerabits.PhotoMechanic"])
		XCTAssertFalse(ProfileImportSafetyAuditor.audit(profile).requiresUserConfirmation)
		let reset = try XCTUnwrap(profile.buttonMappings[.leftTrigger])
		XCTAssertEqual(reset.keyCode, 29)
		XCTAssertTrue(reset.modifiers.control)
		let keepID = try XCTUnwrap(profile.buttonMappings[.a]?.macroId)
		let keep = try XCTUnwrap(profile.macros.first { $0.id == keepID })
		XCTAssertEqual(keep.steps.count, 3)
		guard case .press(let rate) = keep.steps[0], case .delay(let delay) = keep.steps[1],
			case .press(let next) = keep.steps[2] else { return XCTFail("Keep must rate, wait, then advance") }
		XCTAssertEqual(rate.keyCode, 23)
		XCTAssertTrue(rate.modifiers.control)
		XCTAssertEqual(delay, 0.15)
		XCTAssertEqual(next.keyCode, 124)
	}
}
