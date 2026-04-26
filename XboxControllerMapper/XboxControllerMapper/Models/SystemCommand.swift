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

/// Configuration for how HTTP response should be handled
struct HTTPResponseHandling: Codable, Equatable {
    /// Whether to show a macOS notification with the result
    var showNotification: Bool = false

    /// Maximum number of retries on failure (0 = no retries)
    var maxRetries: Int = 0

    /// Base delay in seconds for exponential backoff between retries
    var retryDelay: Double = 1.0

    /// Optional shell command to run on success (2xx response)
    var onSuccessCommand: String?

    /// Optional shell command to run on error (non-2xx or network error)
    var onErrorCommand: String?

    /// Request timeout in seconds
    var timeout: TimeInterval = Self.defaultTimeout

    /// Default timeout for HTTP requests (seconds)
    static let defaultTimeout: TimeInterval = 10

    /// Default instance with no response handling configured
    static let `default` = HTTPResponseHandling()

    /// Whether any response handling is configured beyond defaults
    var hasConfiguration: Bool {
        showNotification || maxRetries > 0 || onSuccessCommand != nil || onErrorCommand != nil || timeout != Self.defaultTimeout
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case showNotification, maxRetries, retryDelay
        case onSuccessCommand, onErrorCommand, timeout
    }

    init(
        showNotification: Bool = false,
        maxRetries: Int = 0,
        retryDelay: Double = 1.0,
        onSuccessCommand: String? = nil,
        onErrorCommand: String? = nil,
        timeout: TimeInterval = Self.defaultTimeout
    ) {
        self.showNotification = showNotification
        self.maxRetries = maxRetries
        self.retryDelay = retryDelay
        self.onSuccessCommand = onSuccessCommand
        self.onErrorCommand = onErrorCommand
        self.timeout = timeout
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showNotification = try container.decodeIfPresent(Bool.self, forKey: .showNotification) ?? false
        maxRetries = try container.decodeIfPresent(Int.self, forKey: .maxRetries) ?? 0
        retryDelay = try container.decodeIfPresent(Double.self, forKey: .retryDelay) ?? 1.0
        onSuccessCommand = try container.decodeIfPresent(String.self, forKey: .onSuccessCommand)
        onErrorCommand = try container.decodeIfPresent(String.self, forKey: .onErrorCommand)
        timeout = try container.decodeIfPresent(TimeInterval.self, forKey: .timeout) ?? Self.defaultTimeout
    }
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
    case httpRequest(url: String, method: HTTPMethod = .POST, headers: [String: String]? = nil, body: String? = nil, responseHandling: HTTPResponseHandling? = nil)

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
        case .httpRequest(let url, let method, _, _, _):
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
        case responseHandling
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
            let responseHandling = try container.decodeIfPresent(HTTPResponseHandling.self, forKey: .responseHandling)
            self = .httpRequest(url: url, method: method, headers: headers, body: body, responseHandling: responseHandling)
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
        case .httpRequest(let url, let method, let headers, let body, let responseHandling):
            try container.encode(CommandType.httpRequest, forKey: .type)
            try container.encode(url, forKey: .url)
            try container.encode(method, forKey: .method)
            try container.encodeIfPresent(headers, forKey: .headers)
            try container.encodeIfPresent(body, forKey: .body)
            // Only persist responseHandling if it has non-default config
            if let rh = responseHandling, rh.hasConfiguration {
                try container.encode(rh, forKey: .responseHandling)
            }
        case .obsWebSocket(let url, let password, let requestType, let requestData):
            try container.encode(CommandType.obsWebSocket, forKey: .type)
            try container.encode(url, forKey: .url)
            // Store password in Keychain, write stable key reference to JSON
            if let password = password, !password.isEmpty {
                let key = KeychainService.stableKey(for: "obs-websocket:\(url)")
                if KeychainService.storePassword(password, key: key) != nil {
                    try container.encode(key, forKey: .password)
                } else {
                    // Keychain store failed — fall back to plaintext to avoid silent data loss
                    NSLog("[SystemCommand] Keychain store failed, falling back to plaintext for OBS password")
                    try container.encode(password, forKey: .password)
                }
            }
            try container.encode(requestType, forKey: .requestType)
            try container.encodeIfPresent(requestData, forKey: .requestData)
        }
    }
}
