import SwiftUI

struct WorkflowSetupEntryView: View {
	@EnvironmentObject private var profiles: ProfileManager
	@ObservedObject private var progress = GuidedPresetProgressStore.shared
	@State private var showingSetup = false
	@State private var resumeId: UUID?
	var body: some View {
		Menu {
			Button("Set Up a Workflow…") { resumeId = nil; showingSetup = true }
			if let id = profiles.activeProfileId, progress.entries[id.uuidString] != nil {
				Button("Test This Preset…") { resumeId = id; showingSetup = true }
			}
		} label: {
			Label("Set Up", systemImage: "wand.and.stars")
				.font(.caption.weight(.medium))
				.padding(.horizontal, 10).padding(.vertical, 6)
				.background(Color.primary.opacity(0.06), in: Capsule())
		}
		.menuStyle(.borderlessButton).fixedSize()
		.help("Create a guided preset, or test the selected preset")
		.sheet(isPresented: $showingSetup) { GuidedPresetSheet(resumeProfileId: resumeId) }
	}
}

struct InputPreviewStatusBanner: View {
	@EnvironmentObject private var engine: MappingEngine
	var body: some View {
		if engine.inputPreviewCount > 0 {
			Label(engine.waitingForNeutralInput ? "Release controls to resume mapped output" : "Paused for editing · mapped output is muted", systemImage: "pause.circle.fill")
				.font(.callout).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
				.padding(.horizontal, 16).padding(.vertical, 8)
		}
	}
}
