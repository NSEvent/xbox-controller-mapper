import SwiftUI

struct TriggerMIDITools: View {
	@EnvironmentObject private var profiles: ProfileManager
	@EnvironmentObject private var controller: ControllerService
	@EnvironmentObject private var engine: MappingEngine
	@State private var showingPreview = false
	@State private var conflict: TriggerMIDIConflict?
	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			Button("Preview Trigger Values…") { showingPreview = true }.disabled(!controller.isConnected)
			Text("Preview pauses mapped output. Use it to check pressure and CC values before connecting a music app.").font(.caption).foregroundStyle(.secondary)
			if let profile = profiles.activeProfile {
				ForEach(JoystickSide.allCases) { side in
					if (side == .left ? profile.joystickSettings.leftTriggerMIDI : profile.joystickSettings.rightTriggerMIDI) != nil {
						let conflicts = TriggerMIDIConflict.find(in: profile, side: side)
						ForEach(conflicts) { item in
							HStack {
								Text("\(side == .left ? "Left" : "Right") trigger: \(item.description)").font(.caption).foregroundStyle(.orange)
								Spacer()
								Button("Edit…") { conflict = item }
							}
						}
					}
				}
			}
			DisclosureGroup("Connect to Logic Pro") {
				VStack(alignment: .leading, spacing: 8) {
					Text("1. Close preview, release both triggers, and enable mapping. Keep this profile active in Logic Pro by linking it to that app or making it the default.")
					Text("2. In Logic’s Mixer or a plug-in, select the parameter you want to control. Choose Logic Pro → Control Surfaces → Learn Assignment for that parameter.")
					Text("3. Squeeze and release one trigger. Check the incoming CC, then turn Learn Mode off to finish. Move the trigger again to verify the parameter follows it.")
					Link("Apple’s controller assignment guide", destination: URL(string: "https://support.apple.com/guide/logicpro/ctls71c31855/mac")!)
				}.font(.caption).padding(.top, 8)
			}
		}
		.sheet(isPresented: $showingPreview) { TriggerMIDIPreviewSheet() }
		.sheet(item: $conflict) { item in conflictEditor(item) }
		.onChange(of: profiles.activeProfileId) { _, _ in conflict = nil; showingPreview = false }
	}
	@ViewBuilder private func conflictEditor(_ item: TriggerMIDIConflict) -> some View {
		switch item.destination {
		case .button(let button, let layerId):
			let state = controller.threadSafeControllerPresentationState
			ButtonMappingSheet(button: button, mapping: Binding(get: {
				if let layerId { return profiles.activeProfile?.layers.first { $0.id == layerId }?.buttonMappings[button] }
				return profiles.activeProfile?.buttonMappings[button]
			}, set: { _ in }), isDualSense: state.isPlayStation, isNintendo: state.isNintendo, isSteamController: state.isSteamController, isAppleTVRemote: state.isAppleTVRemote, selectedLayerId: layerId)
		case .chord(let chord): ChordMappingSheet(editingChord: chord)
		case .sequence(let sequence): SequenceMappingSheet(editingSequence: sequence)
		case .layer(let layer): EditLayerSheet(layer: layer)
		case .precision:
			VStack(alignment: .leading, spacing: 16) {
				Text("Trigger precision control").font(.title2.bold())
				Text("This trigger slows the pointer or scrolling as you squeeze it. Disable that behavior if you want it exclusively for MIDI.")
				HStack {
					Button("Cancel") { conflict = nil }
					Button("Turn Off Trigger Slowdown") {
						if let profile = profiles.activeProfile {
							var settings = profile.joystickSettings; settings.analogPrecisionTriggerMode = .off
							profiles.updateJoystickSettings(settings, in: profile)
						}
						conflict = nil
					}
				}
			}.padding(24).frame(width: 440)
		}
	}
}

struct TriggerMIDIPreviewSheet: View {
	@EnvironmentObject private var profiles: ProfileManager
	@EnvironmentObject private var controller: ControllerService
	@EnvironmentObject private var engine: MappingEngine
	@Environment(\.dismiss) private var dismiss
	@State private var previewId: UUID?
	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text("Preview Trigger MIDI").font(.title2.bold())
			Text("Mapped actions are paused. Existing MIDI output returns to its rest value; trigger squeezes in this preview are not sent to your music app.").font(.callout).foregroundStyle(.secondary)
			TimelineView(.periodic(from: .now, by: 1 / 30)) { _ in
				VStack(alignment: .leading, spacing: 16) {
					let snapshot = controller.snapshot()
					valueRow("Left", raw: Double(snapshot.leftTrigger), config: profiles.activeProfile?.joystickSettings.leftTriggerMIDI)
					valueRow("Right", raw: Double(snapshot.rightTrigger), config: profiles.activeProfile?.joystickSettings.rightTriggerMIDI)
				}
			}
			if !controller.isConnected { Text("Controller disconnected. Reconnect to continue previewing.").foregroundStyle(.orange) }
			Text("Release both triggers before closing to resume output.").font(.caption)
			HStack { Spacer(); Button("Close Preview") { dismiss() }.keyboardShortcut(.cancelAction) }
		}.padding(24).frame(width: 560)
		.onAppear { previewId = engine.beginInputPreview() }
		.onDisappear { if let previewId { engine.endInputPreview(previewId) } }
	}
	private func valueRow(_ name: String, raw: Double, config: TriggerMIDIConfiguration?) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack {
				Text("\(name): \(Int((raw * 100).rounded()))% pressure").monospacedDigit()
				Spacer()
				if let config { Text("Channel \(config.message.channel) · CC \(config.message.controller) → \(config.value(for: raw))").monospacedDigit() }
				else { Text("MIDI off").foregroundStyle(.secondary) }
			}
			ProgressView(value: raw, total: 1)
		}
	}
}
