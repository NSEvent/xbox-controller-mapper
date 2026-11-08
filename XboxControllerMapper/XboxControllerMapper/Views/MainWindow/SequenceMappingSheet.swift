import SwiftUI

// MARK: - Sequence Mapping Sheet

struct SequenceMappingSheet: View, MappingControllerTypeProviding {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var controllerService: ControllerService
    @Environment(\.dismiss) private var dismiss
	@State private var editorScope = MappingEditorScope()

    var editingSequence: SequenceMapping?

    private var joystickSettings: JoystickSettings {
        profileManager.activeProfile?.joystickSettings ?? .default
    }

	@State private var sequenceDraft = SequenceEditorDraft()
	@StateObject private var physicalCapture = SequenceInputSession()
    @State private var stepTimeout: TimeInterval = Config.defaultSequenceStepTimeout
    @State private var keyCode: CGKeyCode?
    @State private var modifiers = ModifierFlags()
    @State private var hint: String = ""
    @State private var hapticStyle: HapticStyle?
    @State private var showingKeyboard = false

    // Macro/Script support
    @State private var mappingType: MappingType = .singleKey
    @State private var selectedMacroId: UUID?
    @State private var selectedScriptId: UUID?
    @State private var midiControlChange = MIDIControlChange()

    // System command support
    @State private var systemCommandCategory: SystemCommandCategory = .shell
	@State private var profileCommand = ProfileCommandSelection()
    @State private var appBundleIdentifier: String = ""
    @State private var appNewWindow: Bool = false
	@State private var shortcutName = ""
    @State private var shellCommandText: String = ""
    @State private var shellRunInTerminal: Bool = true
    @State private var linkURL: String = ""
	@State private var ouraRingCommandOption: OuraRingSystemCommandOption = .centerRing
    @State private var webhookURL: String = ""
    @State private var webhookMethod: HTTPMethod = .POST
    @State private var webhookBody: String = ""
    @State private var webhookHeaders: [String: String] = [:]
    @State private var newWebhookHeaderKey: String = ""
    @State private var newWebhookHeaderValue: String = ""
    @State private var webhookShowNotification: Bool = false
    @State private var webhookMaxRetries: Int = 0
    @State private var webhookRetryDelay: Double = 1.0
    @State private var webhookOnSuccessCommand: String = ""
    @State private var webhookOnErrorCommand: String = ""
    @State private var webhookTimeout: Double = 10
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
		case midiControlChange = 4
    }

    private var isEditing: Bool { editingSequence != nil }

    /// Whether the current step sequence already exists (excluding the one being edited)
    private var sequenceAlreadyExists: Bool {
		guard sequenceDraft.steps.count >= 2,
              let profile = profileManager.activeProfile else { return false }
        return profile.sequenceMappings.contains { seq in
			seq.inputSteps == sequenceDraft.steps && seq.id != editingSequence?.id
        }
    }

	private var sharesPrefix: Bool {
		guard sequenceDraft.steps.count >= 2 else { return false }
		return profileManager.activeProfile?.sequenceMappings.contains { sequence in
			guard sequence.id != editingSequence?.id, sequence.inputSteps != sequenceDraft.steps else { return false }
			return sequence.inputSteps.starts(with: sequenceDraft.steps) || sequenceDraft.steps.starts(with: sequence.inputSteps)
		} == true
	}

    private var canSave: Bool {
		sequenceDraft.canSave &&
        !sequenceAlreadyExists &&
        (mappingType != .singleKey || keyCode != nil || modifiers.hasAny) &&
        (mappingType != .macro || selectedMacroId != nil) &&
        (mappingType != .script || selectedScriptId != nil) &&
        (mappingType != .systemCommand || buildSystemCommand() != nil)
    }

    private func saveSequence() {
		guard editorScope.canSave(to: profileManager.activeProfileId) else { return }
		guard canSave, !physicalCapture.isBusy else { return }

        let hintValue = hint.isEmpty ? nil : hint
        let finalKeyCode = mappingType == .singleKey ? keyCode : nil
        let finalModifiers = mappingType == .singleKey ? modifiers : ModifierFlags()
        let finalMacroId = mappingType == .macro ? selectedMacroId : nil
        let finalScriptId = mappingType == .script ? selectedScriptId : nil
        let finalSystemCommand: SystemCommand? = mappingType == .systemCommand ? buildSystemCommand() : nil
		let finalMIDIControlChange = mappingType == .midiControlChange ? midiControlChange : nil

        if let existingSequence = editingSequence {
            var updated = existingSequence
			updated.inputSteps = sequenceDraft.steps
			updated.usesReleaseSteps = sequenceDraft.usesReleaseSteps
            updated.stepTimeout = stepTimeout
            updated.keyCode = finalKeyCode
            updated.modifiers = finalModifiers
            updated.macroId = finalMacroId
            updated.scriptId = finalScriptId
            updated.systemCommand = finalSystemCommand
			updated.midiControlChange = finalMIDIControlChange
            updated.hint = hintValue
            updated.hapticStyle = hapticStyle
            profileManager.updateSequence(updated)
        } else {
            let sequence = SequenceMapping(
				chordSteps: sequenceDraft.steps,
                stepTimeout: stepTimeout,
                keyCode: finalKeyCode,
                modifiers: finalModifiers,
                macroId: finalMacroId,
                scriptId: finalScriptId,
                systemCommand: finalSystemCommand,
				midiControlChange: finalMIDIControlChange,
                hint: hintValue,
                hapticStyle: hapticStyle
            )
            profileManager.addSequence(sequence)
        }
        dismiss()
    }

	var body: some View {
		let presentationState = controllerPresentationState

		ScrollView {
            VStack(spacing: 20) {
                Text(isEditing ? "Edit Sequence" : "Add Sequence")
                    .font(.headline)

				SequenceStepsEditor(draft: $sequenceDraft, session: physicalCapture,
					descriptor: presentationState, joystickSettings: joystickSettings, timeout: stepTimeout)
				if sequenceAlreadyExists {
					Text("This sequence already exists").font(.caption).foregroundStyle(.red)
				}

				if sharesPrefix {
					Text("Another sequence shares these starting steps. Each sequence runs its action when it completes.")
						.font(.caption).foregroundStyle(.secondary)
				}

                // Step timeout slider
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
						Text("Maximum gap between steps:")
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "%.1fs", stepTimeout))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $stepTimeout, in: 0.1...1.5, step: 0.05)
						.accessibilityLabel("Maximum gap between steps")
                        .accessibilityValue(String(format: "%.1f seconds", stepTimeout))
					Text(sequenceDraft.usesReleaseSteps ? "Measured from release to the next step’s first press. Holding a step does not time out." : "Each button press must follow the previous one within this time.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

				Text("Ordinary button and chord actions still run. The sequence adds its action; recording and testing pause all actions.")
					.font(.caption).foregroundStyle(.secondary)

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
							Text("MIDI").tag(MappingType.midiControlChange)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
						.frame(width: 350)
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
                        if let profile = profileManager.activeProfile,
                           !profile.macros.isEmpty || !profileManager.sharedLibraryMacros.isEmpty {
                            Picker("Select Macro", selection: $selectedMacroId) {
                                Text("Select a Macro...").tag(nil as UUID?)
                                MacroPickerSections(
                                    profileMacros: profile.macros,
                                    sharedMacros: profileManager.sharedLibraryMacros
                                )
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
					} else if mappingType == .midiControlChange {
						MIDIControlChangeEditor(message: $midiControlChange)
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

                    HapticStylePicker(hapticStyle: $hapticStyle)
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
					.disabled(!canSave || physicalCapture.isBusy)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
        .onSubmit { saveSequence() }
        .frame(width: 850)
		.onDisappear { physicalCapture.cancel() }
		.mappingEditorScope($editorScope, profileId: profileManager.activeProfileId)
        .onAppear {
            if let sequence = editingSequence {
				sequenceDraft.load(sequence)
                stepTimeout = sequence.stepTimeout
                keyCode = sequence.keyCode
                modifiers = sequence.modifiers
                hint = sequence.hint ?? ""
                hapticStyle = sequence.hapticStyle

                if let systemCommand = sequence.systemCommand {
                    mappingType = .systemCommand
                    loadSystemCommandState(systemCommand)
                } else if let macroId = sequence.macroId {
                    mappingType = .macro
                    selectedMacroId = macroId
                } else if let scriptId = sequence.scriptId {
                    mappingType = .script
                    selectedScriptId = scriptId
				} else if let midiControlChange = sequence.midiControlChange {
					mappingType = .midiControlChange
					self.midiControlChange = midiControlChange
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
    private var sequenceSystemCommandContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Category", selection: $systemCommandCategory) {
                ForEach(SystemCommandCategory.allCases, id: \.self) { category in
					Text(category.displayName).tag(category)
                }
            }
            .pickerStyle(.segmented)

            switch systemCommandCategory {
			case .shortcut: ShortcutActionPicker(name: $shortcutName)
			case .profile:
				ProfileCommandPicker(selection: $profileCommand)
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
			case .ring:
				OuraRingSystemCommandPicker(selection: $ouraRingCommandOption)
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
		case .shortcut: return shortcutName.isEmpty ? nil : .runShortcut(name: shortcutName)
		case .profile:
			return profileCommand.systemCommand
        case .app:
            guard !appBundleIdentifier.isEmpty else { return nil }
            return .launchApp(bundleIdentifier: appBundleIdentifier, newWindow: appNewWindow)
        case .shell:
            guard !shellCommandText.isEmpty else { return nil }
            return .shellCommand(command: shellCommandText, inTerminal: shellRunInTerminal)
        case .link:
            guard !linkURL.isEmpty else { return nil }
            return .openLink(url: linkURL)
		case .ring:
			return ouraRingCommandOption.systemCommand
        case .webhook:
            guard !webhookURL.isEmpty else { return nil }
            let headers = webhookHeaders.isEmpty ? nil : webhookHeaders
            let body = webhookBody.isEmpty ? nil : webhookBody
            let rh = HTTPResponseHandling(
                showNotification: webhookShowNotification,
                maxRetries: webhookMaxRetries,
                retryDelay: webhookRetryDelay,
                onSuccessCommand: webhookOnSuccessCommand.isEmpty ? nil : webhookOnSuccessCommand,
                onErrorCommand: webhookOnErrorCommand.isEmpty ? nil : webhookOnErrorCommand,
                timeout: webhookTimeout
            )
            return .httpRequest(url: webhookURL, method: webhookMethod, headers: headers, body: body, responseHandling: rh.hasConfiguration ? rh : nil)
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
		case .runShortcut(let name): shortcutName = name
		case .switchProfile, .navigateProfile:
			profileCommand.load(command)
        case .launchApp(let bundleId, let newWindow):
            appBundleIdentifier = bundleId
            appNewWindow = newWindow
        case .shellCommand(let cmd, let inTerminal):
            shellCommandText = cmd
            shellRunInTerminal = inTerminal
        case .openLink(let url):
            linkURL = url
		case .centerOuraRing, .toggleOuraMotion:
			ouraRingCommandOption = OuraRingSystemCommandOption(command: command)
        case .httpRequest(let url, let method, let headers, let body, let responseHandling):
            webhookURL = url
            webhookMethod = method
            webhookHeaders = headers ?? [:]
            webhookBody = body ?? ""
            if let rh = responseHandling {
                webhookShowNotification = rh.showNotification
                webhookMaxRetries = rh.maxRetries
                webhookRetryDelay = rh.retryDelay
                webhookOnSuccessCommand = rh.onSuccessCommand ?? ""
                webhookOnErrorCommand = rh.onErrorCommand ?? ""
                webhookTimeout = rh.timeout
            }
        case .obsWebSocket(let url, let password, let requestType, let requestData):
            obsWebSocketURL = url
            obsWebSocketPassword = password ?? ""
            self.obsRequestType = requestType
            self.obsRequestData = requestData ?? ""
        }
    }
}
