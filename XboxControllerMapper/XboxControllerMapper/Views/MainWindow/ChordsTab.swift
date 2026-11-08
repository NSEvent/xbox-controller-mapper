import SwiftUI

/// Tab content for managing chord mappings.
struct ChordsTab: View, MappingControllerTypeProviding {
    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var profileManager: ProfileManager
    @Binding var showingChordSheet: Bool
    @Binding var editingChord: ChordMapping?

    var body: some View {
		let presentationState = controllerPresentationState

        Form {
            Section {
                Button(action: { showingChordSheet = true }) {
                    Label("Add New Chord", systemImage: "plus")
                        .fontWeight(.medium)
                }
                .padding(.vertical, 4)

                if let profile = profileManager.activeProfile, !profile.chordMappings.isEmpty {
                    ChordListView(
                        chords: profile.chordMappings,
						descriptor: presentationState,
						groupingDescriptor: (profile.controllerPreviewLayout == .active && !controllerService.isConnected) ? nil : presentationState,
						onEdit: { chord in
                            editingChord = chord
                        },
                        onDelete: { chord in
							guard profileManager.activeProfileId == profile.id else { return }
                            profileManager.removeChord(chord)
                        },
                        onClearAction: { chord in
							guard profileManager.activeProfileId == profile.id else { return }
                            profileManager.updateChord(chord.clearingAllActions())
                        },
						onMove: { ids, source, destination in
							profileManager.moveChordSection(ids: ids, from: source, to: destination, profileId: profile.id)
                        }
                    )
                } else {
                    Text("No chords configured")
                        .foregroundColor(.secondary)
                        .italic()
                        .padding()
                }
            } header: {
                Text("Chord Mappings")
                    .foregroundColor(.secondary)
            } footer: {
				Text("Chords let you map multiple button presses to a single action. Compatible mappings appear first. Drag within a section to reorder; switching controllers preserves your saved order.")
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding()
    }
}
