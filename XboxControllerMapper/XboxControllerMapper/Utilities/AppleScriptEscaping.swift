import Foundation

/// Centralized AppleScript string escaping to prevent injection attacks.
/// Used by SystemCommandExecutor and OnScreenKeyboardManager when constructing
/// AppleScript strings from user-provided config values.
enum AppleScriptEscaping {
    /// Escapes a string for safe interpolation inside AppleScript double-quoted strings.
    /// Handles: backslash, double quote, newline, carriage return, tab.
    static func escapeForString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    /// Validates an application name for use in `tell application "Name"`.
    /// Rejects names containing characters that could break out of the AppleScript string
    /// or execute unintended commands.
    /// Returns the sanitized name, or nil if the name is invalid.
    static func sanitizeAppName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Reject names with characters that could break AppleScript string context
        let forbidden: [Character] = ["\"", "\\", "\n", "\r"]
        for ch in forbidden {
            if trimmed.contains(ch) {
                NSLog("[AppleScriptEscaping] Rejected app name containing forbidden character: %@", name)
                return nil
            }
        }

        // Reject names containing control characters (U+0000..U+001F, U+007F)
        if trimmed.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) {
            NSLog("[AppleScriptEscaping] Rejected app name containing control character: %@", name)
            return nil
        }

        return trimmed
    }
}
