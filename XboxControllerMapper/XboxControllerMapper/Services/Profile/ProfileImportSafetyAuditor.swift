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

        // Layer mappings use the same `KeyMapping` struct as the base profile,
        // so they can carry `longHoldMapping` and `doubleTapMapping` variants
        // too — and `MappingEngine` executes them. Earlier versions of this
        // function only walked `mapping.systemCommand`, leaving the long-hold
        // and double-tap shell payloads as a bypass surface for malicious
        // profiles.
        for layer in profile.layers {
            let layerName = layer.name.isEmpty ? "(unnamed)" : layer.name
            for (button, mapping) in layer.buttonMappings {
                collectShell(from: mapping.systemCommand,
                             context: "Layer '\(layerName)' Button \(button.shortLabel)",
                             into: &commands)
                collectShell(from: mapping.longHoldMapping?.systemCommand,
                             context: "Layer '\(layerName)' Button \(button.shortLabel) (long hold)",
                             into: &commands)
                collectShell(from: mapping.doubleTapMapping?.systemCommand,
                             context: "Layer '\(layerName)' Button \(button.shortLabel) (double tap)",
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
        // can still carry them prior to migration). Route through collectShell
        // so .httpRequest webhook follow-ups (onSuccess/onError) here are
        // surfaced too — earlier versions used a direct `if case` that only
        // caught .shellCommand.
        for region in profile.touchpadRegionMappings {
            collectShell(
                from: region.systemCommand,
                context: "Touchpad region \(region.region.rawValue) (\(region.triggerMode.rawValue))",
                into: &commands
            )
        }

        // On-screen-keyboard quick texts with `isTerminalCommand == true` run
        // their text through Terminal — same code-execution surface as a
        // .shellCommand binding, just reached via the OSK instead of a
        // physical button. Missing this would let a malicious community
        // profile hide shell payloads in the OSK and bypass the warning.
        for quickText in profile.onScreenKeyboardSettings.quickTexts where quickText.isTerminalCommand {
            commands.append(.init(
                context: "On-screen keyboard terminal command",
                command: quickText.text,
                inTerminal: true
            ))
        }

        return ProfileImportSafetyReport(shellCommands: commands, scripts: scripts)
    }

    private static func collectShell(
        from command: SystemCommand?,
        context: String,
        into commands: inout [ProfileImportSafetyReport.DiscoveredShellCommand]
    ) {
        switch command {
        case let .shellCommand(cmd, inTerminal):
            commands.append(.init(context: context, command: cmd, inTerminal: inTerminal))

        case let .httpRequest(_, _, _, _, responseHandling):
            // Webhook responseHandling can carry shell follow-ups that
            // SystemCommandExecutor runs silently after the request resolves
            // (see SystemCommandExecutor.swift:459). A malicious profile
            // could otherwise hide a payload here and bypass this auditor
            // since it doesn't appear under any .shellCommand binding.
            if let onSuccess = responseHandling?.onSuccessCommand, !onSuccess.isEmpty {
                commands.append(.init(
                    context: "\(context) (webhook on-success)",
                    command: onSuccess,
                    inTerminal: false
                ))
            }
            if let onError = responseHandling?.onErrorCommand, !onError.isEmpty {
                commands.append(.init(
                    context: "\(context) (webhook on-error)",
                    command: onError,
                    inTerminal: false
                ))
            }

        case .launchApp, .openLink, .obsWebSocket, nil:
            break
        }
    }
}
