import Foundation
import AppKit

/// HTTP methods supported for webhook/HTTP request actions
enum HTTPMethod: String, Codable, CaseIterable, Identifiable {
    case GET
    case POST
    case PUT
    case DELETE
    case PATCH

    var id: String { rawValue }
}

/// Categories for grouping system commands in the UI
enum SystemCommandCategory: String, CaseIterable, Identifiable {
    case shell = "Shell Command"
    case app = "Launch App"
    case link = "Open Link"
    case webhook = "Webhook"
    case obs = "OBS WebSocket"

    var id: String { rawValue }
}

/// Represents a system-level command that can be triggered by a button or chord mapping
enum SystemCommand: Equatable {
    // App launching
    case launchApp(bundleIdentifier: String, newWindow: Bool = false)

    // Shell command execution
    case shellCommand(command: String, inTerminal: Bool)

    // Open URL in default browser
    case openLink(url: String)

    // HTTP request / webhook
    case httpRequest(url: String, method: HTTPMethod = .POST, headers: [String: String]? = nil, body: String? = nil)

    // OBS WebSocket request (generic requestType + optional requestData JSON)
    case obsWebSocket(url: String, password: String? = nil, requestType: String, requestData: String? = nil)

    /// Human-readable display name for the UI
    var displayName: String {
        switch self {
        case .launchApp(let bundleId, let newWindow):
            let name: String
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                name = url.deletingPathExtension().lastPathComponent
            } else {
                name = bundleId
            }
            return newWindow ? "\(name) (New Window)" : name
        case .shellCommand(let command, _):
            if command.count > 30 {
                return String(command.prefix(30)) + "..."
            }
            return command
        case .openLink(let url):
            if url.count > 30 {
                return String(url.prefix(30)) + "..."
            }
            return url
        case .httpRequest(let url, let method, _, _):
            let display = "\(method.rawValue) \(url)"
            if display.count > 30 {
                return String(display.prefix(30)) + "..."
            }
            return display
        case .obsWebSocket(_, _, let requestType, _):
            let display = "OBS \(requestType)"
            if display.count > 30 {
                return String(display.prefix(30)) + "..."
            }
            return display
        }
    }

    /// Category for UI grouping
    var category: SystemCommandCategory {
        switch self {
        case .launchApp: return .app
        case .shellCommand: return .shell
        case .openLink: return .link
        case .httpRequest: return .webhook
        case .obsWebSocket: return .obs
        }
    }
}

// MARK: - Codable

extension SystemCommand: Codable {
    private enum CommandType: String, Codable {
        case launchApp, shellCommand, openLink, httpRequest, obsWebSocket
    }

    private enum CodingKeys: String, CodingKey {
        case type, bundleIdentifier, command, inTerminal, url, newWindow
        case method, headers, body, password, requestType, requestData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(CommandType.self, forKey: .type)

        switch type {
        case .launchApp:
            let bundleId = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier) ?? ""
            let newWindow = try container.decodeIfPresent(Bool.self, forKey: .newWindow) ?? false
            self = .launchApp(bundleIdentifier: bundleId, newWindow: newWindow)
        case .shellCommand:
            let command = try container.decodeIfPresent(String.self, forKey: .command) ?? ""
            let inTerminal = try container.decodeIfPresent(Bool.self, forKey: .inTerminal) ?? false
            self = .shellCommand(command: command, inTerminal: inTerminal)
        case .openLink:
            let url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
            self = .openLink(url: url)
        case .httpRequest:
            let url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
            let method = try container.decodeIfPresent(HTTPMethod.self, forKey: .method) ?? .POST
            let headers = try container.decodeIfPresent([String: String].self, forKey: .headers)
            let body = try container.decodeIfPresent(String.self, forKey: .body)
            self = .httpRequest(url: url, method: method, headers: headers, body: body)
        case .obsWebSocket:
            let url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
            let storedPassword = try container.decodeIfPresent(String.self, forKey: .password)
            // Resolve password: if it's a Keychain reference (UUID), fetch from Keychain.
            // If plaintext (legacy), use as-is — it will migrate to Keychain on next save.
            let password: String?
            if let stored = storedPassword, KeychainService.isKeychainReference(stored) {
                password = KeychainService.retrievePassword(key: stored)
            } else {
                password = storedPassword
            }
            let requestType = try container.decodeIfPresent(String.self, forKey: .requestType) ?? ""
            let requestData = try container.decodeIfPresent(String.self, forKey: .requestData)
            self = .obsWebSocket(url: url, password: password, requestType: requestType, requestData: requestData)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .launchApp(let bundleId, let newWindow):
            try container.encode(CommandType.launchApp, forKey: .type)
            try container.encode(bundleId, forKey: .bundleIdentifier)
            try container.encode(newWindow, forKey: .newWindow)
        case .shellCommand(let command, let inTerminal):
            try container.encode(CommandType.shellCommand, forKey: .type)
            try container.encode(command, forKey: .command)
            try container.encode(inTerminal, forKey: .inTerminal)
        case .openLink(let url):
            try container.encode(CommandType.openLink, forKey: .type)
            try container.encode(url, forKey: .url)
        case .httpRequest(let url, let method, let headers, let body):
            try container.encode(CommandType.httpRequest, forKey: .type)
            try container.encode(url, forKey: .url)
            try container.encode(method, forKey: .method)
            try container.encodeIfPresent(headers, forKey: .headers)
            try container.encodeIfPresent(body, forKey: .body)
        case .obsWebSocket(let url, let password, let requestType, let requestData):
            try container.encode(CommandType.obsWebSocket, forKey: .type)
            try container.encode(url, forKey: .url)
            // Store password in Keychain, write UUID reference to JSON
            if let password = password, !password.isEmpty {
                let key = UUID().uuidString
                if KeychainService.storePassword(password, key: key) != nil {
                    try container.encode(key, forKey: .password)
                } else {
                    // Keychain store failed — omit password from JSON to avoid plaintext leak
                    NSLog("[SystemCommand] Failed to store OBS password in Keychain")
                }
            }
            try container.encode(requestType, forKey: .requestType)
            try container.encodeIfPresent(requestData, forKey: .requestData)
        }
    }
}
