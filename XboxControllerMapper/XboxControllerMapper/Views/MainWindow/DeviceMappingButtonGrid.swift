import SwiftUI

extension ControllerVisualDescriptor {
	/// These devices do not fit the standard two-stick gamepad diagram.
	var usesCompactMappingButtonGrid: Bool { !hasSticks || eightBitDoModel != nil }

	func mappingPickerButtons(joystickSettings: JoystickSettings) -> [ControllerButton] {
		var buttons = supportedButtons.filter { !$0.isJoystickDirection && !$0.isGestureButton }
		if hasSticks {
			buttons.formUnion(joystickSettings.chordSequenceJoystickDirectionButtons(side: .left))
			buttons.formUnion(joystickSettings.chordSequenceJoystickDirectionButtons(side: .right))
		}
		return ControllerButton.allCases.filter { buttons.contains($0) }
	}
}

/// Shared by the chord and sequence sheets. In particular, a foot pedal must
/// expose its three actual pedal inputs, never the generic Xbox diagram.
struct DeviceMappingButtonGrid<Control: View>: View {
	let descriptor: ControllerVisualDescriptor
	let joystickSettings: JoystickSettings
	@ViewBuilder let control: (ControllerButton) -> Control

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text(descriptor.displayName).font(.subheadline.weight(.medium))
			LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 16)], spacing: 20) {
				ForEach(descriptor.mappingPickerButtons(joystickSettings: joystickSettings), id: \.self) { button in
					VStack(spacing: 10) {
						control(button).frame(minHeight: 36)
						Text(descriptor.buttonLabel(button)).font(.caption)
					}
					.frame(maxWidth: .infinity)
				}
			}
		}
		.padding(.vertical, 16)
		.frame(maxWidth: .infinity)
	}
}
