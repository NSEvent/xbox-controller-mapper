import SwiftUI

// MARK: - Chord Mapping Sheet

struct ChordMappingSheet: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var controllerService: ControllerService
    @Environment(\.dismiss) private var dismiss

    var editingChord: ChordMapping?

    private var isDualSense: Bool {
        controllerService.threadSafeIsDualSense
    }

    private var isDualShock: Bool {
        controllerService.threadSafeIsDualShock
    }

    /// True for any PlayStation controller (DualSense or DualShock) - used for PS-style labels and touchpad
    private var isPlayStation: Bool {
        controllerService.threadSafeIsPlayStation
    }

    private var isDualSenseEdge: Bool {
        controllerService.threadSafeIsDualSenseEdge
    }

    @State private var selectedButtons: Set<ControllerButton> = []
    @State private var keyCode: CGKeyCode?
    @State private var modifiers = ModifierFlags()
    @State private var hint: String = ""
    @State private var hapticStyle: HapticStyle?
    @State private var showingKeyboard = false

    // Macro/Script support
    @State private var mappingType: MappingType = .singleKey
    @State private var selectedMacroId: UUID?
    @State private var selectedScriptId: UUID?

    // System command support
    @State private var systemCommandCategory: SystemCommandCategory = .shell
    @State private var appBundleIdentifier: String = ""
    @State private var appNewWindow: Bool = false
    @State private var shellCommandText: String = ""
    @State private var shellRunInTerminal: Bool = true
    @State private var linkURL: String = ""
    @State private var webhookURL: String = ""
    @State private var webhookMethod: HTTPMethod = .POST
    @State private var webhookBody: String = ""
    @State private var webhookHeaders: [String: String] = [:]
    @State private var newWebhookHeaderKey: String = ""
    @State private var newWebhookHeaderValue: String = ""
    @State private var obsWebSocketURL: String = "ws://127.0.0.1:4455"
    @State private var obsWebSocketPassword: String = ""
    @State private var obsRequestType: String = ""
    @State private var obsRequestData: String = ""
    @State private var showingAppPicker = false
    @State private var showingBookmarkPicker = false
    @State private var showingMacroCreation = false
    @State private var showingScriptCreation = false

    enum MappingType: Int {
        case singleKey = 0
        case macro = 1
        case systemCommand = 2
        case script = 3
    }

    private var isEditing: Bool { editingChord != nil }

    /// Whether the current button combination already exists as a chord (excluding the one being edited)
    private var chordAlreadyExists: Bool {
        guard selectedButtons.count >= 2,
              let profile = profileManager.activeProfile else { return false }
        return profile.chordMappings.contains { chord in
            chord.buttons == selectedButtons && chord.id != editingChord?.id
        }
    }

    /// Mapping of buttons that would create a duplicate chord to the chord they conflict with
    private var buttonConflicts: [ControllerButton: ChordMapping] {
        guard let profile = profileManager.activeProfile else { return [:] }
        return ChordMapping.conflictedButtonsWithChords(
            selectedButtons: selectedButtons,
            existingChords: profile.chordMappings,
            editingChordId: editingChord?.id
        )
    }

    private var canSave: Bool {
        selectedButtons.count >= 2 &&
        (mappingType != .singleKey || keyCode != nil || modifiers.hasAny) &&
        (mappingType != .macro || selectedMacroId != nil) &&
        (mappingType != .script || selectedScriptId != nil) &&
        (mappingType != .systemCommand || buildChordSystemCommand() != nil)
    }

    private func saveChord() {
        guard canSave else { return }

        let hintValue = hint.isEmpty ? nil : hint
        let finalKeyCode = mappingType == .singleKey ? keyCode : nil
        let finalModifiers = mappingType == .singleKey ? modifiers : ModifierFlags()
        let finalMacroId = mappingType == .macro ? selectedMacroId : nil
        let finalScriptId = mappingType == .script ? selectedScriptId : nil
        let finalSystemCommand: SystemCommand? = mappingType == .systemCommand ? buildChordSystemCommand() : nil

        if let existingChord = editingChord {
            var updatedChord = existingChord
            updatedChord.buttons = selectedButtons
            updatedChord.keyCode = finalKeyCode
            updatedChord.modifiers = finalModifiers
            updatedChord.macroId = finalMacroId
            updatedChord.scriptId = finalScriptId
            updatedChord.systemCommand = finalSystemCommand
            updatedChord.hint = hintValue
            updatedChord.hapticStyle = hapticStyle
            profileManager.updateChord(updatedChord)
        } else {
            let chord = ChordMapping(
                buttons: selectedButtons,
                keyCode: finalKeyCode,
                modifiers: finalModifiers,
                macroId: finalMacroId,
                scriptId: finalScriptId,
                systemCommand: finalSystemCommand,
                hint: hintValue,
                hapticStyle: hapticStyle
            )
            profileManager.addChord(chord)
        }
        dismiss()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text(isEditing ? "Edit Chord" : "Add Chord")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Select buttons (2 or more):")
                    .font(.subheadline)

                // Visual Controller Layout
                VStack(spacing: 10) {
                    // Top Row: Triggers & Bumpers
                    HStack(spacing: 120) {
                        VStack(spacing: 8) {
                            toggleButton(.leftTrigger)
                            toggleButton(.leftBumper)
                        }

                        VStack(spacing: 8) {
                            toggleButton(.rightTrigger)
                            toggleButton(.rightBumper)
                        }
                    }

                    // Middle Row: D-Pad, System, Face Buttons, Sticks
                    HStack(alignment: .top, spacing: 40) {
                        // Left Column: D-Pad & L3 Stick
                        VStack(spacing: 25) {
                            // D-Pad Cross (aligned with face buttons)
                            VStack(spacing: 2) {
                                toggleButton(.dpadUp)
                                HStack(spacing: 25) {
                                    toggleButton(.dpadLeft)
                                    toggleButton(.dpadRight)
                                }
                                toggleButton(.dpadDown)
                            }

                            toggleButton(.leftThumbstick)
                        }

                        // Center Column: System Buttons
                        VStack(spacing: 15) {
                            toggleButton(.xbox)
                            HStack(spacing: 25) {
                                toggleButton(.view)
                                toggleButton(.menu)
                            }
                            // Show mic mute for DualSense, share for Xbox only
                            // DualShock 4's physical Share button maps to .view (buttonOptions), not .share
                            if isDualSense {
                                toggleButton(.micMute)
                            } else if !isDualShock {
                                toggleButton(.share)
                            }
                            // Touchpad button for PlayStation controllers (DualSense/DualShock)
                            if isPlayStation {
                                toggleButton(.touchpadButton)
                            }
                        }
                        .padding(.top, 15)

                        // Right Column: Face Buttons & Stick
                        VStack(spacing: 25) {
                            // Face Buttons Diamond
                            VStack(spacing: 2) {
                                toggleButton(.y)
                                HStack(spacing: 25) {
                                    toggleButton(.x)
                                    toggleButton(.b)
                                }
                                toggleButton(.a)
                            }

                            toggleButton(.rightThumbstick)
                        }
                    }

                    // Edge Controls (function buttons and paddles)
                    if isDualSenseEdge {
                        VStack(spacing: 8) {
                            Text("EDGE CONTROLS")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)

                            // Function buttons row (above touchpad area)
                            HStack(spacing: 40) {
                                toggleButton(.leftFunction)
                                Text("Fn")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.secondary)
                                toggleButton(.rightFunction)
                            }

                            // Paddles row (back of controller)
                            HStack(spacing: 40) {
                                toggleButton(.leftPaddle)
                                Text("Paddles")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.secondary)
                                toggleButton(.rightPaddle)
                            }
                        }
                        .padding(.top, 20)
                    }
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Action:")
                        .font(.subheadline)

                    Spacer()

                    Picker("Action type", selection: $mappingType) {
                        Text("Key").tag(MappingType.singleKey)
                        Text("Macro").tag(MappingType.macro)
                        Text("Script").tag(MappingType.script)
                        Text("System").tag(MappingType.systemCommand)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
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
                    // MACRO SELECTION
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
                } else if mappingType == .script {
                    // SCRIPT SELECTION
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
                } else {
                    // SYSTEM COMMAND SELECTION
                    chordSystemCommandContent
                }

                // Hint field
                HStack {
                    Text("Hint:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    TextField("e.g. Copy, Paste, Switch App...", text: $hint)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                }

                HapticStylePicker(hapticStyle: $hapticStyle)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(isEditing ? "Save" : "Add") {
                    saveChord()
                }
                .disabled(!canSave)
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
    }
    .onSubmit { saveChord() }
    .frame(width: 850)
        .onAppear {
            if let chord = editingChord {
                selectedButtons = chord.buttons
                keyCode = chord.keyCode
                modifiers = chord.modifiers
                hint = chord.hint ?? ""
                hapticStyle = chord.hapticStyle

                if let systemCommand = chord.systemCommand {
                    mappingType = .systemCommand
                    loadChordSystemCommandState(systemCommand)
                } else if let macroId = chord.macroId {
                    mappingType = .macro
                    selectedMacroId = macroId
                } else if let scriptId = chord.scriptId {
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

    // MARK: - System Command Helpers

    @ViewBuilder
    private var chordSystemCommandContent: some View {
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

                    DisclosureGroup("Headers") {
                        ForEach(Array(webhookHeaders.keys.sorted()), id: \.self) { key in
                            HStack {
                                Text(key)
                                    .font(.caption)
                                Spacer()
                                Text(webhookHeaders[key] ?? "")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Button {
                                    webhookHeaders.removeValue(forKey: key)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        HStack {
                            TextField("Header", text: $newWebhookHeaderKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                            TextField("Value", text: $newWebhookHeaderValue)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                            Button {
                                if !newWebhookHeaderKey.isEmpty {
                                    webhookHeaders[newWebhookHeaderKey] = newWebhookHeaderValue
                                    newWebhookHeaderKey = ""
                                    newWebhookHeaderValue = ""
                                }
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.green)
                            }
                            .buttonStyle(.plain)
                            .disabled(newWebhookHeaderKey.isEmpty)
                        }
                    }

                    Text("Fires an HTTP request when triggered. Use for webhooks, APIs, home automation, etc.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            case .obs:
                VStack(alignment: .leading, spacing: 8) {
                    TextField("WebSocket URL (e.g. ws://127.0.0.1:4455)", text: $obsWebSocketURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)

                    SecureField("Password (optional)", text: $obsWebSocketPassword)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)

                    TextField("Request Type (e.g. StartRecord)", text: $obsRequestType)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)

                    TextField("Request Data (JSON object, optional)", text: $obsRequestData, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                        .lineLimit(3...6)

                    Text("Sends any OBS WebSocket v5 request type with optional requestData JSON.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func buildChordSystemCommand() -> SystemCommand? {
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

    private func loadChordSystemCommandState(_ command: SystemCommand) {
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
            obsRequestType = requestType
            obsRequestData = requestData ?? ""
        }
    }

    @ViewBuilder
    private func toggleButton(_ button: ControllerButton) -> some View {
        let scale: CGFloat = 1.3
        let conflictingChord = buttonConflicts[button]
        let isConflicted = conflictingChord != nil
        let isSelected = selectedButtons.contains(button)
        let buttonName = button.displayName(forDualSense: isPlayStation)

        VStack(spacing: 2) {
            Button(action: {
                if isSelected {
                    selectedButtons.remove(button)
                } else if !isConflicted {
                    selectedButtons.insert(button)
                }
            }) {
                ButtonIconView(button: button, isPressed: isSelected, isDualSense: isPlayStation)
                    .scaleEffect(scale)
                    .frame(width: buttonWidth(for: button) * scale, height: buttonHeight(for: button) * scale)
                    .opacity(isConflicted ? 0.3 : (isSelected ? 1.0 : 0.7))
                    .overlay {
                        if isSelected {
                            selectionBorder(for: button)
                                .scaleEffect(scale)
                        }
                    }
            }
            .buttonStyle(.plain)
            .disabled(isConflicted)
            .accessibilityLabel(buttonName)
            .accessibilityValue(isConflicted ? "Unavailable, conflicts with existing chord" : (isSelected ? "Selected" : "Not selected"))
            .accessibilityAddTraits(.isToggle)

            // Show conflicting chord pill below the button
            if let chord = conflictingChord {
                conflictChordPill(chord: chord)
            }
        }
    }

    /// Small pill showing the chord that conflicts with this button
    @ViewBuilder
    private func conflictChordPill(chord: ChordMapping) -> some View {
        Text(chord.buttonsDisplayString)
            .font(.system(size: 8, weight: .medium))
            .foregroundColor(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.secondary.opacity(0.2))
            .cornerRadius(4)
    }

    private enum SelectionShape {
        case circle, square, roundedRect
    }

    @ViewBuilder
    private func selectionBorder(for button: ControllerButton) -> some View {
        let borderColor: Color = chordAlreadyExists ? .gray : .accentColor
        let shape: SelectionShape = {
            switch button {
            case .micMute:
                return .circle  // Mic mute is circular
            case .touchpadButton:
                return .square  // Touchpad click is square
            default:
                switch button.category {
                case .face, .special, .thumbstick, .dpad:
                    return .circle
                default:
                    return .roundedRect
                }
            }
        }()

        switch shape {
        case .circle:
            Circle()
                .stroke(borderColor, lineWidth: 3)
                .shadow(color: borderColor.opacity(0.8), radius: 4)
        case .square:
            RoundedRectangle(cornerRadius: 4)
                .stroke(borderColor, lineWidth: 3)
                .shadow(color: borderColor.opacity(0.8), radius: 4)
                .aspectRatio(1, contentMode: .fit)
        case .roundedRect:
            RoundedRectangle(cornerRadius: 5)
                .stroke(borderColor, lineWidth: 3)
                .shadow(color: borderColor.opacity(0.8), radius: 4)
        }
    }

    private func buttonWidth(for button: ControllerButton) -> CGFloat {
        switch button.category {
        case .face, .special, .thumbstick, .dpad: return 28
        case .bumper, .trigger: return 42
        case .touchpad: return 48
        case .paddle: return 36
        }
    }

    private func buttonHeight(for button: ControllerButton) -> CGFloat {
        switch button.category {
        case .face, .special, .thumbstick, .dpad: return 28
        case .bumper, .trigger: return 22
        case .touchpad: return 24
        case .paddle: return 24
        }
    }
}
