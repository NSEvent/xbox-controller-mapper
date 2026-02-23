import SwiftUI

// MARK: - Sequence Mapping Sheet

struct SequenceMappingSheet: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var controllerService: ControllerService
    @Environment(\.dismiss) private var dismiss

    var editingSequence: SequenceMapping?

    private var isDualSense: Bool {
        controllerService.threadSafeIsDualSense
    }

    private var isDualShock: Bool {
        controllerService.threadSafeIsDualShock
    }

    private var isPlayStation: Bool {
        controllerService.threadSafeIsPlayStation
    }

    private var isDualSenseEdge: Bool {
        controllerService.threadSafeIsDualSenseEdge
    }

    @State private var steps: [ControllerButton] = []
    @State private var stepTimeout: TimeInterval = Config.defaultSequenceStepTimeout
    @State private var keyCode: CGKeyCode?
    @State private var modifiers = ModifierFlags()
    @State private var hint: String = ""
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

    private var isEditing: Bool { editingSequence != nil }

    /// Whether the current step sequence already exists (excluding the one being edited)
    private var sequenceAlreadyExists: Bool {
        guard steps.count >= 2,
              let profile = profileManager.activeProfile else { return false }
        return profile.sequenceMappings.contains { seq in
            seq.steps == steps && seq.id != editingSequence?.id
        }
    }

    private var canSave: Bool {
        steps.count >= 2 &&
        !sequenceAlreadyExists &&
        (mappingType != .singleKey || keyCode != nil || modifiers.hasAny) &&
        (mappingType != .macro || selectedMacroId != nil) &&
        (mappingType != .script || selectedScriptId != nil) &&
        (mappingType != .systemCommand || buildSystemCommand() != nil)
    }

    private func saveSequence() {
        guard canSave else { return }

        let hintValue = hint.isEmpty ? nil : hint
        let finalKeyCode = mappingType == .singleKey ? keyCode : nil
        let finalModifiers = mappingType == .singleKey ? modifiers : ModifierFlags()
        let finalMacroId = mappingType == .macro ? selectedMacroId : nil
        let finalScriptId = mappingType == .script ? selectedScriptId : nil
        let finalSystemCommand: SystemCommand? = mappingType == .systemCommand ? buildSystemCommand() : nil

        if let existingSequence = editingSequence {
            var updated = existingSequence
            updated.steps = steps
            updated.stepTimeout = stepTimeout
            updated.keyCode = finalKeyCode
            updated.modifiers = finalModifiers
            updated.macroId = finalMacroId
            updated.scriptId = finalScriptId
            updated.systemCommand = finalSystemCommand
            updated.hint = hintValue
            profileManager.updateSequence(updated)
        } else {
            let sequence = SequenceMapping(
                steps: steps,
                stepTimeout: stepTimeout,
                keyCode: finalKeyCode,
                modifiers: finalModifiers,
                macroId: finalMacroId,
                scriptId: finalScriptId,
                systemCommand: finalSystemCommand,
                hint: hintValue
            )
            profileManager.addSequence(sequence)
        }
        dismiss()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text(isEditing ? "Edit Sequence" : "Add Sequence")
                    .font(.headline)

                // Steps section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Button sequence (press order):")
                        .font(.subheadline)

                    // Current steps display
                    if !steps.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(Array(steps.enumerated()), id: \.offset) { index, button in
                                if index > 0 {
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.4))
                                        .accessibilityHidden(true)
                                }
                                HStack(spacing: 2) {
                                    ButtonIconView(button: button, isDualSense: isPlayStation)
                                        .accessibilityLabel("Step \(index + 1): \(button.displayName(forDualSense: isPlayStation))")
                                    Button(action: {
                                        steps.remove(at: index)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 10))
                                            .foregroundColor(.red.opacity(0.7))
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Remove \(button.displayName(forDualSense: isPlayStation)) from step \(index + 1)")
                                }
                            }

                            Spacer()

                            if steps.count > 1 {
                                Button(action: { steps.removeAll() }) {
                                    Text("Clear")
                                        .font(.caption)
                                        .foregroundColor(.red.opacity(0.8))
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Clear all steps")
                            }
                        }
                        .padding(8)
                        .frame(height: 40)
                        .background(Color.black.opacity(0.2))
                        .cornerRadius(8)
                        .accessibilityLabel("Current sequence: \(steps.map { $0.displayName(forDualSense: isPlayStation) }.joined(separator: ", then "))")
                    }

                    if sequenceAlreadyExists {
                        Text("This sequence already exists")
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    // Add step buttons
                    if steps.count < Config.maxSequenceSteps {
                        Text("Tap a button to add it as the next step:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        sequenceButtonGrid
                    } else {
                        Text("Maximum \(Config.maxSequenceSteps) steps reached")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Step timeout slider
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Max time between presses:")
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "%.1fs", stepTimeout))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $stepTimeout, in: 0.1...1.5, step: 0.05)
                        .accessibilityLabel("Maximum time between presses")
                        .accessibilityValue(String(format: "%.1f seconds", stepTimeout))
                    Text("Each button press must follow the previous one within this time.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Action section
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
                        sequenceSystemCommandContent
                    }

                    // Hint field
                    HStack {
                        Text("Hint:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        TextField("e.g. Quick Save, Combo Attack...", text: $hint)
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
                        saveSequence()
                    }
                    .disabled(!canSave)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
        .onSubmit { saveSequence() }
        .frame(width: 850)
        .onAppear {
            if let sequence = editingSequence {
                steps = sequence.steps
                stepTimeout = sequence.stepTimeout
                keyCode = sequence.keyCode
                modifiers = sequence.modifiers
                hint = sequence.hint ?? ""

                if let systemCommand = sequence.systemCommand {
                    mappingType = .systemCommand
                    loadSystemCommandState(systemCommand)
                } else if let macroId = sequence.macroId {
                    mappingType = .macro
                    selectedMacroId = macroId
                } else if let scriptId = sequence.scriptId {
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

    // MARK: - Button Grid for Adding Steps

    @ViewBuilder
    private var sequenceButtonGrid: some View {
        VStack(spacing: 10) {
            // Top Row: Triggers & Bumpers
            HStack(spacing: 120) {
                VStack(spacing: 8) {
                    addStepButton(.leftTrigger)
                    addStepButton(.leftBumper)
                }

                VStack(spacing: 8) {
                    addStepButton(.rightTrigger)
                    addStepButton(.rightBumper)
                }
            }

            // Middle Row: D-Pad, System, Face Buttons, Sticks
            HStack(alignment: .top, spacing: 40) {
                // Left Column: D-Pad & L3
                VStack(spacing: 25) {
                    VStack(spacing: 2) {
                        addStepButton(.dpadUp)
                        HStack(spacing: 25) {
                            addStepButton(.dpadLeft)
                            addStepButton(.dpadRight)
                        }
                        addStepButton(.dpadDown)
                    }

                    addStepButton(.leftThumbstick)
                }

                // Center Column: System Buttons
                VStack(spacing: 15) {
                    addStepButton(.xbox)
                    HStack(spacing: 25) {
                        addStepButton(.view)
                        addStepButton(.menu)
                    }
                    if isDualSense {
                        addStepButton(.micMute)
                    } else if !isDualShock {
                        addStepButton(.share)
                    }
                    if isPlayStation {
                        addStepButton(.touchpadButton)
                    }
                }
                .padding(.top, 15)

                // Right Column: Face Buttons & Stick
                VStack(spacing: 25) {
                    VStack(spacing: 2) {
                        addStepButton(.y)
                        HStack(spacing: 25) {
                            addStepButton(.x)
                            addStepButton(.b)
                        }
                        addStepButton(.a)
                    }

                    addStepButton(.rightThumbstick)
                }
            }

            // Edge Controls
            if isDualSenseEdge {
                VStack(spacing: 8) {
                    Text("EDGE CONTROLS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)

                    HStack(spacing: 40) {
                        addStepButton(.leftFunction)
                        Text("Fn")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        addStepButton(.rightFunction)
                    }

                    HStack(spacing: 40) {
                        addStepButton(.leftPaddle)
                        Text("Paddles")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        addStepButton(.rightPaddle)
                    }
                }
                .padding(.top, 20)
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func addStepButton(_ button: ControllerButton) -> some View {
        let scale: CGFloat = 1.3
        let buttonName = button.displayName(forDualSense: isPlayStation)

        Button(action: {
            if steps.count < Config.maxSequenceSteps {
                steps.append(button)
            }
        }) {
            ButtonIconView(button: button, isPressed: false, isDualSense: isPlayStation)
                .scaleEffect(scale)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Add \(buttonName) step")
        .accessibilityHint("Adds \(buttonName) as the next step in the sequence")
    }

    // MARK: - System Command Helpers

    @ViewBuilder
    private var sequenceSystemCommandContent: some View {
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
