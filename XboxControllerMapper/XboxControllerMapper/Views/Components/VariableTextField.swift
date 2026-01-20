import SwiftUI
import AppKit
import Carbon.HIToolbox

/// A text field that preserves trailing spaces and supports keyboard navigation for autocomplete suggestions
struct VariableTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var showingSuggestions: Bool
    var suggestionCount: Int
    @Binding var selectedSuggestionIndex: Int
    var onSelectSuggestion: () -> Void
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = placeholder
        textField.delegate = context.coordinator
        textField.bezelStyle = .roundedBezel
        textField.focusRingType = .exterior
        textField.font = .systemFont(ofSize: NSFont.systemFontSize)
        textField.lineBreakMode = .byClipping
        textField.cell?.truncatesLastVisibleLine = false
        textField.cell?.wraps = false
        textField.cell?.isScrollable = true
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        // Only update text if it differs to avoid cursor jumping
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        context.coordinator.showingSuggestions = showingSuggestions
        context.coordinator.suggestionCount = suggestionCount
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: VariableTextField
        var showingSuggestions: Bool = false
        var suggestionCount: Int = 0

        init(_ parent: VariableTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if showingSuggestions && suggestionCount > 0 {
                // Handle arrow keys for navigation
                if commandSelector == #selector(NSResponder.moveDown(_:)) {
                    // Move selection down
                    if parent.selectedSuggestionIndex < suggestionCount - 1 {
                        parent.selectedSuggestionIndex += 1
                    } else {
                        // Wrap to first item
                        parent.selectedSuggestionIndex = 0
                    }
                    return true
                }

                if commandSelector == #selector(NSResponder.moveUp(_:)) {
                    // Move selection up
                    if parent.selectedSuggestionIndex > 0 {
                        parent.selectedSuggestionIndex -= 1
                    } else {
                        // Wrap to last item
                        parent.selectedSuggestionIndex = suggestionCount - 1
                    }
                    return true
                }

                // Handle Enter/Return to select suggestion
                if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                    if parent.selectedSuggestionIndex >= 0 {
                        parent.onSelectSuggestion()
                        return true
                    }
                }
            }

            // Handle Enter/Return when no suggestions shown - submit
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }

            return false
        }
    }
}

#Preview {
    VStack {
        VariableTextField(
            text: .constant("Test with trailing spaces   "),
            placeholder: "Enter text...",
            showingSuggestions: false,
            suggestionCount: 0,
            selectedSuggestionIndex: .constant(-1),
            onSelectSuggestion: {},
            onSubmit: {}
        )
        .frame(width: 300)
    }
    .padding()
}
