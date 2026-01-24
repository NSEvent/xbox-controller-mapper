import Foundation
import AppKit

/// Categories for grouping system commands in the UI
enum SystemCommandCategory: String, CaseIterable {
    case app = "Launch App"
    case shell = "Shell Command"
}

/// Represents a system-level command that can be triggered by a button or chord mapping
enum SystemCommand: Equatable {
    // App launching
    case launchApp(bundleIdentifier: String)

    // Shell command execution
    case shellCommand(command: String, inTerminal: Bool)

    /// Human-readable display name for the UI
    var displayName: String {
        switch self {
        case .launchApp(let bundleId):
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                return url.deletingPathExtension().lastPathComponent
            }
            return bundleId
        case .shellCommand(let command, _):
            if command.count > 30 {
                return String(command.prefix(30)) + "..."
            }
            return command
        }
    }

    /// Category for UI grouping
    var category: SystemCommandCategory {
        switch self {
        case .launchApp: return .app
        case .shellCommand: return .shell
        }
    }
}

// MARK: - Codable

extension SystemCommand: Codable {
    private enum CommandType: String, Codable {
        case launchApp, shellCommand
    }

    private enum CodingKeys: String, CodingKey {
        case type, bundleIdentifier, command, inTerminal
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(CommandType.self, forKey: .type)

        switch type {
        case .launchApp:
            let bundleId = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier) ?? ""
            self = .launchApp(bundleIdentifier: bundleId)
        case .shellCommand:
            let command = try container.decodeIfPresent(String.self, forKey: .command) ?? ""
            let inTerminal = try container.decodeIfPresent(Bool.self, forKey: .inTerminal) ?? false
            self = .shellCommand(command: command, inTerminal: inTerminal)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .launchApp(let bundleId):
            try container.encode(CommandType.launchApp, forKey: .type)
            try container.encode(bundleId, forKey: .bundleIdentifier)
        case .shellCommand(let command, let inTerminal):
            try container.encode(CommandType.shellCommand, forKey: .type)
            try container.encode(command, forKey: .command)
            try container.encode(inTerminal, forKey: .inTerminal)
        }
    }
}
