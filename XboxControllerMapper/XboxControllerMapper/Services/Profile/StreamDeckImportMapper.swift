import Foundation
import CoreGraphics
import AppKit

// MARK: - Mapped Action

struct MappedAction: Identifiable {
    let id: UUID
    let streamDeckAction: StreamDeckAction
    var assignedButton: ControllerButton?
    let importResult: ImportResult

    enum ImportResult {
        case directKey(KeyMapping)
        case macro(Macro)
        case unsupported(reason: String)
    }

    var isSupported: Bool {
        switch importResult {
        case .unsupported: return false
        default: return true
        }
    }

    var displayDescription: String {
        switch importResult {
        case .directKey(let mapping):
            return mapping.displayString
        case .macro(let macro):
            return macro.steps.map { $0.displayString }.joined(separator: " → ")
        case .unsupported(let reason):
            return reason
        }
    }
}

// MARK: - Mapper

enum StreamDeckImportMapper {

    /// Button assignment priority order for auto-mapping.
    static let assignmentOrder: [ControllerButton] = [
        .a, .b, .x, .y,
        .leftBumper, .rightBumper,
        .leftTrigger, .rightTrigger,
        .dpadUp, .dpadDown, .dpadLeft, .dpadRight,
        .menu, .view, .share, .xbox,
        .leftThumbstick, .rightThumbstick
    ]

    /// Convert parsed Stream Deck actions into mapped actions with auto-assigned buttons.
    static func mapActions(_ actions: [StreamDeckAction]) -> [MappedAction] {
        var mapped: [MappedAction] = []
        var buttonIndex = 0

        for action in actions {
            let result = convertAction(action)
            let button: ControllerButton?

            if case .unsupported = result {
                button = nil
            } else if buttonIndex < assignmentOrder.count {
                button = assignmentOrder[buttonIndex]
                buttonIndex += 1
            } else {
                button = nil
            }

            mapped.append(MappedAction(
                id: action.id,
                streamDeckAction: action,
                assignedButton: button,
                importResult: result
            ))
        }

        return mapped
    }

    /// Convert a single Stream Deck action to an import result.
    static func convertAction(_ action: StreamDeckAction) -> MappedAction.ImportResult {
        switch action.settings {
        case .hotkey(let keyCode, let modifiers):
            let mapping = KeyMapping(
                keyCode: keyCode,
                modifiers: modifiers,
                hint: action.title
            )
            return .directKey(mapping)

        case .openApp(let path):
            let bundleId = resolveBundleIdentifier(from: path)
            let macro = Macro(
                name: action.title ?? action.name,
                steps: [.openApp(bundleIdentifier: bundleId, newWindow: false)]
            )
            return .macro(macro)

        case .website(let url):
            let macro = Macro(
                name: action.title ?? action.name,
                steps: [.openLink(url: url)]
            )
            return .macro(macro)

        case .text(let text):
            let macro = Macro(
                name: action.title ?? action.name,
                steps: [.typeText(text, speed: 0, pressEnter: false)]
            )
            return .macro(macro)

        case .multiAction(let subActions):
            var steps: [MacroStep] = []
            for sub in subActions {
                switch sub.settings {
                case .hotkey(let keyCode, let modifiers):
                    let mapping = KeyMapping(keyCode: keyCode, modifiers: modifiers)
                    steps.append(.press(mapping))
                case .openApp(let path):
                    let bundleId = resolveBundleIdentifier(from: path)
                    steps.append(.openApp(bundleIdentifier: bundleId, newWindow: false))
                case .website(let url):
                    steps.append(.openLink(url: url))
                case .text(let text):
                    steps.append(.typeText(text, speed: 0, pressEnter: false))
                case .multiAction, .unsupported:
                    break // Skip nested unsupported sub-actions
                }
            }
            if steps.isEmpty {
                return .unsupported(reason: "Multi-action has no supported sub-actions")
            }
            let macro = Macro(
                name: action.title ?? action.name,
                steps: steps
            )
            return .macro(macro)

        case .unsupported(let pluginUUID):
            return .unsupported(reason: "Unsupported Stream Deck plugin: \(pluginUUID)")
        }
    }

    /// Build a ControllerKeys Profile from mapped actions.
    static func buildProfile(name: String, mappedActions: [MappedAction]) -> Profile {
        var buttonMappings: [ControllerButton: KeyMapping] = [:]
        var macros: [Macro] = []

        for action in mappedActions {
            guard let button = action.assignedButton else { continue }

            switch action.importResult {
            case .directKey(let mapping):
                buttonMappings[button] = mapping

            case .macro(let macro):
                macros.append(macro)
                buttonMappings[button] = KeyMapping(
                    macroId: macro.id,
                    hint: action.streamDeckAction.title ?? action.streamDeckAction.name
                )

            case .unsupported:
                break
            }
        }

        return Profile(
            name: name,
            buttonMappings: buttonMappings,
            macros: macros
        )
    }

    // MARK: - Helpers

    private static func resolveBundleIdentifier(from path: String) -> String {
        if let bundle = Bundle(path: path), let bundleId = bundle.bundleIdentifier {
            return bundleId
        }
        // Try .app extension
        if !path.hasSuffix(".app") {
            let appPath = path + ".app"
            if let bundle = Bundle(path: appPath), let bundleId = bundle.bundleIdentifier {
                return bundleId
            }
        }
        // Fall back to path as identifier
        return path
    }
}
