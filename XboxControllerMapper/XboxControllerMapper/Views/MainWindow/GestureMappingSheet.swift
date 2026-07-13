import SwiftUI

/// Sheet for configuring the action for a motion gesture
struct GestureMappingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var controllerService: ControllerService

    let gestureType: MotionGestureType
    let existingMapping: GestureMapping?

    @State private var editorState: MappingEditorState = {
        // Gesture-specific defaults that differ from MappingEditorState's
        var state = MappingEditorState()
        state.systemCommandCategory = .app
        state.shellRunInTerminal = false
        state.webhookMethod = .GET
        state.obsWebSocketURL = "ws://localhost:4455"
        return state
    }()

    private var isEditing: Bool { existingMapping != nil }

    private var canSave: Bool {
        switch editorState.mappingType {
        case .singleKey:
            return editorState.keyCode != nil || editorState.modifiers.hasAny
        case .macro:
            return editorState.selectedMacroId != nil
        case .script:
            return editorState.selectedScriptId != nil
        case .systemCommand:
            return editorState.buildSystemCommand() != nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(isEditing ? "Edit Gesture" : "Configure Gesture")
                    .font(.headline)

                // Gesture type display (fixed, not editable)
                HStack(spacing: 8) {
                    Image(systemName: gestureType.iconName)
                        .font(.system(size: 18))
                        .foregroundColor(.accentColor)
                        .accessibilityHidden(true)
                    Text(gestureType.displayName)
                        .font(.title3)
                        .fontWeight(.medium)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(8)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Gesture type: \(gestureType.displayName)")

                // Action section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Action:")
                            .font(.subheadline)

                        Spacer()

                        Picker("Action type", selection: $editorState.mappingType) {
                            Text("Key").tag(MappingEditorState.MappingType.singleKey)
                            Text("Macro").tag(MappingEditorState.MappingType.macro)
                            Text("Script").tag(MappingEditorState.MappingType.script)
                            Text("System").tag(MappingEditorState.MappingType.systemCommand)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 280)
                        .padding(.trailing, 8)

                        if editorState.mappingType == .singleKey {
                            Button(action: { editorState.showingKeyboard.toggle() }) {
                                HStack(spacing: 6) {
                                    Image(systemName: editorState.showingKeyboard ? "keyboard.chevron.compact.down" : "keyboard")
                                    Text(editorState.showingKeyboard ? "Hide Keyboard" : "Show Keyboard")
                                }
                                .font(.callout)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.accentColor.opacity(0.1))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)
                        }
                    }

                    if editorState.mappingType == .singleKey {
                        if editorState.showingKeyboard {
                            KeyboardVisualView(selectedKeyCode: $editorState.keyCode, modifiers: $editorState.modifiers)
                        } else {
                            KeyCaptureField(keyCode: $editorState.keyCode, modifiers: $editorState.modifiers)

                            Text("Click to type a shortcut, or show keyboard to select visually")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else if editorState.mappingType == .macro {
                        macroContent
                    } else if editorState.mappingType == .script {
                        scriptContent
                    } else {
                        systemCommandContent
                    }

                    // Hint field
                    HStack {
                        Text("Hint:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        TextField("e.g. Quick Save, Screenshot...", text: $editorState.hint)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)
                    }
                }

                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button(isEditing ? "Save" : "Add") {
                        saveGesture()
                    }
                    .disabled(!canSave)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
        .frame(width: 850)
        .onAppear {
            if let mapping = existingMapping {
                editorState.keyCode = mapping.keyCode
                editorState.modifiers = mapping.modifiers
                editorState.hint = mapping.hint ?? ""

                if let systemCommand = mapping.systemCommand {
                    editorState.mappingType = .systemCommand
                    editorState.loadSystemCommand(systemCommand)
                } else if let macroId = mapping.macroId {
                    editorState.mappingType = .macro
                    editorState.selectedMacroId = macroId
                } else if let scriptId = mapping.scriptId {
                    editorState.mappingType = .script
                    editorState.selectedScriptId = scriptId
                } else {
                    editorState.mappingType = .singleKey
                }
            }
        }
        .sheet(isPresented: $editorState.showingMacroCreation) {
            MacroEditorSheet(macro: nil, onSave: { newMacro in
                editorState.selectedMacroId = newMacro.id
            })
        }
        .sheet(isPresented: $editorState.showingScriptCreation) {
            ScriptEditorSheet(script: nil, onSave: { newScript in
                editorState.selectedScriptId = newScript.id
            })
        }
    }

    // MARK: - Macro Content

    @ViewBuilder
    private var macroContent: some View {
        if let profile = profileManager.activeProfile,
           !profile.macros.isEmpty || !profileManager.sharedLibraryMacros.isEmpty {
            Picker("Select Macro", selection: $editorState.selectedMacroId) {
                Text("Select a Macro...").tag(nil as UUID?)
                MacroPickerSections(
                    profileMacros: profile.macros,
                    sharedMacros: profileManager.sharedLibraryMacros
                )
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)

            Button { editorState.showingMacroCreation = true } label: {
                Label("Create New Macro...", systemImage: "plus.circle")
                    .font(.subheadline)
            }
        } else {
            VStack(spacing: 8) {
                Text("No macros defined in this profile.")
                    .foregroundColor(.secondary)
                    .italic()

                Button { editorState.showingMacroCreation = true } label: {
                    Label("Create New Macro...", systemImage: "plus.circle")
                        .font(.subheadline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.black.opacity(0.05))
            .cornerRadius(8)
        }
    }

    // MARK: - Script Content

    @ViewBuilder
    private var scriptContent: some View {
        if let profile = profileManager.activeProfile, !profile.scripts.isEmpty {
            Picker("Select Script", selection: $editorState.selectedScriptId) {
                Text("Select a Script...").tag(nil as UUID?)
                ForEach(profile.scripts) { script in
                    Text(script.name).tag(script.id as UUID?)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)

            Button { editorState.showingScriptCreation = true } label: {
                Label("Create New Script...", systemImage: "plus.circle")
                    .font(.subheadline)
            }
        } else {
            VStack(spacing: 8) {
                Text("No scripts defined in this profile.")
                    .foregroundColor(.secondary)
                    .italic()

                Button { editorState.showingScriptCreation = true } label: {
                    Label("Create New Script...", systemImage: "plus.circle")
                        .font(.subheadline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.black.opacity(0.05))
            .cornerRadius(8)
        }
    }

    // MARK: - System Command Content

    @ViewBuilder
    private var systemCommandContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Category", selection: $editorState.systemCommandCategory) {
                ForEach(SystemCommandCategory.allCases, id: \.self) { category in
                    Text(category.rawValue).tag(category)
                }
            }
            .pickerStyle(.segmented)

            switch editorState.systemCommandCategory {
			case .profile:
				ProfileSelectionPicker(selection: $editorState.selectedProfileId, selectedName: $editorState.selectedProfileName)
            case .app:
                AppSelectionButton(bundleId: editorState.appBundleIdentifier, showingPicker: $editorState.showingAppPicker)
                    .sheet(isPresented: $editorState.showingAppPicker) {
                        SystemActionAppPickerSheet(
                            currentBundleIdentifier: editorState.appBundleIdentifier.isEmpty ? nil : editorState.appBundleIdentifier
                        ) { app in
                            editorState.appBundleIdentifier = app.bundleIdentifier
                        }
                    }
                Toggle("Open in new window (Cmd+N)", isOn: $editorState.appNewWindow)
                    .font(.caption)
            case .shell:
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Command (e.g. say \"Hello\")", text: $editorState.shellCommandText)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)

                    Toggle("Run silently (no terminal window)", isOn: Binding(
                        get: { !editorState.shellRunInTerminal },
                        set: { editorState.shellRunInTerminal = !$0 }
                    ))
                        .font(.caption)

                    Text(editorState.shellRunInTerminal
                        ? "Opens a terminal window and executes the command"
                        : "Runs silently in the background (no visible output)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if editorState.shellRunInTerminal {
                        Divider()
                        TerminalAppPickerRow()
                    }
                }
            case .link:
                VStack(alignment: .leading, spacing: 8) {
                    TextField("URL (e.g. https://google.com)", text: $editorState.linkURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)

                    Button {
                        editorState.showingBookmarkPicker = true
                    } label: {
                        Label("Browse Bookmarks", systemImage: "book")
                            .font(.subheadline)
                    }
                    .sheet(isPresented: $editorState.showingBookmarkPicker) {
                        BookmarkPickerSheet { url in
                            editorState.linkURL = url
                        }
                    }

                    Text("Opens the URL in your default browser")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            case .webhook:
                VStack(alignment: .leading, spacing: 8) {
                    TextField("URL (e.g. https://api.example.com/webhook)", text: $editorState.webhookURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)

                    Picker("Method", selection: $editorState.webhookMethod) {
                        ForEach(HTTPMethod.allCases) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)

                    if [.POST, .PUT, .PATCH].contains(editorState.webhookMethod) {
                        TextField("Body (JSON)", text: $editorState.webhookBody, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)
                            .lineLimit(3...6)
                    }

                    Text("Sends an HTTP request when triggered")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            case .obs:
                VStack(alignment: .leading, spacing: 8) {
                    TextField("WebSocket URL", text: $editorState.obsWebSocketURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                    TextField("Password (optional)", text: $editorState.obsWebSocketPassword)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                    TextField("Request Type", text: $editorState.obsRequestType)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                    TextField("Request Data (JSON, optional)", text: $editorState.obsRequestData, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                        .lineLimit(2...4)
                }
            }
        }
    }

    // MARK: - Save

    private func saveGesture() {
        var gesture = existingMapping ?? GestureMapping(gestureType: gestureType)
        gesture.gestureType = gestureType

        switch editorState.mappingType {
        case .singleKey:
            gesture = gesture.clearingConflicts(keeping: .keyPress)
            gesture.keyCode = editorState.keyCode
            gesture.modifiers = editorState.modifiers
        case .macro:
            gesture = gesture.clearingConflicts(keeping: .macro)
            gesture.macroId = editorState.selectedMacroId
        case .script:
            gesture = gesture.clearingConflicts(keeping: .script)
            gesture.scriptId = editorState.selectedScriptId
        case .systemCommand:
            gesture = gesture.clearingConflicts(keeping: .systemCommand)
            gesture.systemCommand = editorState.buildSystemCommand()
        }

        gesture.hint = editorState.hint.isEmpty ? nil : editorState.hint

        if isEditing {
            profileManager.updateGesture(gesture)
        } else {
            profileManager.addGesture(gesture)
        }

        dismiss()
    }
}
