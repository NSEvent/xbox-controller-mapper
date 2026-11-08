import SwiftUI

// MARK: - Chord List

struct ChordListView: View {
    let chords: [ChordMapping]
	let descriptor: ControllerVisualDescriptor
	let groupingDescriptor: ControllerVisualDescriptor?
	let onEdit: (ChordMapping) -> Void
    let onDelete: (ChordMapping) -> Void
    let onClearAction: (ChordMapping) -> Void
	let onMove: ([UUID], IndexSet, Int) -> Void

    var body: some View {
        List {
			ForEach(ControllerMappingGroups.sections(of: chords, descriptor: groupingDescriptor, buttons: { $0.buttons })) { group in
				Section {
					if group.items.isEmpty { Text("No compatible chords yet").foregroundStyle(.secondary).italic() }
					ForEach(group.items) { chord in
						ChordRow(chord: chord, isDualSense: descriptor.isPlayStation,
							isNintendo: descriptor.isNintendo, isSteamController: descriptor.isSteamController,
							isAppleTVRemote: descriptor.isAppleTVRemote, isWiimote: descriptor.isWiimote,
							isEightBitDo: descriptor.eightBitDoModel != nil,
							onEdit: { onEdit(chord) }, onDelete: { onDelete(chord) }, onClearAction: { onClearAction(chord) })
							.listRowBackground(Color.clear).listRowSeparator(.hidden)
							.listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
							.background(GlassCardBackground())
					}
					.onMove { onMove(group.items.map(\.id), $0, $1) }
				} header: {
					HStack { Text(group.title); Spacer(); Text("\(group.items.count)").foregroundStyle(.secondary) }
				}
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Chord Row

struct ChordRow: View {
    let chord: ChordMapping
	    let isDualSense: Bool
	    let isNintendo: Bool
	    let isSteamController: Bool
	    let isAppleTVRemote: Bool
	    let isWiimote: Bool
	var isEightBitDo: Bool = false
	    var onEdit: () -> Void
    var onDelete: () -> Void
    var onClearAction: () -> Void

    @EnvironmentObject var profileManager: ProfileManager

	private var triggerLabel: String {
		(Array(chord.buttons).sorted { $0.rawValue < $1.rawValue }).map { $0.displayName(forDualSense: isDualSense, forNintendo: isNintendo,
			forAppleTVRemote: isAppleTVRemote, forEightBitDo: isEightBitDo, forWiimote: isWiimote) }
			.joined(separator: " + ")
	}

    var body: some View {
        HStack {
            // Drag handle - not tappable, allows List drag to work
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.white.opacity(0.3))
                .font(.caption)
                .frame(width: 20)
                .accessibilityHidden(true)

            // Tappable content area
            HStack {
                HStack(spacing: 4) {
                    ForEach(Array(chord.buttons).sorted(by: { $0.category.chordDisplayOrder < $1.category.chordDisplayOrder }), id: \.self) { button in
							ButtonIconView(button: button, isDualSense: isDualSense, isNintendo: isNintendo, isSteamController: isSteamController, isAppleTVRemote: isAppleTVRemote, isEightBitDo: isEightBitDo, isWiimote: isWiimote)
                    }
                }

                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.3))
                    .accessibilityHidden(true)

                if let systemCommand = chord.systemCommand {
                    Text(chord.hint ?? systemCommand.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.green.opacity(0.9))
                        .tooltipIfPresent(chord.hint != nil ? systemCommand.displayName : nil)
				} else if let macroId = chord.macroId,
						  let profile = profileManager.activeProfile,
						  let macroName = profile.macroDisplayName(for: macroId) {
					Text(chord.hint ?? macroName)
						.font(.system(size: 13, weight: .medium))
						.foregroundColor(.purple.opacity(0.9))
						.tooltipIfPresent(chord.hint != nil ? macroName : nil)
				} else if let scriptId = chord.scriptId,
						  let profile = profileManager.activeProfile,
						  let script = profile.scripts.first(where: { $0.id == scriptId }) {
					Text(chord.hint ?? script.name)
						.font(.system(size: 13, weight: .medium))
						.foregroundColor(.white.opacity(0.9))
						.tooltipIfPresent(chord.hint != nil ? script.name : nil)
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
				.help("Edit \(triggerLabel)")
				.accessibilityLabel("Edit \(triggerLabel)")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.borderless)
				.help("Delete \(triggerLabel)")
				.accessibilityLabel("Delete \(triggerLabel)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .hoverableRow()
        .contextMenu {
            Button(action: onEdit) {
                Label("Edit Chord", systemImage: "pencil")
            }
            if chord.hasAction {
                Button(action: onClearAction) {
                    Label("Clear Action", systemImage: "xmark.circle")
                }
            }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("Delete Chord", systemImage: "trash")
            }
        }
    }
}

// MARK: - Sequence List

struct SequenceListView: View {
    let sequences: [SequenceMapping]
	let descriptor: ControllerVisualDescriptor
	let groupingDescriptor: ControllerVisualDescriptor?
	let onEdit: (SequenceMapping) -> Void
    let onDelete: (SequenceMapping) -> Void
    let onClearAction: (SequenceMapping) -> Void
	let onMove: ([UUID], IndexSet, Int) -> Void

    var body: some View {
        List {
			ForEach(ControllerMappingGroups.sections(of: sequences, descriptor: groupingDescriptor, buttons: { Set($0.steps) })) { group in
				Section {
					if group.items.isEmpty { Text("No compatible sequences yet").foregroundStyle(.secondary).italic() }
					ForEach(group.items) { sequence in
						SequenceRow(sequence: sequence, isDualSense: descriptor.isPlayStation,
							isNintendo: descriptor.isNintendo, isSteamController: descriptor.isSteamController,
							isAppleTVRemote: descriptor.isAppleTVRemote, isWiimote: descriptor.isWiimote,
							isEightBitDo: descriptor.eightBitDoModel != nil,
							onEdit: { onEdit(sequence) }, onDelete: { onDelete(sequence) }, onClearAction: { onClearAction(sequence) })
							.listRowBackground(Color.clear).listRowSeparator(.hidden)
							.listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
							.background(GlassCardBackground())
					}
					.onMove { onMove(group.items.map(\.id), $0, $1) }
				} header: {
					HStack { Text(group.title); Spacer(); Text("\(group.items.count)").foregroundStyle(.secondary) }
				}
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Sequence Row

struct SequenceRow: View {
    let sequence: SequenceMapping
	    let isDualSense: Bool
	    let isNintendo: Bool
	    let isSteamController: Bool
	    let isAppleTVRemote: Bool
	    let isWiimote: Bool
	var isEightBitDo: Bool = false
	    var onEdit: () -> Void
    var onDelete: () -> Void
    var onClearAction: () -> Void

    @EnvironmentObject var profileManager: ProfileManager

	private var triggerLabel: String {
		(sequence.steps).map { $0.displayName(forDualSense: isDualSense, forNintendo: isNintendo,
			forAppleTVRemote: isAppleTVRemote, forEightBitDo: isEightBitDo, forWiimote: isWiimote) }
			.joined(separator: " → ")
	}

    var body: some View {
        HStack {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.white.opacity(0.3))
                .font(.caption)
                .frame(width: 20)
                .accessibilityHidden(true)

            // Tappable content area
            HStack {
                HStack(spacing: 4) {
                    ForEach(Array(sequence.steps.enumerated()), id: \.offset) { index, button in
                        if index > 0 {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.3))
                                .accessibilityHidden(true)
                        }
							ButtonIconView(button: button, isDualSense: isDualSense, isNintendo: isNintendo, isSteamController: isSteamController, isAppleTVRemote: isAppleTVRemote, isEightBitDo: isEightBitDo, isWiimote: isWiimote)
                    }
                }

                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.3))
                    .accessibilityHidden(true)

                if let systemCommand = sequence.systemCommand {
                    Text(sequence.hint ?? systemCommand.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.green.opacity(0.9))
                        .tooltipIfPresent(sequence.hint != nil ? systemCommand.displayName : nil)
                } else if let macroId = sequence.macroId,
                   let profile = profileManager.activeProfile,
                   let macroName = profile.macroDisplayName(for: macroId) {
                    Text(sequence.hint ?? macroName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.purple.opacity(0.9))
                        .tooltipIfPresent(sequence.hint != nil ? macroName : nil)
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
				.help("Edit \(triggerLabel)")
				.accessibilityLabel("Edit \(triggerLabel)")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.borderless)
				.help("Delete \(triggerLabel)")
				.accessibilityLabel("Delete \(triggerLabel)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .hoverableRow()
        .contextMenu {
            Button(action: onEdit) {
                Label("Edit Sequence", systemImage: "pencil")
            }
            if sequence.hasAction {
                Button(action: onClearAction) {
                    Label("Clear Action", systemImage: "xmark.circle")
                }
            }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("Delete Sequence", systemImage: "trash")
            }
        }
    }
}
