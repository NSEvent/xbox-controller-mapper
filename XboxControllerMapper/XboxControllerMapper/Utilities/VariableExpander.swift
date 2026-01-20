import Foundation
import AppKit

/// Expands variables in text using {variable} syntax
enum VariableExpander {

    // MARK: - Variable Definitions

    /// All supported variables with their descriptions and examples
    static let availableVariables: [(name: String, description: String, example: String)] = [
        // Time/Date
        ("time.iso", "ISO 8601 timestamp", "2024-01-15T14:30:45Z"),
        ("date", "Current date", "2024-01-15"),
        ("time", "Current time", "14:30:45"),
        ("datetime", "Date and time", "2024-01-15 14:30:45"),
        ("unix", "Unix timestamp", "1705329045"),

        // System
        ("clipboard", "Clipboard contents", "(clipboard text)"),
        ("selection", "Selected text", "(selected text)"),
        ("hostname", "Computer name", "My-Mac"),
        ("username", "Current user", NSUserName()),

        // Utility
        ("uuid", "Random UUID", "550e8400-e29b-41d4-..."),
        ("random", "Random number (0-9999)", "4271")
    ]

    // MARK: - Expansion

    /// Expands all variables in the given text
    /// - Parameter text: The text containing {variable} placeholders
    /// - Returns: The text with all variables expanded
    static func expand(_ text: String) -> String {
        var result = text

        // Use regex to find all {variable} patterns
        let pattern = #"\{([a-z._]+)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }

        // Find all matches (process in reverse to preserve indices)
        let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))

        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let varNameRange = Range(match.range(at: 1), in: result) else {
                continue
            }

            let variableName = String(result[varNameRange])

            if let value = resolveVariable(variableName) {
                result.replaceSubrange(fullRange, with: value)
            }
            // If variable cannot be resolved, leave it unchanged
        }

        return result
    }

    // MARK: - Variable Resolution

    /// Resolves a single variable name to its value
    private static func resolveVariable(_ name: String) -> String? {
        switch name {
        // Time/Date variables
        case "time.iso":
            return ISO8601DateFormatter().string(from: Date())

        case "date":
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: Date())

        case "time":
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            return formatter.string(from: Date())

        case "datetime":
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return formatter.string(from: Date())

        case "unix":
            return String(Int(Date().timeIntervalSince1970))

        // System variables
        case "clipboard":
            return NSPasteboard.general.string(forType: .string) ?? ""

        case "selection":
            return getSelectedText() ?? ""

        case "hostname":
            return Host.current().localizedName ?? ProcessInfo.processInfo.hostName

        case "username":
            return NSUserName()

        // Utility variables
        case "uuid":
            return UUID().uuidString

        case "random":
            return String(Int.random(in: 0...9999))

        default:
            return nil
        }
    }

    // MARK: - Selected Text (Accessibility)

    /// Gets the currently selected text using Accessibility APIs
    private static func getSelectedText() -> String? {
        // Get the frontmost application
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let pid = app.processIdentifier

        // Create AXUIElement for the application
        let appElement = AXUIElementCreateApplication(pid)

        // Get the focused element
        var focusedElement: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard focusResult == .success,
              let focused = focusedElement else {
            return nil
        }

        // Try to get selected text
        var selectedText: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(
            focused as! AXUIElement,
            kAXSelectedTextAttribute as CFString,
            &selectedText
        )

        guard textResult == .success,
              let text = selectedText as? String,
              !text.isEmpty else {
            return nil
        }

        return text
    }
}
