import Foundation

/// Itemized audit of the code-execution surface a `Profile` brings into the
/// app at import time. Surfaced to the user via `ProfileImportSafetySheet`
/// before any external (community / file / URL / StreamDeck) profile is
/// allowed to add bindings to ProfileManager.
///
/// Scope is intentionally narrow: shell commands (run as the user, full
/// permissions) and scripts (full JavaScript host with shell access). Other
/// SystemCommand cases (launchApp, openLink, httpRequest, obsWebSocket) are
/// also network/automation risks but get separate treatment.
struct ProfileImportSafetyReport: Equatable {
    let shellCommands: [DiscoveredShellCommand]
    let scripts: [DiscoveredScript]

    var requiresUserConfirmation: Bool {
        !shellCommands.isEmpty || !scripts.isEmpty
    }

    struct DiscoveredShellCommand: Equatable, Identifiable {
        let id = UUID()
        let context: String   // "Button A", "Chord X+Y", "Macro 'X' step 3", etc.
        let command: String
        let inTerminal: Bool

        private enum CodingKeys: String, CodingKey { case context, command, inTerminal }
    }

    struct DiscoveredScript: Equatable, Identifiable {
        let id = UUID()
        let name: String
        let lineCount: Int
    }
}

enum ProfileImportSafetyAuditor {
    /// Walk every place a `Profile` can hide a shell command or script.
    static func audit(_ profile: Profile) -> ProfileImportSafetyReport {
        var commands: [ProfileImportSafetyReport.DiscoveredShellCommand] = []
        var scripts: [ProfileImportSafetyReport.DiscoveredScript] = []

        // Button mappings + long-hold + double-tap variants.
        for (button, mapping) in profile.buttonMappings {
            collectShell(from: mapping.systemCommand,
                         context: "Button \(button.shortLabel)",
                         into: &commands)
            collectShell(from: mapping.longHoldMapping?.systemCommand,
                         context: "Button \(button.shortLabel) (long hold)",
                         into: &commands)
            collectShell(from: mapping.doubleTapMapping?.systemCommand,
                         context: "Button \(button.shortLabel) (double tap)",
                         into: &commands)
        }

        for chord in profile.chordMappings {
            collectShell(from: chord.systemCommand,
                         context: "Chord \(chord.buttonsDisplayString)",
                         into: &commands)
        }

        for sequence in profile.sequenceMappings {
            collectShell(from: sequence.systemCommand,
                         context: "Sequence \(sequence.stepsDisplayString)",
                         into: &commands)
        }

        for gesture in profile.gestureMappings {
            collectShell(from: gesture.systemCommand,
                         context: "Gesture: \(gesture.gestureType.displayName)",
                         into: &commands)
        }

        for action in profile.commandWheelActions {
            let label = action.displayName.isEmpty ? "(unnamed)" : action.displayName
            collectShell(from: action.systemCommand,
                         context: "Command Wheel: \(label)",
                         into: &commands)
        }

        // Layers carry their own per-button mappings (no Edge / long-hold
        // variants on layer mappings as of today, so the simpler walk is fine).
        for layer in profile.layers {
            for (button, mapping) in layer.buttonMappings {
                let layerName = layer.name.isEmpty ? "(unnamed)" : layer.name
                collectShell(from: mapping.systemCommand,
                             context: "Layer '\(layerName)' Button \(button.shortLabel)",
                             into: &commands)
            }
        }

        // Macros store their own embedded shell steps (independent of SystemCommand).
        for macro in profile.macros {
            for (idx, step) in macro.steps.enumerated() {
                if case let .shellCommand(command, inTerminal) = step {
                    let macroName = macro.name.isEmpty ? "(unnamed)" : macro.name
                    commands.append(.init(
                        context: "Macro '\(macroName)' step \(idx + 1)",
                        command: command,
                        inTerminal: inTerminal
                    ))
                }
            }
        }

        // Scripts are full JavaScript with shell() bindings — every script
        // gets surfaced regardless of its content; the user should see exactly
        // how much code they're authorizing.
        for script in profile.scripts {
            let scriptName = script.name.isEmpty ? "(unnamed script)" : script.name
            let lineCount = script.source.isEmpty
                ? 0
                : script.source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
            scripts.append(.init(name: scriptName, lineCount: lineCount))
        }

        // Legacy v1 touchpad-region mappings (drained at load via
        // ProfileConfigurationMigrationService, but a freshly imported profile
        // can still carry them prior to migration).
        for region in profile.touchpadRegionMappings {
            if case let .shellCommand(command, inTerminal)? = region.systemCommand {
                commands.append(.init(
                    context: "Touchpad region \(region.region.rawValue) (\(region.triggerMode.rawValue))",
                    command: command,
                    inTerminal: inTerminal
                ))
            }
        }

        return ProfileImportSafetyReport(shellCommands: commands, scripts: scripts)
    }

    private static func collectShell(
        from command: SystemCommand?,
        context: String,
        into commands: inout [ProfileImportSafetyReport.DiscoveredShellCommand]
    ) {
        guard case let .shellCommand(cmd, inTerminal)? = command else { return }
        commands.append(.init(context: context, command: cmd, inTerminal: inTerminal))
    }
}
