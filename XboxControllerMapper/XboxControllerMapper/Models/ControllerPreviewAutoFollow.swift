import Foundation

/// The connection display is not an event source: an auxiliary pedal can send
/// input while Xiaomi or a gamepad remains the primary connected device.
enum ControllerPreviewAutoFollow {
	static func layout(
		button: ControllerButton,
		source: ControllerPreviewLayout?,
		activeDescriptor: ControllerVisualDescriptor
	) -> ControllerPreviewLayout? {
		guard !button.isGestureButton, !button.isJoystickDirection else { return nil }
		if let source, source != .active { return source }
		// Dedicated button identities also preserve provenance for services that
		// predate explicit source tagging. Shared controls (e.g. D-pad) must tag.
		if button.isFootPedalOnly { return .footPedal }
		if button.isXiaomiRemoteOnly { return .xiaomiRemote }
		if button.isS29RingOnly { return .s29Ring }
		if button.isOuraRingOnly { return .ouraRing }
		if button.isBeamdeskHandOnly { return .beamdeskHands }
		return ControllerPreviewLayout.concreteLayouts.first {
			ControllerVisualDescriptor.concrete(for: $0)?.family == activeDescriptor.family
		}
	}
}
