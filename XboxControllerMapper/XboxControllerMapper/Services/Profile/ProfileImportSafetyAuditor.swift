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
///
/// The walk itself lives on the data types via `ProfileSurfaceVisitor`; this
/// file is a thin visitor that accumulates findings. Any new code-execution
/// field added to a Profile-reachable type must extend the corresponding
/// `accept`/`walkSurface` method, at which point this auditor automatically
/// inherits the call.
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
    }

    struct DiscoveredScript: Equatable, Identifiable {
        let id = UUID()
        let name: String
        let lineCount: Int
    }
}

enum ProfileImportSafetyAuditor {
    /// Walk the profile via `ProfileSurfaceVisitor` and assemble a report of
    /// shell commands and scripts discovered.
    static func audit(_ profile: Profile) -> ProfileImportSafetyReport {
        var collector = SafetySurfaceCollector()
        profile.walkSurface(&collector)
        return ProfileImportSafetyReport(
            shellCommands: collector.commands,
            scripts: collector.scripts
        )
    }

    /// Visitor that turns each visited surface into a finding (or skips it
    /// when there's nothing actionable to report).
    private struct SafetySurfaceCollector: ProfileSurfaceVisitor {
        var commands: [ProfileImportSafetyReport.DiscoveredShellCommand] = []
        var scripts: [ProfileImportSafetyReport.DiscoveredScript] = []

        mutating func visit(systemCommand: SystemCommand, context: String) {
            switch systemCommand {
            case let .shellCommand(cmd, inTerminal):
                guard !cmd.isEmpty else { return }
                commands.append(.init(context: context, command: cmd, inTerminal: inTerminal))

            case let .httpRequest(_, _, _, _, responseHandling):
                // Webhook responseHandling can carry shell follow-ups that
                // SystemCommandExecutor runs silently after the request
                // resolves (see SystemCommandExecutor.swift:459).
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

            // Explicit cases (no `default`): adding a new SystemCommand
            // variant must surface here as a compile error so the auditor
            // doesn't silently drop a new execution surface.
            case .launchApp, .openLink, .obsWebSocket:
                break
            }
        }

        mutating func visit(macro: Macro) {
            let macroName = macro.name.isEmpty ? "(unnamed)" : macro.name
            for (idx, step) in macro.steps.enumerated() {
                guard case let .shellCommand(command, inTerminal) = step else { continue }
                guard !command.isEmpty else { continue }
                commands.append(.init(
                    context: "Macro '\(macroName)' step \(idx + 1)",
                    command: command,
                    inTerminal: inTerminal
                ))
            }
        }

        mutating func visit(script: Script) {
            let scriptName = script.name.isEmpty ? "(unnamed script)" : script.name
            let lineCount = script.source.isEmpty
                ? 0
                : script.source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
            scripts.append(.init(name: scriptName, lineCount: lineCount))
        }

        mutating func visit(quickText: QuickText) {
            guard quickText.isTerminalCommand, !quickText.text.isEmpty else { return }
            commands.append(.init(
                context: "On-screen keyboard terminal command",
                command: quickText.text,
                inTerminal: true
            ))
        }
    }
}
