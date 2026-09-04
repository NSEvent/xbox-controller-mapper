import XCTest
@testable import ControllerKeys

final class LayerLEDSettingsPolicyTests: XCTestCase {
	func testColorEditPreservesHiddenLEDFields() throws {
		let original = DualSenseLEDSettings(
			lightBarColor: CodableColor(red: 1, green: 0, blue: 0),
			lightBarBrightness: .dim,
			lightBarEnabled: false,
			muteButtonLED: .breathing,
			playerLEDs: .player3,
			batteryLightBar: true
		)
		let replacementColor = CodableColor(red: 0, green: 1, blue: 0)
		let updated = try XCTUnwrap(LayerLEDSettingsPolicy.applyingColorEdit(
			to: original,
			isEnabled: true,
			color: replacementColor,
			didEditColor: true
		))

		XCTAssertEqual(updated.lightBarColor, replacementColor)
		XCTAssertTrue(updated.lightBarEnabled)
		XCTAssertEqual(updated.lightBarBrightness, .dim)
		XCTAssertEqual(updated.muteButtonLED, .breathing)
		XCTAssertEqual(updated.playerLEDs, .player3)
		XCTAssertFalse(updated.batteryLightBar)
	}

	func testSavingCompactEditorWithoutChangingColorPreservesExistingSettings() throws {
		let original = DualSenseLEDSettings(
			lightBarColor: CodableColor(red: 1, green: 0, blue: 0),
			lightBarBrightness: .dim,
			lightBarEnabled: false,
			muteButtonLED: .breathing,
			playerLEDs: .player3,
			batteryLightBar: true
		)
		let updated = try XCTUnwrap(LayerLEDSettingsPolicy.applyingColorEdit(
			to: original,
			isEnabled: true,
			color: CodableColor(red: 0, green: 1, blue: 0),
			didEditColor: false
		))

		XCTAssertEqual(updated, original)
	}

	func testDisablingLayerLEDOverrideRemovesIt() {
		XCTAssertNil(LayerLEDSettingsPolicy.applyingColorEdit(
			to: .default,
			isEnabled: false,
			color: CodableColor(red: 0, green: 0, blue: 1),
			didEditColor: false
		))
	}

	func testOnlyRuntimeEffectiveScopePreviewsOnPhysicalController() {
		let activeProfileId = UUID()
		let runtimeLayerId = UUID()

		XCTAssertTrue(LayerLEDSettingsPolicy.shouldPreviewOnController(
			editingProfileId: activeProfileId,
			activeProfileId: activeProfileId,
			editingLayerId: runtimeLayerId,
			activeRuntimeLayerId: runtimeLayerId,
			isControllerLocked: false
		))
		XCTAssertTrue(LayerLEDSettingsPolicy.shouldPreviewOnController(
			editingProfileId: activeProfileId,
			activeProfileId: activeProfileId,
			editingLayerId: nil,
			activeRuntimeLayerId: nil,
			isControllerLocked: false
		))
		XCTAssertFalse(LayerLEDSettingsPolicy.shouldPreviewOnController(
			editingProfileId: activeProfileId,
			activeProfileId: activeProfileId,
			editingLayerId: UUID(),
			activeRuntimeLayerId: runtimeLayerId,
			isControllerLocked: false
		))
		XCTAssertFalse(LayerLEDSettingsPolicy.shouldPreviewOnController(
			editingProfileId: activeProfileId,
			activeProfileId: activeProfileId,
			editingLayerId: nil,
			activeRuntimeLayerId: runtimeLayerId,
			isControllerLocked: false
		))
		XCTAssertFalse(LayerLEDSettingsPolicy.shouldPreviewOnController(
			editingProfileId: UUID(),
			activeProfileId: activeProfileId,
			editingLayerId: nil,
			activeRuntimeLayerId: nil,
			isControllerLocked: false
		))
		XCTAssertFalse(LayerLEDSettingsPolicy.shouldPreviewOnController(
			editingProfileId: activeProfileId,
			activeProfileId: activeProfileId,
			editingLayerId: runtimeLayerId,
			activeRuntimeLayerId: runtimeLayerId,
			isControllerLocked: true
		))
	}
}
