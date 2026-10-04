import SwiftUI

struct GuidedPresetReviewView: View {
	let profile: Profile
	@EnvironmentObject private var controller: ControllerService
	@StateObject private var input = PhysicalButtonReviewSession()
	private var descriptor: ControllerVisualDescriptor { ControllerVisualDescriptor.inputWorkflow(profile: profile, using: controller) }
	private var buttons: [ControllerButton] { profile.buttonMappings.keys.sorted { $0.rawValue < $1.rawValue } }
	private var prompt: String {
		if !controller.isConnected { return "Connect a controller to explore these controls. You can also review the list below." }
		if !input.held.isEmpty { return "Holding: " + input.held.sorted { $0.rawValue < $1.rawValue }.map { descriptor.buttonLabel($0) }.joined(separator: " + ") }
		if let next = buttons.first(where: { !input.seen.contains($0) }) {
			return "Try pressing \(descriptor.buttonLabel(next)): \(profile.buttonMappings[next]?.hint ?? "see its action")."
		}
		return "You've explored every mapped button. Press any again, or hold several together."
	}
	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Label(prompt, systemImage: "gamecontroller").font(.callout.weight(.medium))
			Text("Press one button or hold several together to highlight their rows. No actions run during this review.").font(.caption).foregroundStyle(.secondary)
			ForEach(buttons, id: \.self) { button in
				HStack {
					Text(descriptor.buttonLabel(button)).frame(width: 110, alignment: .leading)
					Text(profile.buttonMappings[button]?.hint ?? "")
					Spacer()
					Text(profile.buttonMappings[button]?.displayString ?? "").foregroundStyle(.secondary)
				}.font(.callout).padding(8)
				.background(input.held.contains(button) ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
				.overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(input.held.contains(button) ? Color.accentColor : .clear))
				.accessibilityElement(children: .combine)
				.accessibilityValue(input.held.contains(button) ? "Pressed" : "Released")
			}
			let unmapped = input.held.subtracting(Set(buttons))
			if !unmapped.isEmpty { Text(unmapped.map { descriptor.buttonLabel($0) }.sorted().joined(separator: " + ") + ": no action in this preset.").font(.caption).foregroundStyle(.secondary) }
		}
		.onAppear { input.start(controller: controller) }
		.onDisappear { input.stop() }
	}
}
