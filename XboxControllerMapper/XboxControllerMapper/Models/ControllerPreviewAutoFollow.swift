import Foundation

/// A manual preview stays selected until a fresh physical button press. Releases,
/// repeated held-state publications, connection changes and analog noise do not
/// change it. Select a concrete layout so later background hardware changes cannot
/// move the preview before the next deliberate press.
struct ControllerPreviewAutoFollow {
	private var previousButtons: Set<ControllerButton> = []

	mutating func receive(
		buttons: Set<ControllerButton>,
		isConnected: Bool,
		activeDescriptor: ControllerVisualDescriptor
	) -> ControllerPreviewLayout? {
		let physicalButtons = ControllerInputCapture.eligible(buttons)
		let fresh = physicalButtons.subtracting(previousButtons)
		previousButtons = physicalButtons
		guard isConnected, !fresh.isEmpty else { return nil }
		return ControllerPreviewLayout.concreteLayouts.first {
			ControllerVisualDescriptor.concrete(for: $0)?.family == activeDescriptor.family
		}
	}
}
