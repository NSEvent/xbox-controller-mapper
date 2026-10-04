import SwiftUI

struct TriggerMIDIEditor: View {
	let title: String
	var side: JoystickSide = .left
	var otherConfiguration: TriggerMIDIConfiguration? = nil
	@Binding var configuration: TriggerMIDIConfiguration?
	@EnvironmentObject private var controller: ControllerService
	@EnvironmentObject private var engine: MappingEngine
	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Toggle(title, isOn: Binding(get: { configuration != nil }, set: { configuration = $0 ? TriggerMIDIConfiguration.suggested(for: side, avoiding: otherConfiguration) : nil }))
				.disabled(controller.isConnected && !ControllerVisualDescriptor.inputWorkflow(profile: engine.profileManager.activeProfile, using: controller).hasTriggers && configuration == nil)
			if let config = configuration {
				TimelineView(.periodic(from: .now, by: 1 / 30)) { _ in
					let input = controller.snapshot()
					let raw = side == .left ? Double(input.leftTrigger) : Double(input.rightTrigger)
					let stream = engine.triggerMIDIOutput.snapshot(for: side == .left ? 0 : 1)
					HStack {
						Text("Pressure \(Int((raw * 100).rounded()))% → calculated CC \(config.value(for: raw))").monospacedDigit()
						Spacer()
						Text(!controller.isConnected ? "Disconnected" : !engine.isEnabled || engine.isLocked || engine.inputPreviewCount > 0 ? "Output paused" : stream?.armed == true ? "Sent CC \(stream?.value ?? config.value(for: 0))" : "Release trigger to activate")
							.font(.caption).foregroundStyle(.secondary)
					}
				}
				HStack {
					Stepper("Channel \(config.message.channel)", value: field(\.message.channel), in: 1...16)
					Stepper("CC \(config.message.controller)", value: field(\.message.controller), in: 0...127)
				}
				HStack {
					Stepper("Minimum \(config.message.releaseValue)", value: field(\.message.releaseValue), in: 0...127)
					Stepper("Maximum \(config.message.pressValue)", value: field(\.message.pressValue), in: 0...127)
				}
				Toggle("Invert trigger", isOn: field(\.inverted))
				HStack { Text("Deadzone"); Slider(value: field(\.deadzone), in: 0...0.5); Text(config.deadzone, format: .percent.precision(.fractionLength(0))) }
				if let warning = config.message.controllerWarning { Text(warning).font(.caption).foregroundStyle(.orange) }
				Text("Release the trigger after changing profiles or resuming mapping to activate continuous output.")
					.font(.caption).foregroundStyle(.secondary)
			}
		}
	}
	private func field<T>(_ keyPath: WritableKeyPath<TriggerMIDIConfiguration, T>) -> Binding<T> {
		Binding(get: { (configuration ?? TriggerMIDIConfiguration())[keyPath: keyPath] },
				set: { value in guard var config = configuration else { return }; config[keyPath: keyPath] = value; configuration = config })
	}
}
