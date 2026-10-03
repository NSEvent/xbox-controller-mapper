import ApplicationServices
import SwiftUI

struct GuidedPresetSheet: View {
	@EnvironmentObject private var profiles: ProfileManager
	@EnvironmentObject private var controller: ControllerService
	@EnvironmentObject private var engine: MappingEngine
	@Environment(\.dismiss) private var dismiss
	@State private var preset = GuidedPreset.anki
	@State private var name = ""
	@State private var targetBundleId = ""
	@State private var linkApp = true
	@State private var showingAppPicker = false
	@State private var step = 0
	@State private var createdId: UUID?
	@State private var previewId: UUID?
	@State private var testing = false
	@State private var verified = false

	private var candidate: Profile { preset.makeProfile(name: name, targetBundleId: targetBundleId.isEmpty ? nil : targetBundleId, linkApp: linkApp) }
	private var ready: Bool { controller.isConnected && AXIsProcessTrusted() && engine.isEnabled && engine.inputPreviewCount == 0 && profiles.activeProfileId == createdId }
	private var targetAppName: String {
		guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: targetBundleId) else { return "Choose Installed App…" }
		return "Target: \(url.deletingPathExtension().lastPathComponent)"
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text(step == 0 ? "What do you want to do?" : step == 1 ? "Review your starting preset" : "Try one real action")
				.font(.title2.bold())
			Text("\(step + 1) of 3 · \(step < 2 ? "Mapped actions are paused during setup." : "Your new profile has been saved.")")
				.font(.caption).foregroundStyle(.secondary)
			if step == 0 { choices }
			if step == 1 { review }
			if step == 2 { test }
			Divider()
			HStack {
				Button(step == 2 ? "Finish Later" : "Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
				if step == 1 { Button("Back") { step = 0 } }
				Spacer()
				if step == 0 {
					Button("Review Preset") { step = 1 }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
				} else if step == 1 {
					Button("Create New Profile") { create() }.keyboardShortcut(.defaultAction)
				} else {
					Button("Done") { dismiss() }.disabled(!verified)
				}
			}
		}
		.padding(24).frame(width: 570)
		.onAppear { choose(preset); previewId = engine.beginInputPreview() }
		.onDisappear { if let previewId { engine.endInputPreview(previewId) } }
		.sheet(isPresented: $showingAppPicker) {
			SystemActionAppPickerSheet(currentBundleIdentifier: targetBundleId) { targetBundleId = $0.bundleIdentifier }
		}
	}

	private var choices: some View {
		VStack(alignment: .leading, spacing: 12) {
			ForEach(GuidedPreset.allCases) { option in
				Button { choose(option) } label: {
					HStack {
						Image(systemName: option.icon).frame(width: 24)
						Text(option.title)
						Spacer()
						if preset == option { Image(systemName: "checkmark.circle.fill") }
					}.padding(10).background(preset == option ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
				}.buttonStyle(.plain)
			}
			TextField("Profile name", text: $name)
			if preset != .oneHand {
				Button(targetAppName) { showingAppPicker = true }
				Toggle("Switch to this profile when the app comes forward", isOn: $linkApp).disabled(targetBundleId.isEmpty)
				if targetBundleId.isEmpty { Text("You can create the profile now and link an installed app later.").font(.caption).foregroundStyle(.secondary) }
			}
		}
	}

	private var review: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text(name).font(.headline)
			Text(preset.setupInstruction).font(.callout)
			ForEach(candidate.buttonMappings.keys.sorted { $0.rawValue < $1.rawValue }, id: \.self) { button in
				HStack {
					Text(button.shortLabel).frame(width: 90, alignment: .leading)
					Text(candidate.buttonMappings[button]?.hint ?? "")
					Spacer()
					Text(candidate.buttonMappings[button]?.displayString ?? "").foregroundStyle(.secondary)
				}.font(.callout)
			}
			Text("Creates a separate profile. You can customize any mapping with Press to Edit afterward.").font(.caption).foregroundStyle(.secondary)
		}
	}

	private var test: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text(preset.testInstruction).font(.headline)
			if !controller.isConnected { Text("Connect your controller before testing.").foregroundStyle(.orange) }
			if !AXIsProcessTrusted() {
				Button("Open Accessibility Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }
			}
			if !engine.isEnabled {
				Button("Enable Mapping for Test") { engine.enable() }
			}
			if !testing {
				Button("Start Testing") {
					if let previewId { engine.endInputPreview(previewId); self.previewId = nil }
					testing = true
				}
				Text("Release all controls, then bring the target app forward. Return here after seeing the action.").font(.caption)
			} else {
				if !targetBundleId.isEmpty, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: targetBundleId) {
					Button("Open Target App") { NSWorkspace.shared.openApplication(at: url, configuration: .init()) }
				}
				Button("I Saw the Expected Action") {
					verified = true
					if let createdId { UserDefaults.standard.set(Date(), forKey: "guidedPresetVerified.\(createdId)") }
				}.disabled(!ready)
				if engine.inputPreviewCount > 0 { Text("Release the buttons, triggers, and sticks to resume mapped output.").font(.caption).foregroundStyle(.orange) }
			}
			if verified { Label("Action confirmed by you.", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
		}
	}

	private func choose(_ option: GuidedPreset) {
		preset = option
		name = option.title
		targetBundleId = option.preferredBundleIds.first { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil } ?? ""
		linkApp = option != .oneHand
	}
	private func create() {
		let profile = profiles.createProfile(name: name.trimmingCharacters(in: .whitespacesAndNewlines), basedOn: candidate)
		profiles.setActiveProfile(profile)
		createdId = profile.id
		step = 2
	}
}
