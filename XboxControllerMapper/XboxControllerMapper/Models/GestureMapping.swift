import Foundation
import CoreGraphics

/// Types of motion gestures detected from the DualSense gyroscope
enum MotionGestureType: String, Codable, CaseIterable, Identifiable {
    case tiltBack
    case tiltForward
    case steerLeft
    case steerRight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tiltBack: return "Tilt Back"
        case .tiltForward: return "Tilt Forward"
        case .steerLeft: return "Steer Left"
        case .steerRight: return "Steer Right"
        }
    }

    var iconName: String {
        switch self {
        case .tiltBack: return "iphone.and.arrow.backward"
        case .tiltForward: return "iphone.and.arrow.forward"
        case .steerLeft: return "arrow.turn.up.left"
        case .steerRight: return "arrow.turn.up.right"
        }
    }

    /// Corresponding virtual ControllerButton for logging
    var controllerButton: ControllerButton {
        switch self {
        case .tiltBack: return .gestureTiltBack
        case .tiltForward: return .gestureTiltForward
        case .steerLeft: return .gestureSteerLeft
        case .steerRight: return .gestureSteerRight
        }
    }
}

/// Represents a gesture-to-action mapping
struct GestureMapping: Codable, Identifiable, Equatable, ExecutableAction {
    var id: UUID
    var gestureType: MotionGestureType

    /// The key code to simulate when gesture is detected
    var keyCode: CGKeyCode?

    /// Modifier flags to apply
    var modifiers: ModifierFlags

    /// Optional ID of a macro to execute instead of key press
    var macroId: UUID?

    /// Optional ID of a script to execute instead of key press
    var scriptId: UUID?

    /// Optional system command to execute instead of key press
    var systemCommand: SystemCommand?

    /// Optional user-provided description of what this gesture does
    var hint: String?

    init(
        id: UUID = UUID(),
        gestureType: MotionGestureType,
        keyCode: CGKeyCode? = nil,
        modifiers: ModifierFlags = ModifierFlags(),
        macroId: UUID? = nil,
        scriptId: UUID? = nil,
        systemCommand: SystemCommand? = nil,
        hint: String? = nil
    ) {
        self.id = id
        self.gestureType = gestureType
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.macroId = macroId
        self.scriptId = scriptId
        self.systemCommand = systemCommand
        self.hint = hint
    }

    private enum CodingKeys: String, CodingKey {
        case id, gestureType, keyCode, modifiers, macroId, scriptId, systemCommand, hint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        // decodeIfPresent throws on invalid enum values (key present but value unrecognized),
        // so wrap in do-catch to log the bad value and fall back gracefully.
        do {
            gestureType = try container.decodeIfPresent(MotionGestureType.self, forKey: .gestureType) ?? .tiltBack
        } catch {
            let rawValue = try? container.decode(String.self, forKey: .gestureType)
            NSLog("[GestureMapping] Unknown gestureType '%@', falling back to tiltBack", rawValue ?? "<decode failure>")
            gestureType = .tiltBack
        }
        keyCode = try container.decodeIfPresent(CGKeyCode.self, forKey: .keyCode)
        modifiers = try container.decodeIfPresent(ModifierFlags.self, forKey: .modifiers) ?? ModifierFlags()
        macroId = try container.decodeIfPresent(UUID.self, forKey: .macroId)
        scriptId = try container.decodeIfPresent(UUID.self, forKey: .scriptId)
        systemCommand = try container.decodeIfPresent(SystemCommand.self, forKey: .systemCommand)
        hint = try container.decodeIfPresent(String.self, forKey: .hint)
    }

    /// Human-readable description of the mapping action
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

    /// ExecutableAction protocol conformance
    var displayString: String { actionDisplayString }

    /// Whether this gesture mapping has any action configured
    var hasAction: Bool {
        keyCode != nil || macroId != nil || scriptId != nil || systemCommand != nil || modifiers.hasAny
    }

    // MARK: - Action Conflict Resolution

    /// Returns a copy with all action fields cleared except the specified type.
    func clearingConflicts(keeping actionType: ActionType) -> GestureMapping {
        var copy = self
        if actionType != .keyPress {
            copy.keyCode = nil
            copy.modifiers = ModifierFlags()
        }
        if actionType != .macro { copy.macroId = nil }
        if actionType != .script { copy.scriptId = nil }
        if actionType != .systemCommand { copy.systemCommand = nil }
        return copy
    }
}
