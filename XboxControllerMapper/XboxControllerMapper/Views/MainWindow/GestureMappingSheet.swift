import SwiftUI

/// Sheet for configuring the action for a motion gesture
struct GestureMappingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var controllerService: ControllerService

    let gestureType: MotionGestureType
    let existingMapping: GestureMapping?

    enum MappingType: Int {
        case singleKey = 0
        case macro = 1
        case script = 2
        case systemCommand = 3
    }

    @State private var mappingType: MappingType = .singleKey
    @State private var keyCode: CGKeyCode?
    @State private var modifiers = ModifierFlags()
    @State private var selectedMacroId: UUID?
    @State private var selectedScriptId: UUID?
    @State private var hint: String = ""
    @State private var showingKeyboard = false
    @State private var showingMacroCreation = false
    @State private var showingScriptCreation = false

    // System command state
    @State private var systemCommandCategory: SystemCommandCategory = .app
    @State private var appBundleIdentifier: String = ""
    @State private var appNewWindow: Bool = false
    @State private var shellCommandText: String = ""
    @State private var shellRunInTerminal: Bool = false
    @State private var linkURL: String = ""
    @State private var webhookURL: String = ""
    @State private var webhookMethod: HTTPMethod = .GET
    @State private var webhookHeaders: [String: String] = [:]
    @State private var webhookBody: String = ""
    @State private var obsWebSocketURL: String = "ws://localhost:4455"
    @State private var obsWebSocketPassword: String = ""
    @State private var obsRequestType: String = ""
    @State private var obsRequestData: String = ""
    @State private var showingAppPicker = false
    @State private var showingBookmarkPicker = false

    private var isEditing: Bool { existingMapping != nil }

    private var canSave: Bool {
        switch mappingType {
        case .singleKey:
            return keyCode != nil || modifiers.hasAny
        case .macro:
            return selectedMacroId != nil
        case .script:
            return selectedScriptId != nil
        case .systemCommand:
            return buildSystemCommand() != nil
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
                    Text(gestureType.displayName)
                        .font(.title3)
                        .fontWeight(.medium)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(8)

                // Action section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Action:")
                            .font(.subheadline)

                        Spacer()

                        Picker("", selection: $mappingType) {
                            Text("Key").tag(MappingType.singleKey)
                            Text("Macro").tag(MappingType.macro)
                            Text("Script").tag(MappingType.script)
                            Text("System").tag(MappingType.systemCommand)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 280)
                        .padding(.trailing, 8)

                        if mappingType == .singleKey {
                            Button(action: { showingKeyboard.toggle() }) {
                                HStack(spacing: 6) {
                                    Image(systemName: showingKeyboard ? "keyboard.chevron.compact.down" : "keyboard")
                                    Text(showingKeyboard ? "Hide Keyboard" : "Show Keyboard")
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

                    if mappingType == .singleKey {
                        if showingKeyboard {
                            KeyboardVisualView(selectedKeyCode: $keyCode, modifiers: $modifiers)
                        } else {
                            KeyCaptureField(keyCode: $keyCode, modifiers: $modifiers)

                            Text("Click to type a shortcut, or show keyboard to select visually")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else if mappingType == .macro {
                        macroContent
                    } else if mappingType == .script {
                        scriptContent
                    } else {
                        systemCommandContent
                    }

                    // Hint field
                    HStack {
                        Text("Hint:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        TextField("e.g. Quick Save, Screenshot...", text: $hint)
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
                keyCode = mapping.keyCode
                modifiers = mapping.modifiers
                hint = mapping.hint ?? ""

                if let systemCommand = mapping.systemCommand {
                    mappingType = .systemCommand
                    loadSystemCommandState(systemCommand)
                } else if let macroId = mapping.macroId {
                    mappingType = .macro
                    selectedMacroId = macroId
                } else if let scriptId = mapping.scriptId {
                    mappingType = .script
                    selectedScriptId = scriptId
                } else {
                    mappingType = .singleKey
                }
            }
        }
        .sheet(isPresented: $showingMacroCreation) {
            MacroEditorSheet(macro: nil, onSave: { newMacro in
                selectedMacroId = newMacro.id
            })
        }
        .sheet(isPresented: $showingScriptCreation) {
            ScriptEditorSheet(script: nil, onSave: { newScript in
                selectedScriptId = newScript.id
            })
        }
    }

    // MARK: - Macro Content

    @ViewBuilder
    private var macroContent: some View {
        if let profile = profileManager.activeProfile, !profile.macros.isEmpty {
            Picker("Select Macro", selection: $selectedMacroId) {
                Text("Select a Macro...").tag(nil as UUID?)
                ForEach(profile.macros) { macro in
                    Text(macro.name).tag(macro.id as UUID?)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)

            Button { showingMacroCreation = true } label: {
                Label("Create New Macro...", systemImage: "plus.circle")
                    .font(.subheadline)
            }
        } else {
            VStack(spacing: 8) {
                Text("No macros defined in this profile.")
                    .foregroundColor(.secondary)
                    .italic()

                Button { showingMacroCreation = true } label: {
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
            Picker("Select Script", selection: $selectedScriptId) {
                Text("Select a Script...").tag(nil as UUID?)
                ForEach(profile.scripts) { script in
                    Text(script.name).tag(script.id as UUID?)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)

            Button { showingScriptCreation = true } label: {
                Label("Create New Script...", systemImage: "plus.circle")
                    .font(.subheadline)
            }
        } else {
            VStack(spacing: 8) {
                Text("No scripts defined in this profile.")
                    .foregroundColor(.secondary)
                    .italic()

                Button { showingScriptCreation = true } label: {
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
            Picker("Category", selection: $systemCommandCategory) {
                ForEach(SystemCommandCategory.allCases, id: \.self) { category in
                    Text(category.rawValue).tag(category)
                }
            }
            .pickerStyle(.segmented)

            switch systemCommandCategory {
            case .app:
                AppSelectionButton(bundleId: appBundleIdentifier, showingPicker: $showingAppPicker)
                    .sheet(isPresented: $showingAppPicker) {
                        SystemActionAppPickerSheet(
                            currentBundleIdentifier: appBundleIdentifier.isEmpty ? nil : appBundleIdentifier
                        ) { app in
                            appBundleIdentifier = app.bundleIdentifier
                        }
                    }
                Toggle("Open in new window (Cmd+N)", isOn: $appNewWindow)
                    .font(.caption)
            case .shell:
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Command (e.g. say \"Hello\")", text: $shellCommandText)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)

                    Toggle("Run silently (no terminal window)", isOn: Binding(
                        get: { !shellRunInTerminal },
                        set: { shellRunInTerminal = !$0 }
                    ))
                        .font(.caption)

                    Text(shellRunInTerminal
                        ? "Opens a terminal window and executes the command"
                        : "Runs silently in the background (no visible output)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if shellRunInTerminal {
                        Divider()
                        TerminalAppPickerRow()
                    }
                }
            case .link:
                VStack(alignment: .leading, spacing: 8) {
                    TextField("URL (e.g. https://google.com)", text: $linkURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)

                    Button {
                        showingBookmarkPicker = true
                    } label: {
                        Label("Browse Bookmarks", systemImage: "book")
                            .font(.subheadline)
                    }
                    .sheet(isPresented: $showingBookmarkPicker) {
                        BookmarkPickerSheet { url in
                            linkURL = url
                        }
                    }

                    Text("Opens the URL in your default browser")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            case .webhook:
                VStack(alignment: .leading, spacing: 8) {
                    TextField("URL (e.g. https://api.example.com/webhook)", text: $webhookURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)

                    Picker("Method", selection: $webhookMethod) {
                        ForEach(HTTPMethod.allCases) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)

                    if [.POST, .PUT, .PATCH].contains(webhookMethod) {
                        TextField("Body (JSON)", text: $webhookBody, axis: .vertical)
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
                    TextField("WebSocket URL", text: $obsWebSocketURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                    TextField("Password (optional)", text: $obsWebSocketPassword)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                    TextField("Request Type", text: $obsRequestType)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                    TextField("Request Data (JSON, optional)", text: $obsRequestData, axis: .vertical)
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

        switch mappingType {
        case .singleKey:
            gesture = gesture.clearingConflicts(keeping: .keyPress)
            gesture.keyCode = keyCode
            gesture.modifiers = modifiers
        case .macro:
            gesture = gesture.clearingConflicts(keeping: .macro)
            gesture.macroId = selectedMacroId
        case .script:
            gesture = gesture.clearingConflicts(keeping: .script)
            gesture.scriptId = selectedScriptId
        case .systemCommand:
            gesture = gesture.clearingConflicts(keeping: .systemCommand)
            gesture.systemCommand = buildSystemCommand()
        }

        gesture.hint = hint.isEmpty ? nil : hint

        if isEditing {
            profileManager.updateGesture(gesture)
        } else {
            profileManager.addGesture(gesture)
        }

        dismiss()
    }

    // MARK: - System Command Helpers

    private func buildSystemCommand() -> SystemCommand? {
        switch systemCommandCategory {
        case .app:
            guard !appBundleIdentifier.isEmpty else { return nil }
            return .launchApp(bundleIdentifier: appBundleIdentifier, newWindow: appNewWindow)
        case .shell:
            guard !shellCommandText.isEmpty else { return nil }
            return .shellCommand(command: shellCommandText, inTerminal: shellRunInTerminal)
        case .link:
            guard !linkURL.isEmpty else { return nil }
            return .openLink(url: linkURL)
        case .webhook:
            guard !webhookURL.isEmpty else { return nil }
            let headers = webhookHeaders.isEmpty ? nil : webhookHeaders
            let body = webhookBody.isEmpty ? nil : webhookBody
            return .httpRequest(url: webhookURL, method: webhookMethod, headers: headers, body: body)
        case .obs:
            guard !obsWebSocketURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            guard !obsRequestType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let password = obsWebSocketPassword.trimmingCharacters(in: .whitespacesAndNewlines)
            let requestData = obsRequestData.trimmingCharacters(in: .whitespacesAndNewlines)
            return .obsWebSocket(
                url: obsWebSocketURL,
                password: password.isEmpty ? nil : password,
                requestType: obsRequestType,
                requestData: requestData.isEmpty ? nil : requestData
            )
        }
    }

    private func loadSystemCommandState(_ command: SystemCommand) {
        systemCommandCategory = command.category
        switch command {
        case .launchApp(let bundleId, let newWindow):
            appBundleIdentifier = bundleId
            appNewWindow = newWindow
        case .shellCommand(let cmd, let inTerminal):
            shellCommandText = cmd
            shellRunInTerminal = inTerminal
        case .openLink(let url):
            linkURL = url
        case .httpRequest(let url, let method, let headers, let body):
            webhookURL = url
            webhookMethod = method
            webhookHeaders = headers ?? [:]
            webhookBody = body ?? ""
        case .obsWebSocket(let url, let password, let requestType, let requestData):
            obsWebSocketURL = url
            obsWebSocketPassword = password ?? ""
            self.obsRequestType = requestType
            self.obsRequestData = requestData ?? ""
        }
    }
}
