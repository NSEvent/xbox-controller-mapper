import SwiftUI

struct AnalogTriggerPrecisionSettingsView: View {
	@EnvironmentObject private var profileManager: ProfileManager

	private var settings: JoystickSettings {
		profileManager.activeProfile?.joystickSettings ?? .default
	}

	var body: some View {
		Section("Trigger Cursor Slowdown") {
			VStack(alignment: .leading, spacing: 6) {
				Text("Hold a trigger for finer mouse control. Squeeze further to move slower; release to return to normal speed.")
				Text("Applies to joystick and controller touchpad mouse movement, even while the on-screen keyboard is open. No modifier key is needed.")
					.foregroundStyle(.secondary)
			}
			.font(.callout)
			.fixedSize(horizontal: false, vertical: true)

			Picker("Slowdown Trigger", selection: binding(\.analogPrecisionTriggerMode)) {
				ForEach(AnalogPrecisionTriggerMode.allCases, id: \.self) { mode in
					Text(LocalizedStringKey(mode.displayName)).tag(mode)
				}
			}
			.pickerStyle(.segmented)

			if settings.analogPrecisionTriggerMode == .off {
				Text("Off: trigger pressure does not change cursor speed.")
					.font(.caption)
					.foregroundStyle(.secondary)
			} else {
				ForEach(warnings, id: \.self) { warning in
					Label {
						Text(warning)
							.fixedSize(horizontal: false, vertical: true)
					} icon: {
						Image(systemName: "exclamationmark.triangle.fill")
							.foregroundStyle(.orange)
					}
					.font(.callout)
				}

				VStack(alignment: .leading, spacing: 4) {
					HStack {
						Text("Speed at Full Pull")
						Spacer()
						Text(settings.analogPrecisionMinimumSpeed, format: .percent.precision(.fractionLength(0)))
							.monospacedDigit()
					}
					Slider(value: binding(\.analogPrecisionMinimumSpeed), in: 0.05...1.0)
						.accessibilityLabel("Speed at Full Pull")
						.accessibilityValue(settings.analogPrecisionMinimumSpeed.formatted(.percent.precision(.fractionLength(0))))
					Text("Percentage of normal cursor speed. For example, 5% is 20 times slower. Releasing the trigger restores normal speed.")
						.font(.caption)
						.foregroundStyle(.secondary)
						.fixedSize(horizontal: false, vertical: true)
				}

				SliderRow(
					label: "Trigger Deadzone",
					value: binding(\.analogPrecisionDeadzone),
					range: 0...0.5,
					description: "Ignore light trigger presses before slowing the cursor"
				)
				SliderRow(
					label: "Trigger Curve",
					value: binding(\.analogPrecisionCurve),
					range: 0...1,
					description: "Higher values keep more speed until the trigger is nearly fully pressed"
				)
			}
		}
	}

	private func binding<Value>(_ keyPath: WritableKeyPath<JoystickSettings, Value>) -> Binding<Value> {
		Binding(
			get: { settings[keyPath: keyPath] },
			set: { value in
				var updated = settings
				updated[keyPath: keyPath] = value
				profileManager.updateJoystickSettings(updated)
			}
		)
	}

	private var selectedTriggers: [ControllerButton] {
		switch settings.analogPrecisionTriggerMode {
		case .off: return []
		case .left: return [.leftTrigger]
		case .right: return [.rightTrigger]
		case .either: return [.leftTrigger, .rightTrigger]
		}
	}

	private var warnings: [String] {
		var messages: [String] = []
		for trigger in selectedTriggers {
			guard let mapping = profileManager.activeProfile?.buttonMappings[trigger], !mapping.isEmpty else { continue }
			let name = trigger == .leftTrigger ? "L2 / LT" : "R2 / RT"
			if mapping.keyCode == KeyCodeMapping.showOnScreenKeyboard {
				messages.append(String(format: String(localized: "%@ also opens the on-screen keyboard. Pulling it slows the cursor across the desktop, too. Choose Off or another trigger to keep normal speed while using the keyboard."), name))
			} else {
				messages.append(String(format: String(localized: "%@ also has a button action. Pulling it will slow the cursor and run that action."), name))
			}
		}
		if selectedTriggers.contains(.leftTrigger), profileManager.onScreenKeyboardSettings.swipeTypingEnabled {
			messages.append(String(localized: "L2 / LT also activates swipe typing. Holding it slows normal cursor movement before you start a swipe."))
		}
		return messages
	}
}
