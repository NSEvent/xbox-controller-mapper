import SwiftUI
import TriggerKitCore

struct TextEntryModeSelector: View {
	@Binding var selection: TextEntryMode

	var body: some View {
		HStack(spacing: 6) {
			modeButton(.paste, label: "Paste")
			modeButton(.type, label: "Type")
		}
	}

	private func modeButton(_ mode: TextEntryMode, label: String) -> some View {
		let selected = selection == mode
		return Button {
			selection = mode
		} label: {
			Text(label)
				.font(.caption.weight(.bold))
				.frame(maxWidth: .infinity)
				.frame(height: 28)
				.background(selected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
				.foregroundStyle(selected ? .white : .primary)
				.clipShape(RoundedRectangle(cornerRadius: 6))
				.overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Color.accentColor : Color.gray.opacity(0.25)))
		}
		.buttonStyle(.plain)
	}
}
