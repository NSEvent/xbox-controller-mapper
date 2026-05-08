import Foundation
import CoreGraphics
import CoreTransferable

/// Represents a quadrant of the touchpad surface.
enum TouchpadRegion: String, Codable, CaseIterable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        }
    }

    /// Determines which quadrant a normalized touchpad position (0-1) falls in.
    /// x: 0 = left, 1 = right. y: 0 = bottom, 1 = top.
    static func from(position: CGPoint) -> TouchpadRegion {
        let isRight = position.x >= 0.5
        let isTop = position.y >= 0.5
        switch (isRight, isTop) {
        case (false, true):  return .topLeft
        case (true, true):   return .topRight
        case (false, false): return .bottomLeft
        case (true, false):  return .bottomRight
        }
    }
}

extension TouchpadRegion: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(
            exporting: { (region: TouchpadRegion) -> String in region.rawValue },
            importing: { (rawValue: String) -> TouchpadRegion in
                guard let region = TouchpadRegion(rawValue: rawValue) else {
                    throw CocoaError(.coderInvalidValue)
                }
                return region
            }
        )
    }
}

/// Selects which set of touchpad buttons is active for a profile.
///
/// **Whole pad mode (default):** the four classic touchpad buttons fire —
/// `.touchpadButton`, `.touchpadTap`, `.touchpadTwoFingerButton`,
/// `.touchpadTwoFingerTap`. The eight quadrant buttons are inactive.
///
/// **Quadrants mode:** the eight region buttons fire (4 quadrants × {click,
/// touch}). The single-finger global buttons (`.touchpadButton`,
/// `.touchpadTap`) are suppressed in favor of the per-quadrant variants.
/// Two-finger buttons stay active in both modes — there's no quadrant
/// concept for two-finger actions.
///
/// The mode is per-profile so different controllers / use cases can pick
/// different layouts.
enum TouchpadInputMode: String, Codable, CaseIterable {
    case wholePad
    case quadrants

    var displayName: String {
        switch self {
        case .wholePad: return "Whole Pad"
        case .quadrants: return "Quadrants"
        }
    }
}

/// When a touchpad region mapping fires.
enum TouchpadTriggerMode: String, Codable, CaseIterable {
    case touch   // Fires on finger contact
    case click   // Fires on physical press (click)
    case both    // Fires on either

    var displayName: String {
        switch self {
        case .touch: return "Touch"
        case .click: return "Click"
        case .both: return "Both"
        }
    }
}

/// Maps a touchpad region to an action (key press, macro, system command, etc.).
struct TouchpadRegionMapping: Codable, Identifiable, Equatable {
    var id: UUID
    var region: TouchpadRegion
    var triggerMode: TouchpadTriggerMode
    var keyCode: CGKeyCode?
    var modifiers: ModifierFlags
    var macroId: UUID?
    var systemCommand: SystemCommand?
    var hint: String?

    init(
        id: UUID = UUID(),
        region: TouchpadRegion,
        triggerMode: TouchpadTriggerMode = .click,
        keyCode: CGKeyCode? = nil,
        modifiers: ModifierFlags = ModifierFlags(),
        macroId: UUID? = nil,
        systemCommand: SystemCommand? = nil,
        hint: String? = nil
    ) {
        self.id = id
        self.region = region
        self.triggerMode = triggerMode
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.macroId = macroId
        self.systemCommand = systemCommand
        self.hint = hint
    }

    /// Whether this mapping has any action configured.
    var isEmpty: Bool {
        keyCode == nil && macroId == nil && systemCommand == nil
    }

    // MARK: - Custom Codable

    private enum CodingKeys: String, CodingKey {
        case id, region, triggerMode, keyCode, modifiers, macroId, systemCommand, hint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        region = try container.decodeIfPresent(TouchpadRegion.self, forKey: .region) ?? .topLeft
        triggerMode = try container.decodeIfPresent(TouchpadTriggerMode.self, forKey: .triggerMode) ?? .click
        keyCode = try container.decodeIfPresent(CGKeyCode.self, forKey: .keyCode)
        modifiers = try container.decodeIfPresent(ModifierFlags.self, forKey: .modifiers) ?? ModifierFlags()
        macroId = try container.decodeIfPresent(UUID.self, forKey: .macroId)
        systemCommand = try container.decodeIfPresent(SystemCommand.self, forKey: .systemCommand)
        hint = try container.decodeIfPresent(String.self, forKey: .hint)
    }
}
