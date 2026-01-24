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

    /// Type a string of text with specified speed (CPM). 0 = Instant Paste.
    case typeText(String, speed: Int)

    /// Open an application, optionally in a new window
    case openApp(bundleIdentifier: String, newWindow: Bool)

    /// Open a URL in the default browser
    case openLink(url: String)
    
    // Custom decoding/encoding to handle enum associated values
    private enum CodingKeys: String, CodingKey {
        case type, payload
    }
    
    private enum StepType: String, Codable {
        case press, hold, delay, typeText, openApp, openLink
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
                self = .typeText(data.text, speed: data.speed)
            } else {
                // Fallback for legacy string-only payload
                let text = try container.decode(String.self, forKey: .payload)
                self = .typeText(text, speed: 0) // Default to paste/instant
            }
        case .openApp:
            let data = try container.decode(OpenAppPayload.self, forKey: .payload)
            self = .openApp(bundleIdentifier: data.bundleIdentifier, newWindow: data.newWindow)
        case .openLink:
            let url = try container.decode(String.self, forKey: .payload)
            self = .openLink(url: url)
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
        case .typeText(let text, let speed):
            try container.encode(StepType.typeText, forKey: .type)
            try container.encode(TypeTextPayload(text: text, speed: speed), forKey: .payload)
        case .openApp(let bundleIdentifier, let newWindow):
            try container.encode(StepType.openApp, forKey: .type)
            try container.encode(OpenAppPayload(bundleIdentifier: bundleIdentifier, newWindow: newWindow), forKey: .payload)
        case .openLink(let url):
            try container.encode(StepType.openLink, forKey: .type)
            try container.encode(url, forKey: .payload)
        }
    }
    
    private struct HoldPayload: Codable {
        let mapping: KeyMapping
        let duration: TimeInterval
    }
    
    private struct TypeTextPayload: Codable {
        let text: String
        let speed: Int
    }

    private struct OpenAppPayload: Codable {
        let bundleIdentifier: String
        let newWindow: Bool
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
        case .typeText(let text, let speed):
            let speedText = speed == 0 ? "Paste" : "\(speed) CPM"
            return "Type: \"\(text)\" (\(speedText))"
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
        }
    }
}
