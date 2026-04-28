import SwiftUI

/// Sheet for adding or editing a command wheel action
struct CommandWheelActionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var profileManager: ProfileManager

    /// The action being edited, or nil for a new action
    let action: CommandWheelAction?
    let onSave: (CommandWheelAction) -> Void

    @State private var displayName: String = ""
    @State private var iconName: String = ""
    @State private var mappingState = MappingEditorState()
    @State private var showingIconPicker = false

    /// Common SF Symbol icons for the wheel
    private static let iconGroups: [(name: String, icons: [String])] = [
        ("Actions", ["play.fill", "pause.fill", "stop.fill", "forward.fill", "backward.fill",
                     "speaker.wave.2.fill", "mic.fill", "camera.fill", "photo.fill", "film.fill"]),
        ("Apps", ["app.fill", "globe", "terminal", "folder.fill", "doc.fill",
                  "envelope.fill", "message.fill", "phone.fill", "video.fill", "music.note"]),
        ("Tools", ["wrench.fill", "hammer.fill", "scissors", "paintbrush.fill", "pencil",
                   "magnifyingglass", "link", "bolt.fill", "gear", "slider.horizontal.3"]),
        ("Media", ["keyboard", "gamecontroller.fill", "headphones", "tv.fill", "display",
                   "desktopcomputer", "laptopcomputer", "printer.fill", "externaldrive.fill", "network"]),
        ("Symbols", ["star.fill", "heart.fill", "flag.fill", "bookmark.fill", "tag.fill",
                     "bell.fill", "clock.fill", "lock.fill", "key.fill", "shield.fill"]),
        ("Arrows", ["arrow.up", "arrow.down", "arrow.left", "arrow.right",
                    "arrow.clockwise", "arrow.counterclockwise", "arrow.up.arrow.down", "arrow.left.arrow.right"])
    ]

    private var isEditing: Bool { action != nil }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? "Edit Action" : "Add Action")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Display Name
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextField("Action name", text: $displayName)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Icon
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Icon")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            // Current icon preview
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.accentColor.opacity(0.1))
                                    .frame(width: 36, height: 36)
                                if !iconName.isEmpty {
                                    Image(systemName: iconName)
                                        .font(.system(size: 18))
                                        .foregroundColor(.accentColor)
                                } else {
                                    Image(systemName: "questionmark.circle")
                                        .font(.system(size: 18))
                                        .foregroundColor(.secondary)
                                }
                            }

                            Button(showingIconPicker ? "Hide Icons" : "Choose Icon") {
                                withAnimation { showingIconPicker.toggle() }
                            }
                            .buttonStyle(.bordered)

                            if !iconName.isEmpty {
                                Button("Clear") {
                                    iconName = ""
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.secondary)
                            }

                            Spacer()

                            // Manual entry
                            TextField("SF Symbol name", text: $iconName)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 160)
                        }

                        if showingIconPicker {
                            iconPickerGrid
                                .padding(.top, 4)
                        }
                    }

                    Divider()

                    // Action Type Picker
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Action")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        HStack {
                            Picker("", selection: $mappingState.mappingType) {
                                Text("Key").tag(MappingEditorState.MappingType.singleKey)
                                Text("Macro").tag(MappingEditorState.MappingType.macro)
                                Text("System").tag(MappingEditorState.MappingType.systemCommand)
                                Text("Script").tag(MappingEditorState.MappingType.script)
                            }
                            .pickerStyle(.segmented)

                            if mappingState.mappingType == .singleKey {
                                Button(action: { mappingState.showingKeyboard.toggle() }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: mappingState.showingKeyboard ? "keyboard.chevron.compact.down" : "keyboard")
                                        Text(mappingState.showingKeyboard ? "Hide Keyboard" : "Show Keyboard")
                                            .lineLimit(1)
                                    }
                                    .font(.callout)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.accentColor.opacity(0.1))
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.accentColor)
                                .fixedSize()
                            }
                        }
                    }

                    // Action Editor (includes hint and haptic picker for primary variant)
                    ActionMappingEditor(state: $mappingState, variant: .primary)
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Save" : "Add") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .frame(width: mappingState.showingKeyboard ? 850 : 550, height: mappingState.showingKeyboard ? 750 : 600)
        .animation(.easeInOut(duration: 0.2), value: mappingState.showingKeyboard)
        .onAppear { loadExisting() }
    }

    // MARK: - Icon Picker Grid

    @ViewBuilder
    private var iconPickerGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Self.iconGroups, id: \.name) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 4), count: 10), spacing: 4) {
                        ForEach(group.icons, id: \.self) { symbolName in
                            Button {
                                iconName = symbolName
                                withAnimation { showingIconPicker = false }
                            } label: {
                                Image(systemName: symbolName)
                                    .font(.system(size: 14))
                                    .frame(width: 30, height: 30)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(iconName == symbolName ? Color.accentColor.opacity(0.2) : Color.clear)
                                    )
                                    .foregroundColor(iconName == symbolName ? .accentColor : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.03))
        )
    }

    // MARK: - Load / Save

    private func loadExisting() {
        guard let action = action else { return }
        displayName = action.displayName
        iconName = action.iconName ?? ""

        // Load action into editor state
        if let systemCommand = action.systemCommand {
            mappingState.mappingType = .systemCommand
            mappingState.loadSystemCommand(systemCommand)
        } else if let macroId = action.macroId {
            mappingState.mappingType = .macro
            mappingState.selectedMacroId = macroId
        } else if let scriptId = action.scriptId {
            mappingState.mappingType = .script
            mappingState.selectedScriptId = scriptId
        } else {
            mappingState.mappingType = .singleKey
            mappingState.keyCode = action.keyCode
            mappingState.modifiers = action.modifiers
        }
        mappingState.hint = action.hint ?? ""
        mappingState.hapticStyle = action.hapticStyle
    }

    private func save() {
        var result = action ?? CommandWheelAction()
        result.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        result.iconName = iconName.isEmpty ? nil : iconName
        let trimmedHint = mappingState.hint.trimmingCharacters(in: .whitespacesAndNewlines)
        result.hint = trimmedHint.isEmpty ? nil : trimmedHint
        result.hapticStyle = mappingState.hapticStyle

        // Clear all action fields first
        result.keyCode = nil
        result.modifiers = ModifierFlags()
        result.macroId = nil
        result.scriptId = nil
        result.systemCommand = nil

        // Set based on current mapping type
        switch mappingState.mappingType {
        case .singleKey:
            result.keyCode = mappingState.keyCode
            result.modifiers = mappingState.modifiers
        case .macro:
            result.macroId = mappingState.selectedMacroId
        case .script:
            result.scriptId = mappingState.selectedScriptId
        case .systemCommand:
            result.systemCommand = mappingState.buildSystemCommand()
        }

        onSave(result)
        dismiss()
    }
}
