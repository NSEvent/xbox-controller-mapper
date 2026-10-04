import SwiftUI

struct WorkflowSetupEntryView: View {
	@EnvironmentObject private var profiles: ProfileManager
	@ObservedObject private var progress = GuidedPresetProgressStore.shared
	@State private var showingSetup = false
	@State private var resumeId: UUID?
	var body: some View {
		HStack {
			Button { resumeId = nil; showingSetup = true } label: { Label("Set Up a Workflow", systemImage: "wand.and.stars") }
			Text("Start with a preset, then verify one action.").font(.caption).foregroundStyle(.secondary)
			Spacer()
			if !progress.pending(in: profiles.profiles).isEmpty {
				Menu("Resume Setup") {
					ForEach(progress.pending(in: profiles.profiles)) { profile in
						Button(profile.name) { resumeId = profile.id; showingSetup = true }
					}
				}.fixedSize()
			}
		}.padding(.horizontal, 16).padding(.vertical, 8)
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
