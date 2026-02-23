import SwiftUI

/// Shared variable autocomplete helpers used by text snippets and terminal commands sections.
enum OSKVariableAutocomplete {

    /// Finds the variable prefix being typed (text after the last unclosed `{`)
    static func variablePrefix(in text: String) -> String? {
        guard let lastBrace = text.lastIndex(of: "{") else { return nil }
        let afterBrace = text[text.index(after: lastBrace)...]
        if afterBrace.contains("}") { return nil }
        return String(afterBrace)
    }

    /// Returns filtered variables matching the given prefix
    static func filteredVariables(for prefix: String) -> [(name: String, description: String, example: String)] {
        if prefix.isEmpty {
            return VariableExpander.availableVariables
        }
        return VariableExpander.availableVariables.filter {
            $0.name.lowercased().hasPrefix(prefix.lowercased())
        }
    }

    /// Inserts a variable into text, replacing any partial variable being typed
    static func insertVariable(_ variableName: String, into text: inout String) {
        guard let lastBrace = text.lastIndex(of: "{") else { return }
        let beforeBrace = String(text[..<lastBrace])
        text = beforeBrace + "{\(variableName)}"
    }

    /// Checks if suggestions should be shown for the given text
    static func shouldShowSuggestions(for text: String) -> Bool {
        guard let prefix = variablePrefix(in: text) else { return false }
        return !filteredVariables(for: prefix).isEmpty
    }

    /// Returns the count of filtered variables for the given text
    static func suggestionCount(for text: String) -> Int {
        guard let prefix = variablePrefix(in: text) else { return 0 }
        return filteredVariables(for: prefix).count
    }
}

/// Variable hint section shown above text snippet and terminal command input fields.
struct OSKVariableHintView: View {
    @Binding var isPresented: Bool

    var body: some View {
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
                isPresented.toggle()
            } label: {
                Text("View all")
                    .font(.caption)
            }
            .buttonStyle(.link)
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
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
}

/// Variable suggestion dropdown view, shared between text snippet and terminal command fields.
struct OSKVariableSuggestionsView: View {
    @Binding var text: String
    @Binding var showSuggestions: Bool
    @Binding var selectedIndex: Int

    var body: some View {
        if let prefix = OSKVariableAutocomplete.variablePrefix(in: text) {
            let matches = OSKVariableAutocomplete.filteredVariables(for: prefix)
            if !matches.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(matches.enumerated()), id: \.element.name) { index, variable in
                        let isSelected = index == selectedIndex
                        Button {
                            OSKVariableAutocomplete.insertVariable(variable.name, into: &text)
                            showSuggestions = false
                            selectedIndex = 0
                        } label: {
                            HStack {
                                Text("{\(variable.name)}")
                                    .font(.system(.caption, design: .monospaced))
                                    .fontWeight(.medium)

                                Spacer()

                                Text(variable.description)
                                    .font(.caption2)
                                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                        .foregroundColor(isSelected ? .white : .primary)
                    }
                }
                .background(Color(nsColor: .windowBackgroundColor))
                .cornerRadius(6)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                .frame(maxWidth: 300)
            }
        }
    }
}
