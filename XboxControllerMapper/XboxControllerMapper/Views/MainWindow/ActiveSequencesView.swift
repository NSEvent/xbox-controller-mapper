import SwiftUI

/// Displays the active sequence mappings in a flow layout at the bottom of the controller tab.
struct ActiveSequencesView: View {
    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var profileManager: ProfileManager
    @Binding var editingSequence: SequenceMapping?

    var body: some View {
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
                        HStack(spacing: 2) {
                            ForEach(Array(sequence.steps.enumerated()), id: \.offset) { index, button in
                                if index > 0 {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 7))
                                        .foregroundColor(.white.opacity(0.2))
                                        .accessibilityHidden(true)
                                }
                                ButtonIconView(button: button, isDualSense: controllerService.threadSafeIsPlayStation)
                            }
                        }

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
                           let macro = profile.macros.first(where: { $0.id == macroId }) {
                            Text(sequence.hint ?? macro.name)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.purple)
                                .lineLimit(1)
                                .tooltipIfPresent(sequence.hint != nil ? macro.name : nil)
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
