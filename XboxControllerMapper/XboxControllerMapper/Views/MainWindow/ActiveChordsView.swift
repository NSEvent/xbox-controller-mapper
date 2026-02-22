import SwiftUI

/// Displays the active chord mappings in a flow layout at the bottom of the controller tab.
struct ActiveChordsView: View {
    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var profileManager: ProfileManager
    @Binding var editingChord: ChordMapping?

    var body: some View {
        if let profile = profileManager.activeProfile, !profile.chordMappings.isEmpty {
            Divider()
                .background(Color.white.opacity(0.1))

            VStack(alignment: .leading, spacing: 12) {
                Text("ACTIVE CHORDS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                FlowLayout(data: profile.chordMappings, spacing: 10) { chord in
                    HStack(spacing: 10) {
                        HStack(spacing: 2) {
                            ForEach(Array(chord.buttons).sorted(by: { $0.category.chordDisplayOrder < $1.category.chordDisplayOrder }), id: \.self) { button in
                                ButtonIconView(button: button, isDualSense: controllerService.threadSafeIsPlayStation)
                            }
                        }

                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.3))
                            .accessibilityHidden(true)

                        if let systemCommand = chord.systemCommand {
                            Text(chord.hint ?? systemCommand.displayName)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.green)
                                .lineLimit(1)
                                .tooltipIfPresent(chord.hint != nil ? systemCommand.displayName : nil)
                        } else if let macroId = chord.macroId,
                           let macro = profile.macros.first(where: { $0.id == macroId }) {
                            Text(chord.hint ?? macro.name)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.purple)
                                .lineLimit(1)
                                .tooltipIfPresent(chord.hint != nil ? macro.name : nil)
                        } else {
                            Text(chord.hint ?? chord.actionDisplayString)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .tooltipIfPresent(chord.hint != nil ? chord.actionDisplayString : nil)
                        }
                    }
                    .frame(minHeight: 28)  // Consistent height regardless of button types
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .cornerRadius(10)
                    .hoverableGlassRow {
                        editingChord = chord
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
