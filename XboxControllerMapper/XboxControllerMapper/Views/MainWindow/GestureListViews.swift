import SwiftUI

// MARK: - Gesture List

struct GestureListView: View {
    let gestureMappings: [GestureMapping]
    let onEdit: (MotionGestureType) -> Void
    let onClear: (MotionGestureType) -> Void

    @EnvironmentObject var profileManager: ProfileManager

    var body: some View {
        List {
            ForEach(MotionGestureType.allCases) { gestureType in
                let mapping = gestureMappings.first(where: { $0.gestureType == gestureType })
                GestureRow(
                    gestureType: gestureType,
                    mapping: mapping,
                    onEdit: { onEdit(gestureType) },
                    onClear: { onClear(gestureType) }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                .background(GlassCardBackground())
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Gesture Row

struct GestureRow: View {
    let gestureType: MotionGestureType
    let mapping: GestureMapping?
    var onEdit: () -> Void
    var onClear: () -> Void

    @EnvironmentObject var profileManager: ProfileManager

    var body: some View {
        HStack {
            // Gesture icon and name
            HStack(spacing: 8) {
                Image(systemName: gestureType.iconName)
                    .font(.system(size: 16))
                    .foregroundColor(.accentColor)
                    .frame(width: 24)

                Text(gestureType.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
            }

            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.3))
                .accessibilityHidden(true)

            // Action display
            if let mapping = mapping, mapping.hasAction {
                actionText(for: mapping)
            } else {
                Text("Not Mapped")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .italic()
            }

            Spacer()

            // Action buttons
            HStack(spacing: 12) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Edit")

                if mapping?.hasAction == true {
                    Button(action: onClear) {
                        Image(systemName: "trash")
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Clear")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
        .hoverableRow()
    }

    @ViewBuilder
    private func actionText(for mapping: GestureMapping) -> some View {
        if let systemCommand = mapping.systemCommand {
            Text(mapping.hint ?? systemCommand.displayName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.green.opacity(0.9))
                .lineLimit(1)
                .tooltipIfPresent(mapping.hint != nil ? systemCommand.displayName : nil)
        } else if let macroId = mapping.macroId,
                  let profile = profileManager.activeProfile,
                  let macro = profile.macros.first(where: { $0.id == macroId }) {
            Text(mapping.hint ?? macro.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.purple.opacity(0.9))
                .lineLimit(1)
                .tooltipIfPresent(mapping.hint != nil ? macro.name : nil)
        } else if let scriptId = mapping.scriptId,
                  let profile = profileManager.activeProfile,
                  let script = profile.scripts.first(where: { $0.id == scriptId }) {
            Text(mapping.hint ?? script.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.orange.opacity(0.9))
                .lineLimit(1)
                .tooltipIfPresent(mapping.hint != nil ? script.name : nil)
        } else {
            Text(mapping.hint ?? mapping.actionDisplayString)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
                .tooltipIfPresent(mapping.hint != nil ? mapping.actionDisplayString : nil)
        }
    }
}
