import Foundation

/// Applies the compact layer-sheet color edit without resetting LED fields the
/// compact sheet does not expose.
enum LayerLEDSettingsPolicy {
	static func applyingColorEdit(
		to existing: DualSenseLEDSettings?,
		isEnabled: Bool,
		color: CodableColor,
		didEditColor: Bool
	) -> DualSenseLEDSettings? {
		guard isEnabled else { return nil }
		guard existing == nil || didEditColor else { return existing }
		var settings = existing ?? DualSenseLEDSettings()
		settings.lightBarEnabled = true
		settings.batteryLightBar = false
		settings.lightBarColor = color
		return settings
	}

	static func shouldPreviewOnController(
		editingProfileId: UUID?,
		activeProfileId: UUID?,
		editingLayerId: UUID?,
		activeRuntimeLayerId: UUID?,
		isControllerLocked: Bool
	) -> Bool {
		guard !isControllerLocked else { return false }
		guard let editingProfileId, editingProfileId == activeProfileId else { return false }
		return editingLayerId == activeRuntimeLayerId
	}
}
