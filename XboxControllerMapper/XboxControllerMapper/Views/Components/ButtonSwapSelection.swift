import Foundation

/// The swap tool's two-pick flow, shared by on-screen clicks and physical
/// input capture so both pick swap buttons the same way.
enum ButtonSwapSelection {
	/// Records `button` as the next pick. Once both are chosen, disarms swap
	/// mode and returns the pair to swap.
	static func pick(
		_ button: ControllerButton,
		first: inout ControllerButton?,
		isSwapMode: inout Bool
	) -> (ControllerButton, ControllerButton)? {
		guard let firstButton = first else {
			first = button
			return nil
		}
		first = nil
		isSwapMode = false
		return (firstButton, button)
	}

	/// On remotes, several physical buttons share one binding; swaps act on
	/// the binding button.
	@MainActor
	static func bindingButton(
		for button: ControllerButton,
		descriptor: ControllerVisualDescriptor,
		profile: Profile?,
		layerId: UUID?
	) -> ControllerButton {
		guard descriptor.isXiaomiRemote || descriptor.isAppleTVRemote else { return button }
		return RemoteButtonEquivalence.bindingButton(for: button, profile: profile, layerId: layerId)
	}

	@MainActor
	static func apply(_ pair: (ControllerButton, ControllerButton), layerId: UUID?, profileManager: ProfileManager) {
		if let layerId {
			profileManager.swapLayerMappings(button1: pair.0, button2: pair.1, in: layerId)
		} else {
			profileManager.swapMappings(button1: pair.0, button2: pair.1)
		}
	}
}
