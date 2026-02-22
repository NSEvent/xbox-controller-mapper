import SwiftUI

/// Tab content for managing sequence mappings.
struct SequencesTab: View {
    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var profileManager: ProfileManager
    @Binding var showingSequenceSheet: Bool
    @Binding var editingSequence: SequenceMapping?

    var body: some View {
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
                        isDualSense: controllerService.threadSafeIsPlayStation,
                        onEdit: { sequence in
                            editingSequence = sequence
                        },
                        onDelete: { sequence in
                            profileManager.removeSequence(sequence)
                        },
                        onMove: { source, destination in
                            profileManager.moveSequences(from: source, to: destination)
                        }
                    )
                    .equatable()
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
                Text("Sequences fire an extra action when buttons are pressed in order within a time window. Individual button actions still fire normally (zero added latency).")
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding()
    }
}
