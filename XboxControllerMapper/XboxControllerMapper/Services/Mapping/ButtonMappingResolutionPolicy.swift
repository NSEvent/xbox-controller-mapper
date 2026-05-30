import Foundation

/// Resolves the effective button mapping for the current profile + layer context.
enum ButtonMappingResolutionPolicy {
    static func resolve(
        button: ControllerButton,
        profile: Profile,
        activeLayerIds: [UUID],
        layerActivatorMap: [ControllerButton: UUID]
    ) -> KeyMapping? {
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
			if let mapping = firstFallbackMapping(for: button, in: layer.buttonMappings) {
				return mapping
			}
		}

		if let mapping = profile.buttonMappings[button] {
			return mapping.isEmpty ? nil : mapping
		}

		if let mapping = firstFallbackMapping(for: button, in: profile.buttonMappings) {
			return mapping
		}

        return defaultMapping(for: button)
    }

	private static func nonEmptyMapping(
		for button: ControllerButton,
		in mappings: [ControllerButton: KeyMapping]
	) -> KeyMapping? {
		guard let mapping = mappings[button], !mapping.isEmpty else { return nil }
		return mapping
	}

	private static func firstFallbackMapping(
		for button: ControllerButton,
		in mappings: [ControllerButton: KeyMapping]
	) -> KeyMapping? {
		for fallbackButton in button.mappingFallbackButtons {
			if let mapping = nonEmptyMapping(for: fallbackButton, in: mappings) {
				return mapping
			}
		}
		return nil
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
