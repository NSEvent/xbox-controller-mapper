import SwiftUI

/// Tab content for managing sequence mappings.
struct SequencesTab: View, MappingControllerTypeProviding {
    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var profileManager: ProfileManager
    @Binding var showingSequenceSheet: Bool
    @Binding var editingSequence: SequenceMapping?

    var body: some View {
		let presentationState = controllerPresentationState

        Form {
            Section {
                Button(action: { showingSequenceSheet = true }) {
                    Label("Add New Sequence", systemImage: "plus")
                        .fontWeight(.medium)
                }
                .padding(.vertical, 4)

                if let profile = profileManager.activeProfile, !profile.sequenceMappings.isEmpty {
                    SequenceListView(
                        sequences: profile.sequenceMappings,
						descriptor: presentationState,
						groupingDescriptor: (profile.controllerPreviewLayout == .active && !controllerService.isConnected) ? nil : presentationState,
						onEdit: { sequence in
                            editingSequence = sequence
                        },
                        onDelete: { sequence in
							guard profileManager.activeProfileId == profile.id else { return }
                            profileManager.removeSequence(sequence)
                        },
                        onClearAction: { sequence in
							guard profileManager.activeProfileId == profile.id else { return }
                            profileManager.updateSequence(sequence.clearingAllActions())
                        },
						onMove: { ids, source, destination in
							profileManager.moveSequenceSection(ids: ids, from: source, to: destination, profileId: profile.id)
                        }
                    )
                } else {
                    Text("No sequences configured")
                        .foregroundColor(.secondary)
                        .italic()
                        .padding()
                }
            } header: {
                Text("Sequence Mappings")
                    .foregroundColor(.secondary)
            } footer: {
				Text("Sequences run steps in order; each step can be one button or a chord. Release all controls between steps in new sequences. Ordinary button and chord actions still run. Compatible mappings appear first. Drag within a section to reorder; switching controllers preserves your saved order.")
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding()
    }
}
