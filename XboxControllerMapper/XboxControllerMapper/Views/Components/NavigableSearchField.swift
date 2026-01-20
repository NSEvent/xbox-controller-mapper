import SwiftUI
import AppKit

/// A search field that supports keyboard navigation for a list below it
struct NavigableSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var itemCount: Int
    @Binding var selectedIndex: Int
    var onSelect: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = placeholder
        textField.delegate = context.coordinator
        textField.bezelStyle = .roundedBezel
        textField.focusRingType = .exterior
        textField.font = .systemFont(ofSize: NSFont.systemFontSize)
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        context.coordinator.itemCount = itemCount
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NavigableSearchField
        var itemCount: Int = 0

        init(_ parent: NavigableSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            parent.text = textField.stringValue
            // Reset selection to first item when search changes
            parent.selectedIndex = 0
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if itemCount > 0 {
                // Handle arrow keys for navigation
                if commandSelector == #selector(NSResponder.moveDown(_:)) {
                    if parent.selectedIndex < itemCount - 1 {
                        parent.selectedIndex += 1
                    } else {
                        parent.selectedIndex = 0
                    }
                    return true
                }

                if commandSelector == #selector(NSResponder.moveUp(_:)) {
                    if parent.selectedIndex > 0 {
                        parent.selectedIndex -= 1
                    } else {
                        parent.selectedIndex = itemCount - 1
                    }
                    return true
                }

                // Handle Enter/Return to select
                if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                    parent.onSelect()
                    return true
                }
            }

            return false
        }
    }
}
