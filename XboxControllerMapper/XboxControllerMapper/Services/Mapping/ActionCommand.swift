import Foundation
import CoreGraphics

// MARK: - ActionCommand Protocol

/// A command object that encapsulates a single executable action.
///
/// Replaces the hardcoded if-else priority chain in MappingExecutor
/// with polymorphic dispatch. Each concrete command knows how to execute
/// itself and provide feedback text.
///
/// `execute()` returns the feedback string because some commands (scripts)
/// compute feedback during execution.
protocol ActionCommand {
    /// Executes the action and returns feedback text for the HUD/log.
    func execute() -> String
}

// MARK: - Concrete Commands

/// Executes a system command (shell, webhook, OBS, launch app, open link)
struct SystemCommandActionCommand: ActionCommand {
    let systemCommand: SystemCommand
    let systemCommandExecutor: SystemCommandExecutor
    let hint: String?

    func execute() -> String {
        systemCommandExecutor.execute(systemCommand)
        if let hint = hint, !hint.isEmpty { return hint }
        return systemCommand.displayName
    }
}

/// Executes a macro sequence
struct MacroActionCommand: ActionCommand {
    let macro: Macro?
    let macroExecutor: MacroExecutor
    let hint: String?

    func execute() -> String {
        if let macro = macro {
            macroExecutor.execute(macro)
        }
        if let hint = hint, !hint.isEmpty { return hint }
        if let macro = macro { return macro.name }
        return "Macro"
    }
}

/// Executes a JavaScript script, returning dynamic feedback from the script result
struct ScriptActionCommand: ActionCommand {
    let script: Script?
    let scriptEngine: ScriptEngine?
    let trigger: ScriptTrigger
    let hint: String?

    func execute() -> String {
        guard let scriptEngine = scriptEngine else {
            return (hint?.isEmpty == false) ? hint! : "Script"
        }

        guard let script = script else {
            return (hint?.isEmpty == false) ? hint! : "Script"
        }

        let result = scriptEngine.execute(script: script, trigger: trigger)

        switch result {
        case .success(let hintOverride):
            return hintOverride ?? ((hint?.isEmpty == false) ? hint! : script.name)
        case .error(let message):
            NSLog("[ScriptActionCommand] Error: %@", message)
            return "Script Error"
        }
    }
}

/// Executes a key press with optional modifiers
struct KeyPressActionCommand: ActionCommand {
    let keyCode: CGKeyCode
    let modifiers: CGEventFlags
    let inputSimulator: InputSimulatorProtocol
    let action: any ExecutableAction

    func execute() -> String {
        inputSimulator.pressKey(keyCode, modifiers: modifiers)
        // Notify on-screen keyboard of controller key press
        OnScreenKeyboardManager.shared.notifyControllerKeyPress(
            keyCode: keyCode, modifiers: modifiers
        )
        return action.feedbackString
    }
}

/// Taps a modifier key (hold + delayed release)
struct ModifierTapActionCommand: ActionCommand {
    let modifierFlags: CGEventFlags
    let inputSimulator: InputSimulatorProtocol
    let inputQueue: DispatchQueue
    let action: any ExecutableAction

    func execute() -> String {
        inputSimulator.holdModifier(modifierFlags)
        inputQueue.asyncAfter(deadline: .now() + Config.modifierReleaseCheckDelay) { [inputSimulator] in
            inputSimulator.releaseModifier(modifierFlags)
        }
        return action.feedbackString
    }
}

/// No-op command for empty/unconfigured mappings
struct NoOpActionCommand: ActionCommand {
    let action: any ExecutableAction

    func execute() -> String {
        action.feedbackString
    }
}

// MARK: - ActionCommandFactory

/// Creates the appropriate ActionCommand for a given ExecutableAction.
///
/// Encodes the priority chain: systemCommand > macro > script > keyPress.
/// This replaces the if-else chain in MappingExecutor.executeAction.
struct ActionCommandFactory {
    let inputSimulator: InputSimulatorProtocol
    let inputQueue: DispatchQueue
    let macroExecutor: MacroExecutor
    let systemCommandExecutor: SystemCommandExecutor
    let scriptEngine: ScriptEngine?

    func makeCommand(
        for action: any ExecutableAction,
        profile: Profile?,
        button: ControllerButton = .a,
        pressType: PressType = .press
    ) -> ActionCommand {
        // Priority 1: System command
        if let systemCommand = action.systemCommand {
            return SystemCommandActionCommand(
                systemCommand: systemCommand,
                systemCommandExecutor: systemCommandExecutor,
                hint: action.hint
            )
        }

        // Priority 2: Macro
        if let macroId = action.macroId {
            let macro = profile?.macros.first(where: { $0.id == macroId })
            return MacroActionCommand(
                macro: macro,
                macroExecutor: macroExecutor,
                hint: action.hint
            )
        }

        // Priority 3: Script
        if let scriptId = action.scriptId, scriptEngine != nil {
            let script = profile?.scripts.first(where: { $0.id == scriptId })
            let trigger = ScriptTrigger(button: button, pressType: pressType)
            return ScriptActionCommand(
                script: script,
                scriptEngine: scriptEngine,
                trigger: trigger,
                hint: action.hint
            )
        }

        // Priority 4: Key press or modifier tap
        if let keyCode = action.keyCode {
            return KeyPressActionCommand(
                keyCode: keyCode,
                modifiers: action.modifiers.cgEventFlags,
                inputSimulator: inputSimulator,
                action: action
            )
        }

        if action.modifiers.hasAny {
            return ModifierTapActionCommand(
                modifierFlags: action.modifiers.cgEventFlags,
                inputSimulator: inputSimulator,
                inputQueue: inputQueue,
                action: action
            )
        }

        // No action configured
        return NoOpActionCommand(action: action)
    }
}
