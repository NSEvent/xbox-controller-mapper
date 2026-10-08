import SwiftUI

struct GuidedPresetSheet: View {
	var resumeProfileId: UUID? = nil
	@EnvironmentObject private var profiles: ProfileManager
	@EnvironmentObject private var controller: ControllerService
	@EnvironmentObject private var engine: MappingEngine
	@Environment(\.dismiss) private var dismiss
	@ObservedObject private var permissions = PermissionsManager.shared
	@ObservedObject private var progress: GuidedPresetProgressStore
	@StateObject private var testSession = GuidedPresetTestSession()
	@State private var preset = GuidedPreset.anki
	@State private var hand = JoystickSide.left
	@State private var name = ""
	@State private var targetBundleId = ""
	@State private var linkApp = true
	@State private var useDefault = false
	@State private var showingAppPicker = false
	@State private var step = 0
	@State private var createdId: UUID?
	@State private var previewId: UUID?
	@State private var verified = false

	init(resumeProfileId: UUID? = nil, initialPreset: GuidedPreset = .anki, progress: GuidedPresetProgressStore = .shared) {
		self.resumeProfileId = resumeProfileId
		self.progress = progress
		_preset = State(initialValue: initialPreset)
	}

	private var candidate: Profile { preset.makeProfile(name: name, targetBundleId: targetBundleId.isEmpty ? nil : targetBundleId, linkApp: linkApp, hand: hand) }
	private var compatibleControls: Bool {
		let descriptor = ControllerVisualDescriptor.inputWorkflow(profile: profiles.activeProfile, using: controller)
		let buttons = savedProfile?.buttonMappings.keys ?? candidate.buttonMappings.keys
		return Set(buttons).isSubset(of: descriptor.supportedButtons) && (preset != .oneHand || descriptor.hasSticks)
	}
	private var savedProfile: Profile? { profiles.profiles.first { $0.id == createdId } }
	private var ready: Bool { createdId.map { testSession.isReady(profileId: $0, engine: engine, accessibilityGranted: permissions.accessibilityGranted) } ?? false }
	private var routingSaved: Bool { savedProfile.map { $0.isDefault || $0.linkedApps.contains(targetBundleId) } ?? false }
	private var targetAvailable: Bool { !targetBundleId.isEmpty && NSWorkspace.shared.urlForApplication(withBundleIdentifier: targetBundleId) != nil }
	private var targetAppName: String {
		guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: targetBundleId) else { return "Choose Installed App…" }
		return "Target: \(url.deletingPathExtension().lastPathComponent)"
	}
	private func label(_ button: ControllerButton) -> String {
		return ControllerVisualDescriptor.inputWorkflow(profile: profiles.activeProfile, using: controller).buttonLabel(button)
	}
	private var testInstruction: String {
		switch preset {
		case .anki: return "Open a review card in Anki. Press \(label(.a)) once: the answer should appear."
		case .photoCulling: return "Open a contact sheet or preview. Press \(label(.rightBumper)): selection should move to the next photo."
		case .finalCut: return "Open a timeline in Final Cut Pro. Press \(label(.a)): playback should start or pause."
		case .oneHand: return "Open a Finder window. Use the \(hand.rawValue) stick to move the pointer; press \(label(hand == .left ? .leftBumper : .rightBumper)) on a folder to select it."
		}
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			Text(step == 0 ? "What do you want to do?" : step == 1 ? "Review your starting preset" : "Try one real action").font(.title2.bold())
			Text("\(step + 1) of 3 · \(step < 2 ? "Mapped actions are paused during setup." : "Profile saved. Testing is optional; revisit it from Set Up → Test This Preset.")").font(.caption).foregroundStyle(.secondary)
			ScrollView {
				VStack(alignment: .leading, spacing: 14) {
					if step == 0 { choices }
					if step == 1 { review }
					if step == 2 { test }
				}.frame(maxWidth: .infinity, alignment: .leading).padding(4)
			}
			Divider()
			HStack {
				Button(step == 2 ? "Close" : "Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
				if step == 1 { Button("Back") { step = 0 } }
				Spacer()
				if step == 0 {
					Button("Review Preset") { step = 1 }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
				} else if step == 1 {
					Button("Create New Profile") { create() }.keyboardShortcut(.defaultAction)
				} else { Button("Done") { dismiss() } }
			}
		}.padding(24).frame(width: 620, height: 660)
		.onAppear { load(); permissions.startPolling() }
		.onDisappear { testSession.stop(); if let previewId { engine.endInputPreview(previewId) }; permissions.stopPolling() }
		.sheet(isPresented: $showingAppPicker) {
			SystemActionAppPickerSheet(currentBundleIdentifier: targetBundleId) {
				testSession.stop(); targetBundleId = $0.bundleIdentifier
				if let createdId { progress.save(.init(preset: preset, hand: hand, targetBundleId: targetBundleId), for: createdId) }
			}
		}
	}
	private var choices: some View {
		VStack(alignment: .leading, spacing: 12) {
			ForEach(GuidedPreset.allCases) { option in
				Button { choose(option) } label: {
					HStack {
						Image(systemName: option.icon).frame(width: 24); Text(option.title); Spacer()
						if preset == option { Image(systemName: "checkmark.circle.fill") }
					}.padding(10).background(preset == option ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
				}.buttonStyle(.plain)
			}
			VStack(alignment: .leading, spacing: 4) {
				Text("Profile name").font(.caption).foregroundStyle(.secondary)
				TextField("Profile name", text: $name).textFieldStyle(.roundedBorder)
			}
			if preset == .oneHand {
				Picker("Hand", selection: $hand) { Text("Left hand").tag(JoystickSide.left); Text("Right hand").tag(JoystickSide.right) }.pickerStyle(.segmented)
			} else {
				Button(targetAppName) { showingAppPicker = true }
				Toggle("Switch to this profile when the app comes forward", isOn: $linkApp).disabled(targetBundleId.isEmpty)
			}
			Toggle("Use as default in apps without a linked profile", isOn: $useDefault)
			if useDefault { Text("Replaces the current default profile for unlinked apps. Your existing profiles stay saved.").font(.caption).foregroundStyle(.secondary) }
			if !useDefault && (!linkApp || targetBundleId.isEmpty) { Text("This preset will need an app link or default assignment before its setup can be completed.").font(.caption).foregroundStyle(.orange) }
		}
	}
	private var review: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text(name).font(.headline); Text(preset.setupInstruction).font(.callout)
			if preset == .oneHand { Text("Uses the \(hand.rawValue) stick and controls on that side.").font(.callout) }
			GuidedPresetReviewView(profile: candidate)
			Text(useDefault ? "Will become your default for unlinked apps." : linkApp && !targetBundleId.isEmpty ? "Will activate in the selected app." : "Saved for later; choose activation before finishing.").font(.caption)
			Text("Customize any mapping with Press to Edit afterward.").font(.caption).foregroundStyle(.secondary)
		}
	}
	private var test: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text(testInstruction).font(.headline)
			check("Controller connected", controller.isConnected)
			check("Controller has the preset’s controls", compatibleControls)
			check("Accessibility granted", permissions.accessibilityGranted)
			check("Mapping enabled and unlocked", engine.isEnabled && !engine.isLocked)
			check("Saved profile selected", profiles.activeProfileId == createdId)
			check(testSession.isTesting ? "Controls released; output ready" : "Start Testing to resume output", engine.inputPreviewCount == 0)
			check("Activation saved for everyday use", routingSaved)
			if !compatibleControls { Text("This preset needs gamepad controls your current device or preview does not have. Connect a compatible gamepad before testing.").font(.caption).foregroundStyle(.orange) }
			if !permissions.accessibilityGranted { Button("Open Accessibility Settings", action: permissions.openAccessibilitySettings) }
			if !engine.isEnabled { Button("Enable Mapping for Test") { engine.enable() } }
			if engine.isLocked { Button("Unlock for Test") { _ = engine.performLockToggle() } }
			if profiles.activeProfileId != createdId, let savedProfile { Button("Select Saved Preset") { profiles.setActiveProfile(savedProfile) } }
			if !routingSaved, let savedProfile {
				HStack {
					Button("Use as Default") { profiles.setDefaultProfile(savedProfile) }
					if targetAvailable { Button("Link Target App") { profiles.addLinkedApp(targetBundleId, to: savedProfile) } }
				}
			}
			if !targetAvailable { Button("Choose Target App…") { showingAppPicker = true } }
			if !testSession.interruption.isEmpty { Text(testSession.interruption).foregroundStyle(.orange) }
			if !testSession.isTesting {
				Button("Start Testing") {
					if let previewId { engine.endInputPreview(previewId); self.previewId = nil }
					if let createdId { testSession.start(profileId: createdId, targetBundleId: targetBundleId, engine: engine, accessibility: { permissions.accessibilityGranted }) }
				}.disabled(!controller.isConnected || !compatibleControls || !permissions.accessibilityGranted || !engine.isEnabled || engine.isLocked || profiles.activeProfileId != createdId || !targetAvailable || !routingSaved)
				Text("The chosen preset stays active while testing. Release all controls, open the target app, then return after seeing the action.").font(.caption).foregroundStyle(.secondary)
			} else {
				if engine.inputPreviewCount > 0 {
					Text(engine.waitingForNeutralInput ? "Release buttons, triggers and sticks to resume the test." : "Another editor is pausing output. Close it before testing.").font(.caption).foregroundStyle(.orange)
				}
				Button("Open Target App") {
					if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: targetBundleId) { NSWorkspace.shared.openApplication(at: url, configuration: .init()) }
				}.disabled(!ready)
				Button("I Saw the Expected Action") {
					verified = true
					if let createdId { progress.complete(createdId) }
				}.disabled(!ready || !testSession.visitedTarget || !routingSaved)
				if !testSession.visitedTarget { Text("Open the target app when the checklist is ready before confirming.").font(.caption).foregroundStyle(.secondary) }
			}
			if verified { Label("Action confirmed by you.", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
		}
	}
	private func check(_ text: String, _ okay: Bool) -> some View {
		Label(text, systemImage: okay ? "checkmark.circle.fill" : "circle").font(.callout).foregroundStyle(okay ? Color.green : Color.secondary)
	}
	private func choose(_ option: GuidedPreset) {
		preset = option; name = option.title
		targetBundleId = option == .oneHand ? "com.apple.finder" : option.preferredBundleIds.first { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil } ?? ""
		linkApp = option != .oneHand; useDefault = option == .oneHand
	}
	private func load() {
		if let id = resumeProfileId, let saved = progress.entries[id.uuidString], let profile = profiles.profiles.first(where: { $0.id == id }) {
			preset = saved.preset; hand = saved.hand; name = profile.name; targetBundleId = saved.targetBundleId
			createdId = id; step = 2; verified = saved.verifiedAt != nil; profiles.setActiveProfile(profile)
		} else { choose(preset) }
		previewId = engine.beginInputPreview()
	}
	private func create() {
		let profile = profiles.createProfile(name: name.trimmingCharacters(in: .whitespacesAndNewlines), basedOn: candidate)
		if useDefault { profiles.setDefaultProfile(profile) }
		profiles.setActiveProfile(profiles.profiles.first { $0.id == profile.id } ?? profile)
		createdId = profile.id; step = 2
		progress.save(.init(preset: preset, hand: hand, targetBundleId: targetBundleId), for: profile.id)
	}
}
