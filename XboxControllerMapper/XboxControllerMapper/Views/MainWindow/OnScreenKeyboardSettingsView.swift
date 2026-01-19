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
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                Text("On-Screen Keyboard")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Configure quick text snippets and terminal commands that appear above the on-screen keyboard.")
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                // Text Snippets Section
                textSnippetsSection

                Divider()

                // Typing Speed Settings (related to text snippets)
                typingSpeedSection

                Divider()

                // Terminal Commands Section
                terminalCommandsSection

                Divider()

                // Terminal App Settings
                terminalAppSection

                Divider()

                // App Bar Section
                appBarSection

                Divider()

                // Extended Function Keys Section
                extendedFunctionKeysSection
            }
            .padding(24)
        }
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

    // MARK: - App Bar Section

    private var appBarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App Bar")
                .font(.headline)

            Text("Add apps for quick switching from the on-screen keyboard.")
                .font(.caption)
                .foregroundColor(.secondary)

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
                    .padding(.vertical, 8)
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

    // MARK: - Extended Function Keys Section

    private var extendedFunctionKeysSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Extended Function Keys")
                .font(.headline)

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
            .toggleStyle(.switch)
        }
    }

    // MARK: - Typing Speed Section

    private var typingSpeedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Typing Speed")
                .font(.headline)

            Text("How fast text snippets are typed character by character.")
                .font(.caption)
                .foregroundColor(.secondary)

            Picker("Speed", selection: Binding(
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
    }

    // MARK: - Text Snippets Section

    private var textSnippetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Text Snippets")
                .font(.headline)

            Text("Click these to type the text into any app.")
                .font(.caption)
                .foregroundColor(.secondary)

            // Add new text snippet
            HStack {
                TextField("Enter text snippet...", text: $newTextSnippet)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addTextSnippet()
                    }

                Button("Add") {
                    addTextSnippet()
                }
                .disabled(newTextSnippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            // List of text snippets
            if textSnippets.isEmpty {
                Text("No text snippets yet")
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.vertical, 8)
            } else {
                ForEach(textSnippets) { snippet in
                    quickTextRow(snippet, isTerminalCommand: false)
                }
                .onMove { source, destination in
                    moveQuickTexts(from: source, to: destination, isTerminalCommand: false)
                }
            }
        }
    }

    // MARK: - Terminal Commands Section

    private var terminalCommandsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Terminal Commands")
                .font(.headline)

            Text("Click these to open a new terminal window and run the command.")
                .font(.caption)
                .foregroundColor(.secondary)

            // Add new terminal command
            HStack {
                TextField("Enter terminal command...", text: $newTerminalCommand)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addTerminalCommand()
                    }

                Button("Add") {
                    addTerminalCommand()
                }
                .disabled(newTerminalCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            // List of terminal commands
            if terminalCommands.isEmpty {
                Text("No terminal commands yet")
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.vertical, 8)
            } else {
                ForEach(terminalCommands) { command in
                    quickTextRow(command, isTerminalCommand: true)
                }
                .onMove { source, destination in
                    moveQuickTexts(from: source, to: destination, isTerminalCommand: true)
                }
            }
        }
    }

    // MARK: - Terminal App Section

    private var terminalAppSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Default Terminal App")
                .font(.headline)

            HStack(spacing: 12) {
                Picker("Terminal", selection: Binding(
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
                .frame(width: 150)

                if isUsingCustomTerminal {
                    TextField("App name", text: $customTerminalApp)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
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

            Text("The terminal app to use when running terminal commands.")
                .font(.caption)
                .foregroundColor(.secondary)

            // Permissions status
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    if automationPermissionGranted {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Automation Permission Granted")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }

                        Text("Terminal commands are ready to use.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            Text("Automation Permission Required")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }

                        Text("Terminal commands require Automation permission. If commands don't work, grant permission in System Settings.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button("Open Automation Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                        }
                        .buttonStyle(.link)
                    }
                }
                .padding(4)
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Quick Text Row

    @ViewBuilder
    private func quickTextRow(_ quickText: QuickText, isTerminalCommand: Bool) -> some View {
        let isEditing = isTerminalCommand ? editingCommandId == quickText.id : editingTextId == quickText.id

        HStack {
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)
                .frame(width: 20)

            if isEditing {
                TextField("", text: $editText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        saveEdit(quickText)
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
