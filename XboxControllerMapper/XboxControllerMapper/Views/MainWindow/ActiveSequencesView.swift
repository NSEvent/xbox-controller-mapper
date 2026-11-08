import SwiftUI

/// Displays the active sequence mappings in a flow layout at the bottom of the controller tab.
struct ActiveSequencesView: View, MappingControllerTypeProviding {
    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var profileManager: ProfileManager
    @Binding var editingSequence: SequenceMapping?

    var body: some View {
		let presentationState = controllerPresentationState

        if let profile = profileManager.activeProfile, !profile.sequenceMappings.isEmpty {
            Divider()
                .background(Color.white.opacity(0.1))

            VStack(alignment: .leading, spacing: 12) {
                Text("ACTIVE SEQUENCES")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                FlowLayout(data: profile.sequenceMappings.filter { $0.isValid }, spacing: 10) { sequence in
                    HStack(spacing: 10) {
						Text(sequence.inputSteps.map { $0.label(presentationState.buttonLabel) }.joined(separator: " → "))
							.font(.caption.weight(.medium)).fixedSize(horizontal: false, vertical: true)

                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.3))
                            .accessibilityHidden(true)

                        if let systemCommand = sequence.systemCommand {
                            Text(sequence.hint ?? systemCommand.displayName)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.green)
                                .lineLimit(1)
                                .tooltipIfPresent(sequence.hint != nil ? systemCommand.displayName : nil)
                        } else if let macroId = sequence.macroId,
                           let macroName = profile.macroDisplayName(for: macroId) {
                            Text(sequence.hint ?? macroName)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.purple)
                                .lineLimit(1)
                                .tooltipIfPresent(sequence.hint != nil ? macroName : nil)
                        } else {
                            Text(sequence.hint ?? sequence.actionDisplayString)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .tooltipIfPresent(sequence.hint != nil ? sequence.actionDisplayString : nil)
                        }
                    }
                    .frame(minHeight: 28)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .cornerRadius(10)
                    .hoverableGlassRow {
                        editingSequence = sequence
                    }
                    .contextMenu {
                        Button {
                            editingSequence = sequence
                        } label: {
                            Label("Edit Sequence", systemImage: "pencil")
                        }
                        if sequence.hasAction {
                            Button {
                                profileManager.updateSequence(sequence.clearingAllActions())
                            } label: {
                                Label("Clear Action", systemImage: "xmark.circle")
                            }
                        }
                        Divider()
                        Button(role: .destructive) {
                            profileManager.removeSequence(sequence)
                        } label: {
                            Label("Delete Sequence", systemImage: "trash")
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Double-tap to edit")
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
            .padding(.top, 12)
        }
    }
}
