import SwiftUI
import AppKit

/// Settings view for the on-screen keyboard feature
struct OnScreenKeyboardSettingsView: View {
    @EnvironmentObject var profileManager: ProfileManager

    @State private var newTextSnippet = ""
    @State private var newTerminalCommand = ""
    @State private var editingTextId: UUID?
    @State private var editingCommandId: UUID?
    @State private var editText = ""
    @State private var hasRequestedAutomation = false
    @State private var automationPermissionGranted = false
    @State private var customTerminalApp = ""
    @State private var isUsingCustomTerminal = false
    @State private var showingAppPicker = false
    @State private var appPickerSearchText = ""
    @State private var showingTextSnippetVariableHelp = false
    @State private var showingTerminalVariableHelp = false

    // Variable autocomplete state
    @State private var showSnippetSuggestions = false
    @State private var showCommandSuggestions = false
    @State private var showEditSuggestions = false

    private var textSnippets: [QuickText] {
        profileManager.onScreenKeyboardSettings.quickTexts.filter { !$0.isTerminalCommand }
    }

    private var terminalCommands: [QuickText] {
        profileManager.onScreenKeyboardSettings.quickTexts.filter { $0.isTerminalCommand }
    }

    private var appBarItems: [AppBarItem] {
        profileManager.onScreenKeyboardSettings.appBarItems
    }

    private var installedApps: [AppInfo] {
        AppMonitor().installedApplications
    }

    var body: some View {
        Form {
            // Text Snippets Section
            textSnippetsSection

            // Terminal Section
            terminalSection

            // App Bar Section
            appBarSection

            // Keyboard Layout Section
            keyboardLayoutSection
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            checkAutomationPermission()
            setupCustomTerminal()
        }
    }

    // MARK: - Automation Permission

    private func checkAutomationPermission() {
        // Run a simple AppleScript to check if we have permission
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
                    // If no error, permission was granted
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

    // MARK: - Variable Hint Section

    private func variableHintSection(isPresented: Binding<Bool>) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .foregroundColor(.secondary)
                .font(.caption)

            Text("Type")
                .foregroundColor(.secondary)

            Text("{")
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(3)

            Text("to insert variables like date, time, clipboard, etc.")
                .foregroundColor(.secondary)

            Button {
                isPresented.wrappedValue.toggle()
            } label: {
                Text("View all")
                    .font(.caption)
            }
            .buttonStyle(.link)
            .popover(isPresented: isPresented, arrowEdge: .bottom) {
                variableHelpPopover
            }
        }
        .font(.caption)
    }

    private var variableHelpPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Available Variables")
                .font(.headline)

            Text("Type { followed by a variable name. Suggestions will appear as you type.")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(VariableExpander.availableVariables, id: \.name) { variable in
                        HStack(spacing: 12) {
                            Text("{\(variable.name)}")
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.medium)
                                .frame(width: 130, alignment: .leading)

                            Text(variable.description)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Spacer()

                            Text(variable.example)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.trailing, 12)
            }
            .frame(maxHeight: 400)
        }
        .padding()
        .frame(width: 450)
    }

    // MARK: - Variable Autocomplete Helpers

    /// Finds the variable prefix being typed (text after the last unclosed `{`)
    private func variablePrefix(in text: String) -> String? {
        // Find the last `{` that isn't closed by `}`
        guard let lastBrace = text.lastIndex(of: "{") else { return nil }

        let afterBrace = text[text.index(after: lastBrace)...]

        // If there's a `}` after the `{`, the variable is already closed
        if afterBrace.contains("}") { return nil }

        return String(afterBrace)
    }

    /// Returns filtered variables matching the given prefix
    private func filteredVariables(for prefix: String) -> [(name: String, description: String, example: String)] {
        if prefix.isEmpty {
            return VariableExpander.availableVariables
        }
        return VariableExpander.availableVariables.filter {
            $0.name.lowercased().hasPrefix(prefix.lowercased())
        }
    }

    /// Inserts a variable into text, replacing any partial variable being typed
    private func insertVariable(_ variableName: String, into text: inout String) {
        guard let lastBrace = text.lastIndex(of: "{") else { return }
        let beforeBrace = String(text[..<lastBrace])
        text = beforeBrace + "{\(variableName)}"
    }

    /// Checks if suggestions should be shown for the given text
    private func shouldShowSuggestions(for text: String) -> Bool {
        guard let prefix = variablePrefix(in: text) else { return false }
        return !filteredVariables(for: prefix).isEmpty
    }

    /// Variable suggestion dropdown view
    @ViewBuilder
    private func variableSuggestionsView(for text: Binding<String>, showSuggestions: Binding<Bool>) -> some View {
        if let prefix = variablePrefix(in: text.wrappedValue) {
            let matches = filteredVariables(for: prefix)
            if !matches.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(matches, id: \.name) { variable in
                        Button {
                            insertVariable(variable.name, into: &text.wrappedValue)
                            showSuggestions.wrappedValue = false
                        } label: {
                            HStack {
                                Text("{\(variable.name)}")
                                    .font(.system(.caption, design: .monospaced))
                                    .fontWeight(.medium)

                                Spacer()

                                Text(variable.description)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(Color(nsColor: .controlBackgroundColor))
                    }
                }
                .background(Color(nsColor: .windowBackgroundColor))
                .cornerRadius(6)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                .frame(maxWidth: 300)
            }
        }
    }

    // MARK: - App Bar Section

    private var appBarSection: some View {
        Section {
            // Add app button
            Button {
                showingAppPicker = true
            } label: {
                Label("Add App", systemImage: "plus.app")
            }
            .sheet(isPresented: $showingAppPicker) {
                appPickerSheet
            }

            // List of app bar items
            if appBarItems.isEmpty {
                Text("No apps added yet")
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                List {
                    ForEach(appBarItems) { item in
                        appBarListRow(item)
                    }
                    .onMove { source, destination in
                        profileManager.moveAppBarItems(from: source, to: destination)
                    }
                }
                .listStyle(.plain)
                .frame(height: CGFloat(appBarItems.count) * 32)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
            }
        } header: {
            Text("App Bar")
        } footer: {
            Text("Add apps for quick switching from the on-screen keyboard.")
        }
    }

    @ViewBuilder
    private func appBarListRow(_ item: AppBarItem) -> some View {
        HStack {
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)
                .frame(width: 20)

            // App icon
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.bundleIdentifier),
               let icon = NSWorkspace.shared.icon(forFile: url.path) as NSImage? {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundColor(.secondary)
            }

            Text(item.displayName)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            Button {
                profileManager.removeAppBarItem(item)
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
        }
    }

    private var appPickerSheet: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add App")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    showingAppPicker = false
                }
            }
            .padding()

            Divider()

            // Search field
            TextField("Search apps...", text: $appPickerSearchText)
                .textFieldStyle(.roundedBorder)
                .padding()

            Divider()

            // App list
            List {
                let filteredApps = installedApps.filter { app in
                    appPickerSearchText.isEmpty ||
                    app.name.localizedCaseInsensitiveContains(appPickerSearchText)
                }

                ForEach(filteredApps) { app in
                    let alreadyAdded = appBarItems.contains { $0.bundleIdentifier == app.bundleIdentifier }

                    Button {
                        if !alreadyAdded {
                            let item = AppBarItem(
                                bundleIdentifier: app.bundleIdentifier,
                                displayName: app.name
                            )
                            profileManager.addAppBarItem(item)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            if let icon = app.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 32, height: 32)
                            } else {
                                Image(systemName: "app.fill")
                                    .resizable()
                                    .frame(width: 32, height: 32)
                            }

                            Text(app.name)

                            Spacer()

                            if alreadyAdded {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.green)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(alreadyAdded)
                }
            }
        }
        .frame(width: 400, height: 500)
        .onDisappear {
            appPickerSearchText = ""
        }
    }

    // MARK: - Keyboard Layout Section

    private var keyboardLayoutSection: some View {
        Section("Keyboard Layout") {
            Toggle(isOn: Binding(
                get: { profileManager.onScreenKeyboardSettings.showExtendedFunctionKeys },
                set: { newValue in
                    var settings = profileManager.onScreenKeyboardSettings
                    settings.showExtendedFunctionKeys = newValue
                    profileManager.updateOnScreenKeyboardSettings(settings)
                }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Show F13-F20 Keys")
                    Text("Display extended function keys (F13-F20) in a row above F1-F12.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }


    // MARK: - Text Snippets Section

    private var textSnippetsSection: some View {
        Section {
            // Variable hint
            variableHintSection(isPresented: $showingTextSnippetVariableHelp)

            // Add new text snippet with autocomplete
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    TextField("Enter text snippet...", text: $newTextSnippet)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: newTextSnippet) { _, newValue in
                            showSnippetSuggestions = shouldShowSuggestions(for: newValue)
                        }
                        .onSubmit {
                            if !showSnippetSuggestions {
                                addTextSnippet()
                            }
                        }

                    Button("Add") {
                        addTextSnippet()
                    }
                    .disabled(newTextSnippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if showSnippetSuggestions {
                    variableSuggestionsView(for: $newTextSnippet, showSuggestions: $showSnippetSuggestions)
                }
            }

            // List of text snippets
            if textSnippets.isEmpty {
                Text("No text snippets yet")
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ForEach(textSnippets) { snippet in
                    quickTextRow(snippet, isTerminalCommand: false)
                }
                .onMove { source, destination in
                    moveQuickTexts(from: source, to: destination, isTerminalCommand: false)
                }
            }

            // Typing Speed
            VStack(alignment: .leading, spacing: 6) {
                Picker("Typing Speed", selection: Binding(
                    get: { profileManager.onScreenKeyboardSettings.typingDelay },
                    set: { profileManager.setTypingDelay($0) }
                )) {
                    ForEach(OnScreenKeyboardSettings.typingSpeedPresets, id: \.delay) { preset in
                        Text(preset.name).tag(preset.delay)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
            }
        } header: {
            Text("Text Snippets")
        } footer: {
            Text("Click these to type the text into any app.")
        }
    }

    // MARK: - Terminal Section

    private var terminalSection: some View {
        Section {
            // Variable hint
            variableHintSection(isPresented: $showingTerminalVariableHelp)

            // Add new terminal command with autocomplete
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    TextField("Enter terminal command...", text: $newTerminalCommand)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: newTerminalCommand) { _, newValue in
                            showCommandSuggestions = shouldShowSuggestions(for: newValue)
                        }
                        .onSubmit {
                            if !showCommandSuggestions {
                                addTerminalCommand()
                            }
                        }

                    Button("Add") {
                        addTerminalCommand()
                    }
                    .disabled(newTerminalCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if showCommandSuggestions {
                    variableSuggestionsView(for: $newTerminalCommand, showSuggestions: $showCommandSuggestions)
                }
            }

            // List of terminal commands
            if terminalCommands.isEmpty {
                Text("No terminal commands yet")
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ForEach(terminalCommands) { command in
                    quickTextRow(command, isTerminalCommand: true)
                }
                .onMove { source, destination in
                    moveQuickTexts(from: source, to: destination, isTerminalCommand: true)
                }
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
    }

    // MARK: - Quick Text Row

    @ViewBuilder
    private func quickTextRow(_ quickText: QuickText, isTerminalCommand: Bool) -> some View {
        let isEditing = isTerminalCommand ? editingCommandId == quickText.id : editingTextId == quickText.id

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "line.3.horizontal")
                    .foregroundColor(.secondary)
                    .frame(width: 20)

                if isEditing {
                    TextField("", text: $editText)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: editText) { _, newValue in
                            showEditSuggestions = shouldShowSuggestions(for: newValue)
                        }
                        .onSubmit {
                            if !showEditSuggestions {
                                saveEdit(quickText)
                            }
                        }

                    Button("Save") {
                        saveEdit(quickText)
                    }

                    Button("Cancel") {
                        cancelEdit(isTerminalCommand: isTerminalCommand)
                    }
                } else {
                    Text(quickText.text)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if quickText.containsVariables {
                        Image(systemName: "function")
                            .font(.caption2)
                            .foregroundColor(.blue)
                            .help("Contains variables that will be expanded")
                    }

                    Spacer()

                    Button {
                        startEdit(quickText, isTerminalCommand: isTerminalCommand)
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)

                    Button {
                        profileManager.removeQuickText(quickText)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }

            // Show variable suggestions when editing
            if isEditing && showEditSuggestions {
                variableSuggestionsView(for: $editText, showSuggestions: $showEditSuggestions)
                    .padding(.leading, 28)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }

    // MARK: - Actions

    private func addTextSnippet() {
        let trimmed = newTextSnippet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let snippet = QuickText(text: trimmed, isTerminalCommand: false)
        profileManager.addQuickText(snippet)
        newTextSnippet = ""
    }

    private func addTerminalCommand() {
        let trimmed = newTerminalCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let command = QuickText(text: trimmed, isTerminalCommand: true)
        profileManager.addQuickText(command)
        newTerminalCommand = ""
    }

    private func startEdit(_ quickText: QuickText, isTerminalCommand: Bool) {
        editText = quickText.text
        if isTerminalCommand {
            editingCommandId = quickText.id
            editingTextId = nil
        } else {
            editingTextId = quickText.id
            editingCommandId = nil
        }
    }

    private func saveEdit(_ quickText: QuickText) {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var updated = quickText
        updated.text = trimmed
        profileManager.updateQuickText(updated)

        editingTextId = nil
        editingCommandId = nil
        editText = ""
    }

    private func cancelEdit(isTerminalCommand: Bool) {
        if isTerminalCommand {
            editingCommandId = nil
        } else {
            editingTextId = nil
        }
        editText = ""
    }

    private func moveQuickTexts(from source: IndexSet, to destination: Int, isTerminalCommand: Bool) {
        // Get the filtered list
        let filteredList = isTerminalCommand ? terminalCommands : textSnippets

        // Get the items being moved
        var items = filteredList
        items.move(fromOffsets: source, toOffset: destination)

        // Rebuild the full list maintaining the order
        var newQuickTexts: [QuickText] = []
        if isTerminalCommand {
            // Keep text snippets first, then reordered terminal commands
            newQuickTexts = textSnippets + items
        } else {
            // Keep reordered text snippets first, then terminal commands
            newQuickTexts = items + terminalCommands
        }

        var settings = profileManager.onScreenKeyboardSettings
        settings.quickTexts = newQuickTexts
        profileManager.updateOnScreenKeyboardSettings(settings)
    }
}

#Preview {
    OnScreenKeyboardSettingsView()
        .environmentObject(ProfileManager())
        .frame(width: 600, height: 500)
}
