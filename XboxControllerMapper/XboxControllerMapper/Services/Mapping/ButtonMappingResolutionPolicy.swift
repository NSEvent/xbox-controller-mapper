import Foundation

/// Resolves the effective button mapping for the current profile + layer context.
enum ButtonMappingResolutionPolicy {
	static func resolvedButton(
		button: ControllerButton,
		profile: Profile,
		activeLayerIds: [UUID],
		layerActivatorMap: [ControllerButton: UUID]
	) -> ControllerButton {
		guard let logicalButton = button.logicalEquivalent else { return button }
		let activeLayer = activeLayerIds.last.flatMap { activeLayerId in
			profile.layers.first(where: { $0.id == activeLayerId })
		}
		if activeLayer?.buttonMappings[button] != nil {
			return button
		}
		if activeLayer?.buttonMappings[logicalButton] != nil {
			return logicalButton
		}
		if layerActivatorMap[button] != nil {
			return button
		}
		if layerActivatorMap[logicalButton] != nil {
			return logicalButton
		}
		if shouldPreservePhysicalButton(button, profile: profile) {
			return button
		}
		return logicalButton
	}

    static func resolve(
        button: ControllerButton,
        profile: Profile,
        activeLayerIds: [UUID],
        layerActivatorMap: [ControllerButton: UUID]
    ) -> KeyMapping? {
		let button = resolvedButton(
			button: button,
			profile: profile,
			activeLayerIds: activeLayerIds,
			layerActivatorMap: layerActivatorMap
		)

        // Layer activator handling: context-aware.
        if let activatorLayerId = layerActivatorMap[button] {
            // If this button's own layer is currently active (being held), consume it.
            if activeLayerIds.contains(activatorLayerId) {
                return nil
            }
            // If no layer is active, consume it (it will activate its layer).
            if activeLayerIds.isEmpty {
                return nil
            }
            // A different layer is active — fall through to check if the active layer
            // has a mapping for this button (allows remapping activators within layers).
        }

        // Only the most recently activated layer is considered active.
        if let activeLayerId = activeLayerIds.last,
		   let layer = profile.layers.first(where: { $0.id == activeLayerId }) {
			if let mapping = nonEmptyMapping(for: button, in: layer.buttonMappings) {
				return mapping
			}
		}

		if let mapping = profile.buttonMappings[button] {
			return mapping.isEmpty ? nil : mapping
		}

        return defaultMapping(for: button)
    }

	private static func shouldPreservePhysicalButton(
		_ button: ControllerButton,
		profile: Profile
	) -> Bool {
		if profile.buttonMappings[button] != nil {
			return true
		}
		if profile.chordMappings.contains(where: { $0.buttons.contains(button) }) {
			return true
		}
		if profile.sequenceMappings.contains(where: { $0.steps.contains(button) }) {
			return true
		}
		return false
	}

	private static func nonEmptyMapping(
		for button: ControllerButton,
		in mappings: [ControllerButton: KeyMapping]
	) -> KeyMapping? {
		guard let mapping = mappings[button], !mapping.isEmpty else { return nil }
		return mapping
	}

    /// Hardcoded resolver fallback. Historically returned a "trackpad-like"
    /// default (left/right mouse click) for touchpad buttons even when the
    /// user had explicitly cleared the mapping — making it impossible to
    /// disable touchpad clicks. Now `nil` for everything: an absent mapping
    /// means no action. New users still get sensible click behavior because
    /// `Profile.createDefault()` populates the four touchpad buttons
    /// explicitly; clearing them in the UI is the way to disable.
    private static func defaultMapping(for button: ControllerButton) -> KeyMapping? {
        return nil
    }
}
