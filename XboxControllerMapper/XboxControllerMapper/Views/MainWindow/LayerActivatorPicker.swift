import SwiftUI

enum LayerActivatorOptions {
	static func buttons(for descriptor: ControllerVisualDescriptor, excluding used: Set<ControllerButton>) -> [ControllerButton] {
		let supported = descriptor.supportedButtons.filter { !$0.isGestureButton && !$0.isJoystickDirection && !used.contains($0) }
		let preferred: [ControllerButton] = [.leftBumper, .rightBumper, .leftTrigger, .rightTrigger,
			.share, .view, .menu, .xbox, .leftThumbstick, .rightThumbstick, .xiaomiMenu, .xiaomiHome]
		return preferred.filter { supported.contains($0) }
			+ ControllerButton.allCases.filter { supported.contains($0) && !preferred.contains($0) }
	}

	static func reconciled(_ selection: ControllerButton?, options: [ControllerButton], existing: ControllerButton?) -> ControllerButton? {
		guard let selection else { return nil }
		return options.contains(selection) || selection == existing ? selection : nil
	}
}

/// Both layer sheets use the same selected-device controls and labels as Buttons.
struct LayerActivatorPicker: View {
	@Binding var selection: ControllerButton?
	let descriptor: ControllerVisualDescriptor
	let used: Set<ControllerButton>
	var existing: ControllerButton? = nil

	private var options: [ControllerButton] { LayerActivatorOptions.buttons(for: descriptor, excluding: used) }

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(descriptor.displayName).font(.caption).foregroundStyle(.secondary)
			Picker("Activator", selection: $selection) {
				Text("None (assign later)").tag(nil as ControllerButton?)
				// Preserve an existing assignment when editing a layer from another
				// device. Renaming a layer must not silently remove its activator.
				if let existing, !options.contains(existing) {
					Text("\(existing.displayName) (existing assignment)").tag(existing as ControllerButton?)
				}
				ForEach(options, id: \.self) { button in
					Text(descriptor.buttonLabel(button)).tag(button as ControllerButton?)
				}
			}
			.pickerStyle(.menu)
		}
		.onChange(of: options) { _, options in
			selection = LayerActivatorOptions.reconciled(selection, options: options, existing: existing)
		}
	}
}
