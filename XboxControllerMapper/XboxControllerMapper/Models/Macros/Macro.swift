import Foundation
import AppKit

/// A reusable sequence of input actions
struct Macro: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var steps: [MacroStep]
    
    init(id: UUID = UUID(), name: String, steps: [MacroStep] = []) {
        self.id = id
        self.name = name
        self.steps = steps
    }
}

/// A single step in a macro sequence
enum MacroStep: Codable, Equatable {
    /// Press and release a key combination
    case press(KeyMapping)

    /// Hold a key combination (must be paired with release or used for duration)
    case hold(KeyMapping, duration: TimeInterval)

    /// Wait for a specified duration
    case delay(TimeInterval)

    /// Type a string of text with specified speed (CPM). 0 = Instant Paste. pressEnter sends Return key after.
    case typeText(String, speed: Int, pressEnter: Bool = false)

    /// Open an application, optionally in a new window
    case openApp(bundleIdentifier: String, newWindow: Bool)

    /// Open a URL in the default browser
    case openLink(url: String)

    /// Run a shell command
    case shellCommand(command: String, inTerminal: Bool)

    /// Fire an HTTP webhook request
    case webhook(url: String, method: HTTPMethod, headers: [String: String]?, body: String?)

    /// Send an OBS WebSocket request
    case obsWebSocket(url: String, password: String?, requestType: String, requestData: String?)

    // Custom decoding/encoding to handle enum associated values
    private enum CodingKeys: String, CodingKey {
        case type, payload
    }

    private enum StepType: String, Codable {
        case press, hold, delay, typeText, openApp, openLink
        case shellCommand, webhook, obsWebSocket
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(StepType.self, forKey: .type)
        
        switch type {
        case .press:
            let mapping = try container.decode(KeyMapping.self, forKey: .payload)
            self = .press(mapping)
        case .hold:
            let data = try container.decode(HoldPayload.self, forKey: .payload)
            self = .hold(data.mapping, duration: data.duration)
        case .delay:
            let duration = try container.decode(TimeInterval.self, forKey: .payload)
            self = .delay(duration)
        case .typeText:
            if let data = try? container.decode(TypeTextPayload.self, forKey: .payload) {
                self = .typeText(data.text, speed: data.speed, pressEnter: data.pressEnter)
            } else {
                // Fallback for legacy string-only payload
                let text = try container.decode(String.self, forKey: .payload)
                self = .typeText(text, speed: 0, pressEnter: false) // Default to paste/instant
            }
        case .openApp:
            let data = try container.decode(OpenAppPayload.self, forKey: .payload)
            self = .openApp(bundleIdentifier: data.bundleIdentifier, newWindow: data.newWindow)
        case .openLink:
            let url = try container.decode(String.self, forKey: .payload)
            self = .openLink(url: url)
        case .shellCommand:
            let data = try container.decode(ShellCommandPayload.self, forKey: .payload)
            self = .shellCommand(command: data.command, inTerminal: data.inTerminal)
        case .webhook:
            let data = try container.decode(WebhookPayload.self, forKey: .payload)
            self = .webhook(url: data.url, method: data.method, headers: data.headers, body: data.body)
        case .obsWebSocket:
            let data = try container.decode(OBSWebSocketPayload.self, forKey: .payload)
            self = .obsWebSocket(url: data.url, password: data.password, requestType: data.requestType, requestData: data.requestData)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .press(let mapping):
            try container.encode(StepType.press, forKey: .type)
            try container.encode(mapping, forKey: .payload)
        case .hold(let mapping, let duration):
            try container.encode(StepType.hold, forKey: .type)
            try container.encode(HoldPayload(mapping: mapping, duration: duration), forKey: .payload)
        case .delay(let duration):
            try container.encode(StepType.delay, forKey: .type)
            try container.encode(duration, forKey: .payload)
        case .typeText(let text, let speed, let pressEnter):
            try container.encode(StepType.typeText, forKey: .type)
            try container.encode(TypeTextPayload(text: text, speed: speed, pressEnter: pressEnter), forKey: .payload)
        case .openApp(let bundleIdentifier, let newWindow):
            try container.encode(StepType.openApp, forKey: .type)
            try container.encode(OpenAppPayload(bundleIdentifier: bundleIdentifier, newWindow: newWindow), forKey: .payload)
        case .openLink(let url):
            try container.encode(StepType.openLink, forKey: .type)
            try container.encode(url, forKey: .payload)
        case .shellCommand(let command, let inTerminal):
            try container.encode(StepType.shellCommand, forKey: .type)
            try container.encode(ShellCommandPayload(command: command, inTerminal: inTerminal), forKey: .payload)
        case .webhook(let url, let method, let headers, let body):
            try container.encode(StepType.webhook, forKey: .type)
            try container.encode(WebhookPayload(url: url, method: method, headers: headers, body: body), forKey: .payload)
        case .obsWebSocket(let url, let password, let requestType, let requestData):
            try container.encode(StepType.obsWebSocket, forKey: .type)
            try container.encode(OBSWebSocketPayload(url: url, password: password, requestType: requestType, requestData: requestData), forKey: .payload)
        }
    }
    
    private struct HoldPayload: Codable {
        let mapping: KeyMapping
        let duration: TimeInterval
    }
    
    private struct TypeTextPayload: Codable {
        let text: String
        let speed: Int
        let pressEnter: Bool

        init(text: String, speed: Int, pressEnter: Bool) {
            self.text = text
            self.speed = speed
            self.pressEnter = pressEnter
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            text = try container.decode(String.self, forKey: .text)
            speed = try container.decode(Int.self, forKey: .speed)
            pressEnter = try container.decodeIfPresent(Bool.self, forKey: .pressEnter) ?? false
        }
    }

    private struct OpenAppPayload: Codable {
        let bundleIdentifier: String
        let newWindow: Bool
    }

    private struct ShellCommandPayload: Codable {
        let command: String
        let inTerminal: Bool

        init(command: String, inTerminal: Bool) {
            self.command = command
            self.inTerminal = inTerminal
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            command = try container.decodeIfPresent(String.self, forKey: .command) ?? ""
            inTerminal = try container.decodeIfPresent(Bool.self, forKey: .inTerminal) ?? false
        }
    }

    private struct WebhookPayload: Codable {
        let url: String
        let method: HTTPMethod
        let headers: [String: String]?
        let body: String?

        init(url: String, method: HTTPMethod, headers: [String: String]?, body: String?) {
            self.url = url
            self.method = method
            self.headers = headers
            self.body = body
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
            method = try container.decodeIfPresent(HTTPMethod.self, forKey: .method) ?? .POST
            headers = try container.decodeIfPresent([String: String].self, forKey: .headers)
            body = try container.decodeIfPresent(String.self, forKey: .body)
        }
    }

    private struct OBSWebSocketPayload: Codable {
        let url: String
        let password: String?
        let requestType: String
        let requestData: String?

        private enum PayloadCodingKeys: String, CodingKey {
            case url, password, requestType, requestData
        }

        init(url: String, password: String?, requestType: String, requestData: String?) {
            self.url = url
            self.password = password
            self.requestType = requestType
            self.requestData = requestData
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: PayloadCodingKeys.self)
            url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
            // Resolve password: Keychain reference (UUID) → fetch, plaintext (legacy) → use as-is
            let storedPassword = try container.decodeIfPresent(String.self, forKey: .password)
            if let stored = storedPassword, KeychainService.isKeychainReference(stored) {
                password = KeychainService.retrievePassword(key: stored)
            } else {
                password = storedPassword
            }
            requestType = try container.decodeIfPresent(String.self, forKey: .requestType) ?? ""
            requestData = try container.decodeIfPresent(String.self, forKey: .requestData)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: PayloadCodingKeys.self)
            try container.encode(url, forKey: .url)
            // Store password in Keychain, write stable key reference to JSON
            if let password = password, !password.isEmpty {
                let key = KeychainService.stableKey(for: "obs-websocket:\(url)")
                if KeychainService.storePassword(password, key: key) != nil {
                    try container.encode(key, forKey: .password)
                } else {
                    // Keychain store failed — fall back to plaintext to avoid silent data loss
                    NSLog("[Macro] Keychain store failed, falling back to plaintext for OBS password")
                    try container.encode(password, forKey: .password)
                }
            }
            try container.encode(requestType, forKey: .requestType)
            try container.encodeIfPresent(requestData, forKey: .requestData)
        }
    }
}

extension MacroStep {
    var displayString: String {
        switch self {
        case .press(let mapping):
            return "Press: \(mapping.displayString)"
        case .hold(let mapping, let duration):
            return "Hold: \(mapping.displayString) (\(String(format: "%.2fs", duration)))"
        case .delay(let duration):
            return "Wait: \(String(format: "%.2fs", duration))"
        case .typeText(let text, let speed, let pressEnter):
            let speedText = speed == 0 ? "Paste" : "\(speed) CPM"
            let enterText = pressEnter ? " + ⏎" : ""
            return "Type: \"\(text)\" (\(speedText))\(enterText)"
        case .openApp(let bundleIdentifier, let newWindow):
            let appName: String
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                appName = url.deletingPathExtension().lastPathComponent
            } else {
                appName = bundleIdentifier
            }
            return newWindow ? "Open: \(appName) (New Window)" : "Open: \(appName)"
        case .openLink(let url):
            let display = url.count > 35 ? String(url.prefix(35)) + "..." : url
            return "Open: \(display)"
        case .shellCommand(let command, _):
            let display = command.count > 35 ? String(command.prefix(35)) + "..." : command
            return "Shell: \(display)"
        case .webhook(let url, let method, _, _):
            let display = "\(method.rawValue) \(url)"
            return display.count > 35 ? String(display.prefix(35)) + "..." : display
        case .obsWebSocket(_, _, let requestType, _):
            return "OBS: \(requestType)"
        }
    }
}
