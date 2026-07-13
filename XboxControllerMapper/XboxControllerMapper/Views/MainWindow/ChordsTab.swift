import SwiftUI

/// Tab content for managing chord mappings.
struct ChordsTab: View {
    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var profileManager: ProfileManager
    @Binding var showingChordSheet: Bool
    @Binding var editingChord: ChordMapping?

    private var controllerPresentationState: ControllerPresentationState {
		controllerService.threadSafeControllerPresentationState
    }

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
						isDualSense: presentationState.isPlayStation,
						isNintendo: presentationState.isNintendo,
						isSteamController: presentationState.isSteamController,
						isAppleTVRemote: presentationState.isAppleTVRemote,
						onEdit: { chord in
                            editingChord = chord
                        },
                        onDelete: { chord in
                            profileManager.removeChord(chord)
                        },
                        onClearAction: { chord in
                            profileManager.updateChord(chord.clearingAllActions())
                        },
                        onMove: { source, destination in
                            profileManager.moveChords(from: source, to: destination)
                        }
                    )
                    .equatable()
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
                Text("Chords let you map multiple button presses to a single action.")
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding()
    }
}
