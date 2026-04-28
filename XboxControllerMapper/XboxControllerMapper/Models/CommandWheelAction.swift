import Foundation
import CoreGraphics
import AppKit

/// An action configured for a command wheel slot.
///
/// Each item in the command wheel acts like a virtual button — it can trigger
/// any action type that a physical button mapping supports (key press, macro,
/// script, or system command).
struct CommandWheelAction: Codable, Identifiable, Equatable, ExecutableAction {
    var id: UUID

    /// Display name shown in the wheel's center hub when selected
    var displayName: String

    /// SF Symbol name for the wheel segment icon (e.g. "globe", "terminal")
    var iconName: String?

    /// Custom icon image data (PNG/JPEG, e.g. app icon or favicon)
    var iconData: Data?

    /// The key code to simulate when this action is activated
    var keyCode: CGKeyCode?

    /// Modifier flags to apply
    var modifiers: ModifierFlags

    /// Optional ID of a macro to execute instead of key press
    var macroId: UUID?

    /// Optional ID of a script to execute instead of key press
    var scriptId: UUID?

    /// Optional system command to execute instead of key press
    var systemCommand: SystemCommand?

    /// Optional user-provided description of what this action does
    var hint: String?

    /// Optional haptic feedback style to play when this action fires
    var hapticStyle: HapticStyle?

    init(
        id: UUID = UUID(),
        displayName: String = "",
        iconName: String? = nil,
        iconData: Data? = nil,
        keyCode: CGKeyCode? = nil,
        modifiers: ModifierFlags = ModifierFlags(),
        macroId: UUID? = nil,
        scriptId: UUID? = nil,
        systemCommand: SystemCommand? = nil,
        hint: String? = nil,
        hapticStyle: HapticStyle? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.iconName = iconName
        self.iconData = iconData
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.macroId = macroId
        self.scriptId = scriptId
        self.systemCommand = systemCommand
        self.hint = hint
        self.hapticStyle = hapticStyle
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, displayName, iconName, iconData
        case keyCode, modifiers, macroId, scriptId, systemCommand, hint, hapticStyle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        iconName = try container.decodeIfPresent(String.self, forKey: .iconName)
        iconData = try container.decodeIfPresent(Data.self, forKey: .iconData)
        keyCode = try container.decodeIfPresent(CGKeyCode.self, forKey: .keyCode)
        modifiers = try container.decodeIfPresent(ModifierFlags.self, forKey: .modifiers) ?? ModifierFlags()
        macroId = try container.decodeIfPresent(UUID.self, forKey: .macroId)
        scriptId = try container.decodeIfPresent(UUID.self, forKey: .scriptId)
        systemCommand = try container.decodeIfPresent(SystemCommand.self, forKey: .systemCommand)
        hint = try container.decodeIfPresent(String.self, forKey: .hint)
        hapticStyle = try container.decodeIfPresent(HapticStyle.self, forKey: .hapticStyle)
    }

    /// Human-readable description of the action
    var actionDisplayString: String {
        if let systemCommand = systemCommand {
            return systemCommand.displayName
        }
        if macroId != nil {
            return "Macro"
        }
        if scriptId != nil {
            return "Script"
        }
        return displayString
    }

    /// Whether this action has any executable action configured
    var hasAction: Bool {
        keyCode != nil || macroId != nil || scriptId != nil || systemCommand != nil || modifiers.hasAny
    }

    // MARK: - Icon Resolution

    /// The SF Symbol name to use as a fallback icon based on the action type
    var defaultIconName: String {
        switch effectiveActionType {
        case .keyPress: return "keyboard"
        case .macro: return "repeat"
        case .script: return "chevron.left.forwardslash.chevron.right"
        case .systemCommand:
            if let cmd = systemCommand {
                switch cmd {
                case .shellCommand: return "terminal"
                case .launchApp: return "app"
                case .openLink: return "globe"
                case .httpRequest: return "network"
                case .obsWebSocket: return "video"
                }
            }
            return "gearshape"
        case .none: return "questionmark.circle"
        }
    }

    /// Resolves the best available NSImage for this action.
    /// Priority: iconData → iconName SF Symbol → app icon / favicon → fallback SF Symbol.
    func resolvedIcon() -> NSImage? {
        if let data = iconData, let image = NSImage(data: data) {
            return image
        }
        if let name = iconName, let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
            return image
        }
        if let cmd = systemCommand {
            switch cmd {
            case .launchApp(let bundleId, _):
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                    return NSWorkspace.shared.icon(forFile: url.path)
                }
            case .openLink(let url):
                if let data = FaviconCache.shared.loadCachedFavicon(for: url) {
                    return NSImage(data: data)
                }
            default:
                break
            }
        }
        return NSImage(systemSymbolName: defaultIconName, accessibilityDescription: nil)
    }
}
