import SwiftUI

/// Text snippets management section for the on-screen keyboard settings.
struct TextSnippetsSection: View {
    @EnvironmentObject var profileManager: ProfileManager

    // Input state
    @State private var newTextSnippet = ""

    // Editing state
    @State private var editingTextId: UUID?
    @State private var editText = ""

    // Variable help popover
    @State private var showingVariableHelp = false

    // Variable autocomplete state
    @State private var showSnippetSuggestions = false
    @State private var showEditSuggestions = false
    @State private var snippetSuggestionIndex = 0
    @State private var editSuggestionIndex = 0

    private var textSnippets: [QuickText] {
        (profileManager.activeProfile?.onScreenKeyboardSettings.quickTexts ?? []).filter { !$0.isTerminalCommand }
    }

    private var terminalCommands: [QuickText] {
        (profileManager.activeProfile?.onScreenKeyboardSettings.quickTexts ?? []).filter { $0.isTerminalCommand }
    }

    private var snippetSuggestionCount: Int {
        OSKVariableAutocomplete.suggestionCount(for: newTextSnippet)
    }

    private var editSuggestionCount: Int {
        OSKVariableAutocomplete.suggestionCount(for: editText)
    }

    var body: some View {
        Section {
            // Variable hint
            OSKVariableHintView(isPresented: $showingVariableHelp)

            // Add new text snippet with autocomplete
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    VariableTextField(
                        text: $newTextSnippet,
                        placeholder: "Enter text snippet...",
                        showingSuggestions: showSnippetSuggestions,
                        suggestionCount: snippetSuggestionCount,
                        selectedSuggestionIndex: $snippetSuggestionIndex,
                        onSelectSuggestion: {
                            selectSnippetSuggestion()
                        },
                        onSubmit: {
                            if !showSnippetSuggestions {
                                addTextSnippet()
                            }
                        }
                    )
                    .onChange(of: newTextSnippet) { _, newValue in
                        let shouldShow = OSKVariableAutocomplete.shouldShowSuggestions(for: newValue)
                        if shouldShow && !showSnippetSuggestions {
                            snippetSuggestionIndex = 0
                        }
                        showSnippetSuggestions = shouldShow
                    }

                    Button("Add") {
                        addTextSnippet()
                    }
                    .disabled(newTextSnippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if showSnippetSuggestions {
                    OSKVariableSuggestionsView(
                        text: $newTextSnippet,
                        showSuggestions: $showSnippetSuggestions,
                        selectedIndex: $snippetSuggestionIndex
                    )
                }
            }

            // List of text snippets
            if textSnippets.isEmpty {
                Text("No text snippets yet")
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                List {
                    ForEach(textSnippets) { snippet in
                        quickTextRow(snippet)
                    }
                    .onMove { source, destination in
                        moveQuickTexts(from: source, to: destination)
                    }
                }
                .listStyle(.plain)
                .frame(height: CGFloat(textSnippets.count) * 36)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
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

    // MARK: - Quick Text Row

    @ViewBuilder
    private func quickTextRow(_ quickText: QuickText) -> some View {
        QuickTextRowView(
            quickText: quickText,
            isTerminalCommand: false,
            isEditing: editingTextId == quickText.id,
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

    private func addTextSnippet() {
        let trimmed = newTextSnippet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let snippet = QuickText(text: trimmed, isTerminalCommand: false)
        profileManager.addQuickText(snippet)
        newTextSnippet = ""
    }

    private func startEdit(_ quickText: QuickText) {
        editText = quickText.text
        editSuggestionIndex = 0
        showEditSuggestions = false
        editingTextId = quickText.id
    }

    private func saveEdit(_ quickText: QuickText) {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var updated = quickText
        updated.text = trimmed
        profileManager.updateQuickText(updated)

        editingTextId = nil
        editText = ""
    }

    private func cancelEdit() {
        editingTextId = nil
        editText = ""
    }

    private func moveQuickTexts(from source: IndexSet, to destination: Int) {
        var items = textSnippets
        items.move(fromOffsets: source, toOffset: destination)

        var settings = profileManager.onScreenKeyboardSettings
        settings.quickTexts = items + terminalCommands
        profileManager.updateOnScreenKeyboardSettings(settings)
    }

    // MARK: - Variable Autocomplete

    private func selectSnippetSuggestion() {
        guard let prefix = OSKVariableAutocomplete.variablePrefix(in: newTextSnippet) else { return }
        let matches = OSKVariableAutocomplete.filteredVariables(for: prefix)
        guard snippetSuggestionIndex < matches.count else { return }
        OSKVariableAutocomplete.insertVariable(matches[snippetSuggestionIndex].name, into: &newTextSnippet)
        showSnippetSuggestions = false
        snippetSuggestionIndex = 0
    }

    private func selectEditSuggestion() {
        guard let prefix = OSKVariableAutocomplete.variablePrefix(in: editText) else { return }
        let matches = OSKVariableAutocomplete.filteredVariables(for: prefix)
        guard editSuggestionIndex < matches.count else { return }
        OSKVariableAutocomplete.insertVariable(matches[editSuggestionIndex].name, into: &editText)
        showEditSuggestions = false
        editSuggestionIndex = 0
    }
}
