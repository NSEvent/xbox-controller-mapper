import SwiftUI

// MARK: - Chord List

struct ChordListView: View, Equatable {
    let chords: [ChordMapping]
    let isDualSense: Bool
    let onEdit: (ChordMapping) -> Void
    let onDelete: (ChordMapping) -> Void
    let onMove: (IndexSet, Int) -> Void

    static func == (lhs: ChordListView, rhs: ChordListView) -> Bool {
        lhs.chords == rhs.chords && lhs.isDualSense == rhs.isDualSense
    }

    var body: some View {
        List {
            ForEach(chords) { chord in
                ChordRow(
                    chord: chord,
                    isDualSense: isDualSense,
                    onEdit: { onEdit(chord) },
                    onDelete: { onDelete(chord) }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                .background(GlassCardBackground())
            }
            .onMove(perform: onMove)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Chord Row

struct ChordRow: View {
    let chord: ChordMapping
    let isDualSense: Bool
    var onEdit: () -> Void
    var onDelete: () -> Void

    @EnvironmentObject var profileManager: ProfileManager

    var body: some View {
        HStack {
            // Drag handle - not tappable, allows List drag to work
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.white.opacity(0.3))
                .font(.caption)
                .frame(width: 20)

            // Tappable content area
            HStack {
                HStack(spacing: 4) {
                    ForEach(Array(chord.buttons).sorted(by: { $0.category.chordDisplayOrder < $1.category.chordDisplayOrder }), id: \.self) { button in
                        ButtonIconView(button: button, isDualSense: isDualSense)
                    }
                }

                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.3))

                if let systemCommand = chord.systemCommand {
                    Text(chord.hint ?? systemCommand.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.green.opacity(0.9))
                        .tooltipIfPresent(chord.hint != nil ? systemCommand.displayName : nil)
                } else if let macroId = chord.macroId,
                   let profile = profileManager.activeProfile,
                   let macro = profile.macros.first(where: { $0.id == macroId }) {
                    Text(chord.hint ?? macro.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.purple.opacity(0.9))
                        .tooltipIfPresent(chord.hint != nil ? macro.name : nil)
                } else {
                    Text(chord.hint ?? chord.actionDisplayString)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .tooltipIfPresent(chord.hint != nil ? chord.actionDisplayString : nil)
                }

                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture { onEdit() }

            HStack(spacing: 12) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.borderless)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .hoverableRow()
    }
}

// MARK: - Sequence List

struct SequenceListView: View, Equatable {
    let sequences: [SequenceMapping]
    let isDualSense: Bool
    let onEdit: (SequenceMapping) -> Void
    let onDelete: (SequenceMapping) -> Void
    let onMove: (IndexSet, Int) -> Void

    static func == (lhs: SequenceListView, rhs: SequenceListView) -> Bool {
        lhs.sequences == rhs.sequences && lhs.isDualSense == rhs.isDualSense
    }

    var body: some View {
        List {
            ForEach(sequences) { sequence in
                SequenceRow(
                    sequence: sequence,
                    isDualSense: isDualSense,
                    onEdit: { onEdit(sequence) },
                    onDelete: { onDelete(sequence) }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                .background(GlassCardBackground())
            }
            .onMove(perform: onMove)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Sequence Row

struct SequenceRow: View {
    let sequence: SequenceMapping
    let isDualSense: Bool
    var onEdit: () -> Void
    var onDelete: () -> Void

    @EnvironmentObject var profileManager: ProfileManager

    var body: some View {
        HStack {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.white.opacity(0.3))
                .font(.caption)
                .frame(width: 20)

            // Tappable content area
            HStack {
                HStack(spacing: 4) {
                    ForEach(Array(sequence.steps.enumerated()), id: \.offset) { index, button in
                        if index > 0 {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.3))
                        }
                        ButtonIconView(button: button, isDualSense: isDualSense)
                    }
                }

                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.3))

                if let systemCommand = sequence.systemCommand {
                    Text(sequence.hint ?? systemCommand.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.green.opacity(0.9))
                        .tooltipIfPresent(sequence.hint != nil ? systemCommand.displayName : nil)
                } else if let macroId = sequence.macroId,
                   let profile = profileManager.activeProfile,
                   let macro = profile.macros.first(where: { $0.id == macroId }) {
                    Text(sequence.hint ?? macro.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.purple.opacity(0.9))
                        .tooltipIfPresent(sequence.hint != nil ? macro.name : nil)
                } else {
                    Text(sequence.hint ?? sequence.actionDisplayString)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .tooltipIfPresent(sequence.hint != nil ? sequence.actionDisplayString : nil)
                }

                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture { onEdit() }

            HStack(spacing: 12) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.borderless)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .hoverableRow()
    }
}
