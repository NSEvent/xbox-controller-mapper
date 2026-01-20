import Foundation
import AppKit

/// Expands variables in text using {variable} syntax
enum VariableExpander {

    // MARK: - Variable Definitions

    /// All supported variables with their descriptions and examples
    static let availableVariables: [(name: String, description: String, example: String)] = [
        // Date formats
        ("date", "ISO date (YYYY-MM-DD)", "2024-01-15"),
        ("date.us", "US date (MM/DD/YYYY)", "01/15/2024"),
        ("date.eu", "European date (DD/MM/YYYY)", "15/01/2024"),
        ("date.long", "Long date", "January 15, 2024"),
        ("date.short", "Short date", "Jan 15, 2024"),
        ("date.year", "Year", "2024"),
        ("date.month", "Month (01-12)", "01"),
        ("date.month.name", "Month name", "January"),
        ("date.day", "Day (01-31)", "15"),
        ("date.weekday", "Day of week", "Monday"),

        // Time formats
        ("time", "24-hour time", "14:30:45"),
        ("time.12", "12-hour time", "2:30:45 PM"),
        ("time.short", "Short time (no seconds)", "14:30"),
        ("time.hour", "Hour (00-23)", "14"),
        ("time.minute", "Minute (00-59)", "30"),
        ("time.second", "Second (00-59)", "45"),

        // Combined date/time
        ("datetime", "Date and time", "2024-01-15 14:30:45"),
        ("datetime.long", "Long date and time", "January 15, 2024 at 2:30 PM"),
        ("time.iso", "ISO 8601 timestamp", "2024-01-15T14:30:45Z"),
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
        let now = Date()
        let formatter = DateFormatter()

        switch name {
        // Date formats
        case "date":
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: now)

        case "date.us":
            formatter.dateFormat = "MM/dd/yyyy"
            return formatter.string(from: now)

        case "date.eu":
            formatter.dateFormat = "dd/MM/yyyy"
            return formatter.string(from: now)

        case "date.long":
            formatter.dateStyle = .long
            return formatter.string(from: now)

        case "date.short":
            formatter.dateFormat = "MMM d, yyyy"
            return formatter.string(from: now)

        case "date.year":
            formatter.dateFormat = "yyyy"
            return formatter.string(from: now)

        case "date.month":
            formatter.dateFormat = "MM"
            return formatter.string(from: now)

        case "date.month.name":
            formatter.dateFormat = "MMMM"
            return formatter.string(from: now)

        case "date.day":
            formatter.dateFormat = "dd"
            return formatter.string(from: now)

        case "date.weekday":
            formatter.dateFormat = "EEEE"
            return formatter.string(from: now)

        // Time formats
        case "time":
            formatter.dateFormat = "HH:mm:ss"
            return formatter.string(from: now)

        case "time.12":
            formatter.dateFormat = "h:mm:ss a"
            return formatter.string(from: now)

        case "time.short":
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: now)

        case "time.hour":
            formatter.dateFormat = "HH"
            return formatter.string(from: now)

        case "time.minute":
            formatter.dateFormat = "mm"
            return formatter.string(from: now)

        case "time.second":
            formatter.dateFormat = "ss"
            return formatter.string(from: now)

        // Combined date/time
        case "datetime":
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return formatter.string(from: now)

        case "datetime.long":
            formatter.dateStyle = .long
            formatter.timeStyle = .short
            return formatter.string(from: now)

        case "time.iso":
            return ISO8601DateFormatter().string(from: now)

        case "unix":
            return String(Int(now.timeIntervalSince1970))

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
