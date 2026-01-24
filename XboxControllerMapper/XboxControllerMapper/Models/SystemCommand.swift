import Foundation
import AppKit

/// Categories for grouping system commands in the UI
enum SystemCommandCategory: String, CaseIterable {
    case shell = "Shell Command"
    case app = "Launch App"
    case link = "Open Link"
}

/// Represents a system-level command that can be triggered by a button or chord mapping
enum SystemCommand: Equatable {
    // App launching
    case launchApp(bundleIdentifier: String, newWindow: Bool = false)

    // Shell command execution
    case shellCommand(command: String, inTerminal: Bool)

    // Open URL in default browser
    case openLink(url: String)

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
        }
    }

    /// Category for UI grouping
    var category: SystemCommandCategory {
        switch self {
        case .launchApp: return .app
        case .shellCommand: return .shell
        case .openLink: return .link
        }
    }
}

// MARK: - Codable

extension SystemCommand: Codable {
    private enum CommandType: String, Codable {
        case launchApp, shellCommand, openLink
    }

    private enum CodingKeys: String, CodingKey {
        case type, bundleIdentifier, command, inTerminal, url, newWindow
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
        }
    }
}
