import SwiftUI

struct MIDIControlChangeEditor: View {
	@Binding var message: MIDIControlChange

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text("Sends from the virtual MIDI source “\(VirtualMIDIService.sourceName)”.")
				.font(.caption)
				.foregroundColor(.secondary)

			HStack(spacing: 20) {
				Stepper("Channel \(message.channel)", value: $message.channel, in: 1...16)
				Stepper("CC \(message.controller)", value: $message.controller, in: 0...127)
			}

			HStack(spacing: 20) {
				Stepper("Press \(message.pressValue)", value: $message.pressValue, in: 0...127)
				Stepper("Release \(message.releaseValue)", value: $message.releaseValue, in: 0...127)
			}

			if let warning = message.controllerWarning {
				Label(warning, systemImage: "exclamationmark.triangle.fill")
					.font(.caption)
					.foregroundColor(.orange)
			}

			Button {
				VirtualMIDIService.shared.pulse(message)
			} label: {
				Label("Send Test", systemImage: "waveform")
			}
			.controlSize(.small)
		}
	}
}
