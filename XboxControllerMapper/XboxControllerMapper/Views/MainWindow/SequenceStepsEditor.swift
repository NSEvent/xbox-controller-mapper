import SwiftUI

struct SequenceStepsEditor: View {
	@Binding var draft: SequenceEditorDraft
	@ObservedObject var session: SequenceInputSession
	let descriptor: ControllerVisualDescriptor
	let joystickSettings: JoystickSettings
	let timeout: TimeInterval
	@EnvironmentObject private var controller: ControllerService
	@EnvironmentObject private var engine: MappingEngine

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack {
				Label("Sequence steps", systemImage: "point.3.connected.trianglepath.dotted").font(.headline)
				Spacer()
				Button("Record Sequence", systemImage: "record.circle") {
					session.startRecording(controller: controller, engine: engine)
				}.disabled(!controller.isConnected || session.isBusy)
				Button("Add Step", systemImage: "plus") { draft.edit() }
					.disabled(session.isBusy || draft.isEditingStep || draft.steps.count >= Config.maxSequenceSteps)
			}
			Text("Controller: \(descriptor.displayName)").font(.caption).foregroundStyle(.secondary)
			if let recording = session.recording {
				recordingView(recording)
			} else {
				ForEach(Array(draft.steps.enumerated()), id: \.offset) { index, step in
					HStack {
						Text("\(index + 1)").monospacedDigit().foregroundStyle(.secondary).frame(width: 24)
						Text(step.label(descriptor.buttonLabel)).font(.body.weight(.medium))
						Spacer()
						if session.isTrying && index < session.matchedSteps { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
						Button("Edit") { draft.edit(index) }
						Button { draft.duplicate(index) } label: { Image(systemName: "plus.square.on.square") }
							.help("Duplicate step").accessibilityLabel("Duplicate step \(index + 1)")
							.disabled(draft.steps.count >= Config.maxSequenceSteps)
						Button { draft.move(index, by: -1) } label: { Image(systemName: "arrow.up") }
							.disabled(index == 0).accessibilityLabel("Move step \(index + 1) up")
						Button { draft.move(index, by: 1) } label: { Image(systemName: "arrow.down") }
							.disabled(index == draft.steps.count - 1).accessibilityLabel("Move step \(index + 1) down")
						Button { draft.remove(index) } label: { Image(systemName: "trash") }
							.accessibilityLabel("Delete step \(index + 1)")
					}.padding(10).background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
						.disabled(session.isBusy || draft.isEditingStep)
				}
				if draft.isEditingStep { manualEditor.disabled(session.isBusy) }
			}
			Text(draft.usesReleaseSteps
				? "Press buttons in each step together. Release all controls before the next step. The action runs on the final release."
				: "This existing sequence uses press timing. Adding a chord or using a recording switches it to full release between steps.")
				.font(.caption).foregroundStyle(.secondary)
			if draft.steps.count == 1 && !draft.isEditingStep {
				Text("Add at least 2 steps. For a single combination, use the Chords tab.").font(.caption).foregroundStyle(.secondary)
			}
			if !session.message.isEmpty { Text(session.message).font(.caption).foregroundStyle(.secondary) }
			if session.recording == nil {
				HStack {
					Button(session.isTrying ? "Restart Test" : "Try Sequence") {
						var sequence = SequenceMapping(chordSteps: draft.steps, stepTimeout: timeout)
						sequence.usesReleaseSteps = draft.usesReleaseSteps
						session.startTrying(sequence, controller: controller, engine: engine)
					}.disabled(!draft.canSave || !controller.isConnected)
					if session.isTrying { Button("Stop Test") { session.cancel() } }
				}
			}
		}
	}

	private var manualEditor: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text(draft.editingIndex == nil ? "New step · Press together" : "Edit step · Press together").font(.subheadline.weight(.medium))
			DeviceMappingButtonGrid(descriptor: descriptor, joystickSettings: joystickSettings) { button in
				Button { draft.toggle(button) } label: {
					Image(systemName: draft.selection.contains(button) ? "checkmark.circle.fill" : "circle")
						.font(.title2).foregroundStyle(draft.selection.contains(button) ? Color.accentColor : .secondary)
						.frame(maxWidth: .infinity, minHeight: 36)
				}.buttonStyle(.plain)
					.accessibilityLabel(descriptor.buttonLabel(button))
					.accessibilityValue(draft.selection.contains(button) ? "Selected" : "Not selected")
			}
			if !draft.selection.isEmpty {
				Text(SequenceStep(draft.selection).label(descriptor.buttonLabel)).font(.subheadline.weight(.medium))
				if let reason = draft.selectionError { Text(reason).font(.caption).foregroundStyle(.red) }
			}
			HStack {
				Button("Cancel Step") { draft.cancelStep() }
				Spacer()
				Button(draft.editingIndex == nil ? "Add This Step" : "Done") { draft.commitStep() }
					.disabled(!draft.canCommitStep).buttonStyle(.borderedProminent)
			}
		}.padding(12).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
	}

	private func recordingView(_ recording: SequenceRecording) -> some View {
		VStack(alignment: .leading, spacing: 10) {
			ForEach(Array(recording.steps.enumerated()), id: \.offset) { index, step in
				Text("\(index + 1).  \(step.label(descriptor.buttonLabel))")
			}
			if !recording.assembler.candidate.isEmpty {
				Text("Holding: \(SequenceStep(recording.assembler.candidate).label(descriptor.buttonLabel))").foregroundStyle(.secondary)
			}
			if recording.assembler.waitingForRelease { Text("Release held controls to begin.").foregroundStyle(.orange) }
			if recording.ambiguous {
				Text("These presses did not overlap within the chord window. Release all controls, then retry this step.").foregroundStyle(.orange)
				Button("Retry Step") { session.retryStep() }
			}
			if recording.steps.count == recording.limit { Text("Maximum steps reached. Review and use this recording.") }
			HStack {
				Button("Undo Last") { session.undo() }.disabled(recording.steps.isEmpty || !recording.assembler.held.isEmpty)
				Button("Start Over") { session.startOver() }
				Button("Cancel Recording") { session.cancel() }
				Spacer()
				Button("Use Recording") {
					if let steps = session.acceptRecording() { draft.useRecording(steps) }
				}.disabled(!recording.canUse).buttonStyle(.borderedProminent)
			}
		}.padding(12).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
	}
}
