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

    private var textSnippets: [QuickText] {
        profileManager.onScreenKeyboardSettings.quickTexts.filter { !$0.isTerminalCommand }
    }

    private var terminalCommands: [QuickText] {
        profileManager.onScreenKeyboardSettings.quickTexts.filter { $0.isTerminalCommand }
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

                // Terminal Commands Section
                terminalCommandsSection

                Divider()

                // Typing Speed Settings
                typingSpeedSection

                Divider()

                // Terminal App Settings
                terminalAppSection
            }
            .padding(24)
        }
        .onAppear {
            requestAutomationPermissionIfNeeded()
        }
    }

    // MARK: - Automation Permission

    private func requestAutomationPermissionIfNeeded() {
        // Only request once per app session
        guard !hasRequestedAutomation else { return }
        hasRequestedAutomation = true

        // Run a simple AppleScript that targets Terminal to trigger the permission prompt
        // This is a no-op script that just checks if Terminal is running
        let script = """
        tell application "System Events"
            return name of first process whose frontmost is true
        end tell
        """

        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: script) {
                scriptObject.executeAndReturnError(&error)
                // We don't care about the result - we just want to trigger the permission prompt
            }
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

            Picker("Terminal", selection: Binding(
                get: { profileManager.onScreenKeyboardSettings.defaultTerminalApp },
                set: { profileManager.setDefaultTerminalApp($0) }
            )) {
                ForEach(OnScreenKeyboardSettings.terminalOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 200)

            Text("The terminal app to use when running terminal commands.")
                .font(.caption)
                .foregroundColor(.secondary)

            // Permissions note
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
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
