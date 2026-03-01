import Foundation
import CoreGraphics

/// Holds the editable state for a single action mapping variant (primary, long hold, or double tap).
/// Replaces the triplicated @State properties in ButtonMappingSheet.
struct MappingEditorState {
    // MARK: - Action type
    var mappingType: MappingType = .singleKey

    // MARK: - Key press fields
    var keyCode: CGKeyCode?
    var modifiers = ModifierFlags()

    // MARK: - Macro / Script
    var selectedMacroId: UUID?
    var selectedScriptId: UUID?

    // MARK: - System command
    var systemCommandCategory: SystemCommandCategory = .shell
    var appBundleIdentifier: String = ""
    var appNewWindow: Bool = false
    var shellCommandText: String = ""
    var shellRunInTerminal: Bool = true
    var linkURL: String = ""

    // Webhook (primary-only, but kept here for uniformity)
    var webhookURL: String = ""
    var webhookMethod: HTTPMethod = .POST
    var webhookBody: String = ""
    var webhookHeaders: [String: String] = [:]
    var newWebhookHeaderKey: String = ""
    var newWebhookHeaderValue: String = ""

    // OBS WebSocket (primary-only, but kept here for uniformity)
    var obsWebSocketURL: String = "ws://127.0.0.1:4455"
    var obsWebSocketPassword: String = ""
    var obsRequestType: String = ""
    var obsRequestData: String = ""

    // MARK: - Hint
    var hint: String = ""

    // MARK: - Haptic feedback
    var hapticStyle: HapticStyle?

    // MARK: - UI state
    var showingKeyboard: Bool = false
    var showingAppPicker: Bool = false
    var showingBookmarkPicker: Bool = false
    var showingMacroCreation: Bool = false
    var showingScriptCreation: Bool = false

    /// The mapping type picker used in the original code
    enum MappingType: Int {
        case singleKey = 0
        case macro = 1
        case systemCommand = 2
        case script = 3
    }

    // MARK: - Display helpers

    var mappingDisplayString: String {
        var parts: [String] = []
        if modifiers.command { parts.append("\u{2318}") }
        if modifiers.option { parts.append("\u{2325}") }
        if modifiers.shift { parts.append("\u{21E7}") }
        if modifiers.control { parts.append("\u{2303}") }
        if let keyCode = keyCode {
            parts.append(KeyCodeMapping.displayName(for: keyCode))
        }
        return parts.isEmpty ? "None" : parts.joined(separator: " + ")
    }

    // MARK: - System command builders

    /// Builds a SystemCommand from the current state, or nil if invalid.
    /// For webhook/OBS, only valid when called on the primary variant.
    func buildSystemCommand() -> SystemCommand? {
        switch systemCommandCategory {
        case .shell:
            guard !shellCommandText.isEmpty else { return nil }
            return .shellCommand(command: shellCommandText, inTerminal: shellRunInTerminal)
        case .app:
            guard !appBundleIdentifier.isEmpty else { return nil }
            return .launchApp(bundleIdentifier: appBundleIdentifier, newWindow: appNewWindow)
        case .link:
            guard !linkURL.isEmpty else { return nil }
            return .openLink(url: linkURL)
        case .webhook:
            guard !webhookURL.isEmpty else { return nil }
            let headers = webhookHeaders.isEmpty ? nil : webhookHeaders
            let body = webhookBody.isEmpty ? nil : webhookBody
            return .httpRequest(url: webhookURL, method: webhookMethod, headers: headers, body: body)
        case .obs:
            guard !obsWebSocketURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            guard !obsRequestType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let password = obsWebSocketPassword.trimmingCharacters(in: .whitespacesAndNewlines)
            let requestData = obsRequestData.trimmingCharacters(in: .whitespacesAndNewlines)
            return .obsWebSocket(
                url: obsWebSocketURL,
                password: password.isEmpty ? nil : password,
                requestType: obsRequestType,
                requestData: requestData.isEmpty ? nil : requestData
            )
        }
    }

    // MARK: - Load from existing data

    /// Populates state from a system command
    mutating func loadSystemCommand(_ command: SystemCommand) {
        systemCommandCategory = command.category
        switch command {
        case .launchApp(let bundleId, let newWindow):
            appBundleIdentifier = bundleId
            appNewWindow = newWindow
        case .shellCommand(let cmd, let terminal):
            shellCommandText = cmd
            shellRunInTerminal = terminal
        case .openLink(let url):
            linkURL = url
        case .httpRequest(let url, let method, let headers, let body):
            webhookURL = url
            webhookMethod = method
            webhookHeaders = headers ?? [:]
            webhookBody = body ?? ""
        case .obsWebSocket(let url, let password, let requestType, let requestData):
            obsWebSocketURL = url
            obsWebSocketPassword = password ?? ""
            self.obsRequestType = requestType
            self.obsRequestData = requestData ?? ""
        }
    }
}
