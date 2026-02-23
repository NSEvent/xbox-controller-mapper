import SwiftUI
import AppKit

/// Terminal commands management section for the on-screen keyboard settings.
struct TerminalCommandsSection: View {
    @EnvironmentObject var profileManager: ProfileManager

    // Input state
    @State private var newTerminalCommand = ""

    // Editing state
    @State private var editingCommandId: UUID?
    @State private var editText = ""

    // Terminal app state
    @State private var customTerminalApp = ""
    @State private var isUsingCustomTerminal = false

    // Automation permission state
    @State private var hasRequestedAutomation = false
    @State private var automationPermissionGranted = false

    // Variable help popover
    @State private var showingVariableHelp = false

    // Variable autocomplete state
    @State private var showCommandSuggestions = false
    @State private var showEditSuggestions = false
    @State private var commandSuggestionIndex = 0
    @State private var editSuggestionIndex = 0

    private var textSnippets: [QuickText] {
        (profileManager.activeProfile?.onScreenKeyboardSettings.quickTexts ?? []).filter { !$0.isTerminalCommand }
    }

    private var terminalCommands: [QuickText] {
        (profileManager.activeProfile?.onScreenKeyboardSettings.quickTexts ?? []).filter { $0.isTerminalCommand }
    }

    private var commandSuggestionCount: Int {
        OSKVariableAutocomplete.suggestionCount(for: newTerminalCommand)
    }

    private var editSuggestionCount: Int {
        OSKVariableAutocomplete.suggestionCount(for: editText)
    }

    var body: some View {
        Section {
            // Variable hint
            OSKVariableHintView(isPresented: $showingVariableHelp)

            // Add new terminal command with autocomplete
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    VariableTextField(
                        text: $newTerminalCommand,
                        placeholder: "Enter terminal command...",
                        showingSuggestions: showCommandSuggestions,
                        suggestionCount: commandSuggestionCount,
                        selectedSuggestionIndex: $commandSuggestionIndex,
                        onSelectSuggestion: {
                            selectCommandSuggestion()
                        },
                        onSubmit: {
                            if !showCommandSuggestions {
                                addTerminalCommand()
                            }
                        }
                    )
                    .onChange(of: newTerminalCommand) { _, newValue in
                        let shouldShow = OSKVariableAutocomplete.shouldShowSuggestions(for: newValue)
                        if shouldShow && !showCommandSuggestions {
                            commandSuggestionIndex = 0
                        }
                        showCommandSuggestions = shouldShow
                    }

                    Button("Add") {
                        addTerminalCommand()
                    }
                    .disabled(newTerminalCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if showCommandSuggestions {
                    OSKVariableSuggestionsView(
                        text: $newTerminalCommand,
                        showSuggestions: $showCommandSuggestions,
                        selectedIndex: $commandSuggestionIndex
                    )
                }
            }

            // List of terminal commands
            if terminalCommands.isEmpty {
                Text("No terminal commands yet")
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                List {
                    ForEach(terminalCommands) { command in
                        quickTextRow(command)
                    }
                    .onMove { source, destination in
                        moveQuickTexts(from: source, to: destination)
                    }
                }
                .listStyle(.plain)
                .frame(height: CGFloat(terminalCommands.count) * 36)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
            }

            // Default Terminal App
            Picker("Default App", selection: Binding(
                get: {
                    let current = profileManager.onScreenKeyboardSettings.defaultTerminalApp
                    if OnScreenKeyboardSettings.terminalOptions.contains(current) {
                        return current
                    }
                    return "Other"
                },
                set: { newValue in
                    if newValue == "Other" {
                        isUsingCustomTerminal = true
                    } else {
                        isUsingCustomTerminal = false
                        profileManager.setDefaultTerminalApp(newValue)
                    }
                }
            )) {
                ForEach(OnScreenKeyboardSettings.terminalOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
                Divider()
                Text("Other...").tag("Other")
            }
            .pickerStyle(.menu)

            if isUsingCustomTerminal {
                HStack {
                    TextField("App name", text: $customTerminalApp)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            if !customTerminalApp.isEmpty {
                                profileManager.setDefaultTerminalApp(customTerminalApp)
                            }
                        }

                    Button("Set") {
                        if !customTerminalApp.isEmpty {
                            profileManager.setDefaultTerminalApp(customTerminalApp)
                        }
                    }
                    .disabled(customTerminalApp.isEmpty)
                }
            }

            // Permissions status
            if automationPermissionGranted {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Automation permission granted")
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text("Automation permission required")
                    }

                    Button("Open Automation Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                    }
                    .buttonStyle(.link)
                }
            }
        } header: {
            Text("Terminal")
        } footer: {
            Text("Click these to open a new terminal window and run the command.")
        }
        .onAppear {
            checkAutomationPermission()
            setupCustomTerminal()
        }
    }

    // MARK: - Quick Text Row

    @ViewBuilder
    private func quickTextRow(_ quickText: QuickText) -> some View {
        QuickTextRowView(
            quickText: quickText,
            isTerminalCommand: true,
            isEditing: editingCommandId == quickText.id,
            editText: $editText,
            showEditSuggestions: showEditSuggestions,
            editSuggestionCount: editSuggestionCount,
            editSuggestionIndex: $editSuggestionIndex,
            onSelectSuggestion: selectEditSuggestion,
            onSave: { saveEdit(quickText) },
            onCancel: { cancelEdit() },
            onStartEdit: { startEdit(quickText) },
            onDelete: { profileManager.removeQuickText(quickText) },
            onEditTextChange: { newValue in
                let shouldShow = OSKVariableAutocomplete.shouldShowSuggestions(for: newValue)
                if shouldShow && !showEditSuggestions {
                    editSuggestionIndex = 0
                }
                showEditSuggestions = shouldShow
            },
            variableSuggestionsView: {
                OSKVariableSuggestionsView(
                    text: $editText,
                    showSuggestions: $showEditSuggestions,
                    selectedIndex: $editSuggestionIndex
                )
            }
        )
    }

    // MARK: - Actions

    private func addTerminalCommand() {
        let trimmed = newTerminalCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let command = QuickText(text: trimmed, isTerminalCommand: true)
        profileManager.addQuickText(command)
        newTerminalCommand = ""
    }

    private func startEdit(_ quickText: QuickText) {
        editText = quickText.text
        editSuggestionIndex = 0
        showEditSuggestions = false
        editingCommandId = quickText.id
    }

    private func saveEdit(_ quickText: QuickText) {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var updated = quickText
        updated.text = trimmed
        profileManager.updateQuickText(updated)

        editingCommandId = nil
        editText = ""
    }

    private func cancelEdit() {
        editingCommandId = nil
        editText = ""
    }

    private func moveQuickTexts(from source: IndexSet, to destination: Int) {
        var items = terminalCommands
        items.move(fromOffsets: source, toOffset: destination)

        var settings = profileManager.onScreenKeyboardSettings
        settings.quickTexts = textSnippets + items
        profileManager.updateOnScreenKeyboardSettings(settings)
    }

    // MARK: - Variable Autocomplete

    private func selectCommandSuggestion() {
        guard let prefix = OSKVariableAutocomplete.variablePrefix(in: newTerminalCommand) else { return }
        let matches = OSKVariableAutocomplete.filteredVariables(for: prefix)
        guard commandSuggestionIndex < matches.count else { return }
        OSKVariableAutocomplete.insertVariable(matches[commandSuggestionIndex].name, into: &newTerminalCommand)
        showCommandSuggestions = false
        commandSuggestionIndex = 0
    }

    private func selectEditSuggestion() {
        guard let prefix = OSKVariableAutocomplete.variablePrefix(in: editText) else { return }
        let matches = OSKVariableAutocomplete.filteredVariables(for: prefix)
        guard editSuggestionIndex < matches.count else { return }
        OSKVariableAutocomplete.insertVariable(matches[editSuggestionIndex].name, into: &editText)
        showEditSuggestions = false
        editSuggestionIndex = 0
    }

    // MARK: - Automation Permission

    private func checkAutomationPermission() {
        let script = """
        tell application "System Events"
            return name of first process whose frontmost is true
        end tell
        """

        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: script) {
                scriptObject.executeAndReturnError(&error)
                DispatchQueue.main.async {
                    automationPermissionGranted = (error == nil)
                }
            }
        }
    }

    private func setupCustomTerminal() {
        let currentTerminal = profileManager.onScreenKeyboardSettings.defaultTerminalApp
        if !OnScreenKeyboardSettings.terminalOptions.contains(currentTerminal) {
            isUsingCustomTerminal = true
            customTerminalApp = currentTerminal
        }
    }
}
