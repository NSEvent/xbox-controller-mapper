import SwiftUI

/// Trigger analog output belongs to the triggers, independently of stick modes.
struct TriggerSettingsView: View {
	@EnvironmentObject private var profileManager: ProfileManager
	private var settings: JoystickSettings { profileManager.activeProfile?.joystickSettings ?? .default }
	var body: some View {
		Form {
			Section("Continuous Trigger MIDI") {
				TriggerMIDIEditor(title: "Left Trigger", side: .left, otherConfiguration: settings.rightTriggerMIDI, configuration: Binding(
					get: { settings.leftTriggerMIDI }, set: { updateSettings(\.leftTriggerMIDI, $0) }
				))
				TriggerMIDIEditor(title: "Right Trigger", side: .right, otherConfiguration: settings.leftTriggerMIDI, configuration: Binding(
					get: { settings.rightTriggerMIDI }, set: { updateSettings(\.rightTriggerMIDI, $0) }
				))
				Text("ControllerKeys sends continuous MIDI through its virtual MIDI source. Digital trigger actions still run when configured.")
					.font(.caption).foregroundStyle(.secondary)
				if let left = settings.leftTriggerMIDI, let right = settings.rightTriggerMIDI,
				   left.message.channel == right.message.channel, left.message.controller == right.message.controller {
					Text("Both triggers share a channel and CC number. Choose different numbers to control them independently.")
						.font(.caption).foregroundStyle(.orange)
				}
				TriggerMIDITools()
			}
			Section("Button Actions") {
				Text("Triggers can also run keyboard, mouse, Shortcut and other button actions. Configure those on the controller in Map → Buttons.")
					.font(.callout).foregroundStyle(.secondary)
			}
		}.formStyle(.grouped).padding()
	}
	private func updateSettings<T>(_ keyPath: WritableKeyPath<JoystickSettings, T>, _ value: T) {
		var updated = settings
		updated[keyPath: keyPath] = value
		profileManager.updateJoystickSettings(updated)
	}
}
