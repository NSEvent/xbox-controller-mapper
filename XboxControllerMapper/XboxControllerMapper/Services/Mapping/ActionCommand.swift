import Foundation
import CoreGraphics
import TriggerKitCore
import TriggerKitLibrary

// MARK: - ActionCommand Protocol

/// A command object that encapsulates a single executable action.
///
/// Replaces the hardcoded if-else priority chain in MappingExecutor
/// with polymorphic dispatch. Each concrete command knows how to execute
/// itself and provide feedback text.
///
struct ActionCommandOutcome {
    let feedback: String
    let didDispatch: Bool
}

protocol ActionCommand {
    /// Executes the action and reports whether any configured output dispatched.
    func executeWithOutcome() -> ActionCommandOutcome
}

extension ActionCommand {
    /// Compatibility path for callers that only need HUD/log feedback.
    func execute() -> String { executeWithOutcome().feedback }
}

// MARK: - Concrete Commands

/// Executes a system command (shell, webhook, OBS, launch app, open link)
struct SystemCommandActionCommand: ActionCommand {
    let systemCommand: SystemCommand
    let systemCommandExecutor: SystemCommandExecutor
    let hint: String?

    func executeWithOutcome() -> ActionCommandOutcome {
        systemCommandExecutor.execute(systemCommand)
        let feedback = (hint?.isEmpty == false) ? hint! : systemCommand.displayName
        return ActionCommandOutcome(feedback: feedback, didDispatch: true)
    }
}

/// Executes a macro sequence
struct MacroActionCommand: ActionCommand {
    let macro: Macro?
    let macroExecutor: MacroExecutor
    let hint: String?

    func executeWithOutcome() -> ActionCommandOutcome {
        let didDispatch = macro?.steps.isEmpty == false
        if let macro, didDispatch {
            macroExecutor.execute(macro)
        }
        let feedback = (hint?.isEmpty == false) ? hint! : (macro?.name ?? "Macro")
        return ActionCommandOutcome(feedback: feedback, didDispatch: didDispatch)
    }
}

/// Executes a shared TriggerKit library macro (or its profile-embedded
/// snapshot when the library macro was deleted). `program` is nil when the
/// reference is unresolvable — the command then no-ops but still reports
/// feedback, matching MacroActionCommand's missing-macro behavior.
struct SharedMacroActionCommand: ActionCommand {
    let program: AutomationProgram?
    let macroExecutor: MacroExecutor
    let hint: String?

    func executeWithOutcome() -> ActionCommandOutcome {
        let didDispatch = program?.steps.isEmpty == false
        if let program, didDispatch {
            macroExecutor.execute(program: program)
        }
        let fallback = program?.name.isEmpty == false ? program!.name : "Macro"
        let feedback = (hint?.isEmpty == false) ? hint! : fallback
        return ActionCommandOutcome(feedback: feedback, didDispatch: didDispatch)
    }
}

/// Executes a JavaScript script, returning dynamic feedback from the script result
struct ScriptActionCommand: ActionCommand {
    let script: Script?
    let scriptEngine: ScriptEngine?
    let trigger: ScriptTrigger
    let hint: String?

    /// Returns the hint if non-empty, otherwise falls back to the given default.
    private func effectiveHint(fallback: String = "Script") -> String {
        (hint?.isEmpty == false) ? hint! : fallback
    }

    func executeWithOutcome() -> ActionCommandOutcome {
        guard let scriptEngine = scriptEngine else {
            return ActionCommandOutcome(feedback: effectiveHint(), didDispatch: false)
        }

        guard let script = script else {
            return ActionCommandOutcome(feedback: effectiveHint(), didDispatch: false)
        }

        let result = scriptEngine.execute(script: script, trigger: trigger)

        switch result {
        case .success(let hintOverride):
            return ActionCommandOutcome(
                feedback: hintOverride ?? effectiveHint(fallback: script.name),
                didDispatch: true
            )
        case .error(let message):
            NSLog("[ScriptActionCommand] Error: %@", message)
            return ActionCommandOutcome(feedback: "Script Error", didDispatch: false)
        }
    }
}

/// Emits a momentary MIDI Control Change (press value followed by release value).
struct MIDIControlChangeActionCommand: ActionCommand {
    let message: MIDIControlChange
    let midiService: any MIDIControlChangeSending
    let hint: String?

    func executeWithOutcome() -> ActionCommandOutcome {
		midiService.pulse(message)
		let feedback = (hint?.isEmpty == false) ? hint! : message.displayString
        return ActionCommandOutcome(feedback: feedback, didDispatch: true)
    }
}

/// Executes a key press with optional modifiers
struct KeyPressActionCommand: ActionCommand {
    let keyCode: CGKeyCode
    let modifiers: ModifierFlags
    let inputSimulator: InputSimulatorProtocol
    let action: any ExecutableAction

    func executeWithOutcome() -> ActionCommandOutcome {
        // Special-action markers (laser, OSK, lock, navigator, wheel) are
        // engine-level actions the input simulator deliberately drops — report
        // an honest non-dispatch instead of a false success (gyro markers never
        // reach here; the factory routes them to GyroActionCommand first).
        if KeyCodeMapping.isSpecialAction(keyCode) {
            return ActionCommandOutcome(
                feedback: "\(action.feedbackString) (not available here)",
                didDispatch: false
            )
        }
        inputSimulator.pressKey(keyCode, modifiers: modifiers)
        if !UniversalControlMouseRelay.shared.isRoutingToRemote {
            // Notify on-screen keyboard of controller key press
            OnScreenKeyboardManager.shared.notifyControllerKeyPress(
                keyCode: keyCode, modifiers: modifiers.cgEventFlags
            )
        }
        return ActionCommandOutcome(feedback: action.feedbackString, didDispatch: true)
    }
}

/// Taps a modifier key (hold + delayed release)
struct ModifierTapActionCommand: ActionCommand {
    let modifiers: ModifierFlags
    let inputSimulator: InputSimulatorProtocol
    let inputQueue: DispatchQueue
    let action: any ExecutableAction

    func executeWithOutcome() -> ActionCommandOutcome {
		inputSimulator.holdModifiers(modifiers)
        inputQueue.asyncAfter(deadline: .now() + Config.modifierReleaseCheckDelay) { [inputSimulator] in
			inputSimulator.releaseModifiers(modifiers)
        }
        return ActionCommandOutcome(feedback: action.feedbackString, didDispatch: true)
    }
}

/// Executes a gyro-control marker that reaches the executor path (gestures,
/// touchpad regions, command wheel — contexts without the engine's button
/// press/release intercepts). Toggle works everywhere via the engine's gyro
/// hook; Hold/Pause need a press/release pair, so here they only report that
/// honestly instead of silently doing nothing.
struct GyroActionCommand: ActionCommand {
    let gyroAction: GyroButtonAction
    let gyroControl: ScriptEngine.GyroControl?
    let action: any ExecutableAction

    func executeWithOutcome() -> ActionCommandOutcome {
        switch gyroAction {
        case .toggle:
            guard let gyroControl else {
                // nil means this executor context was never wired to the
                // engine's gyro hook (factories built with scriptEngine: nil,
                // e.g. in tests). Degrade to an honest non-dispatch.
                return ActionCommandOutcome(feedback: "Gyro Toggle (unavailable)", didDispatch: false)
            }
            let latchedOn = gyroControl.toggle()
            return ActionCommandOutcome(feedback: latchedOn ? "Gyro On" : "Gyro Off", didDispatch: true)
        case .hold, .pause:
            return ActionCommandOutcome(
                feedback: "\(action.feedbackString) (needs press & release)",
                didDispatch: false
            )
        }
    }
}

/// No-op command for empty/unconfigured mappings
struct NoOpActionCommand: ActionCommand {
    let action: any ExecutableAction

    func executeWithOutcome() -> ActionCommandOutcome {
        ActionCommandOutcome(feedback: action.feedbackString, didDispatch: false)
    }
}

// MARK: - ActionCommandFactory

/// Creates the appropriate ActionCommand for a given ExecutableAction.
///
/// Encodes the priority chain: systemCommand > macro > script > MIDI > keyPress.
/// This replaces the if-else chain in MappingExecutor.executeAction.
struct ActionCommandFactory {
    let inputSimulator: InputSimulatorProtocol
    let inputQueue: DispatchQueue
    let macroExecutor: MacroExecutor
    let systemCommandExecutor: SystemCommandExecutor
    let scriptEngine: ScriptEngine?
    let sharedMacroStore: AutomationMacroStore
    let midiService: any MIDIControlChangeSending

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

        // Priority 2: Macro. Profile macros win; an ID not in the profile is
        // a shared TriggerKit library reference (live macro first, then the
        // profile's stored snapshot if the library macro was deleted).
        if let macroId = action.macroId {
            if let macro = profile?.macros.first(where: { $0.id == macroId }) {
                return MacroActionCommand(
                    macro: macro,
                    macroExecutor: macroExecutor,
                    hint: action.hint
                )
            }
            let reference = AutomationMacroReference(
                macroID: macroId,
                snapshot: profile?.sharedMacroSnapshots[macroId]
            )
            return SharedMacroActionCommand(
                program: sharedMacroStore.resolve(reference, fallbackName: "Macro"),
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

		// Priority 4: MIDI Control Change
		if let midiControlChange = action.midiControlChange {
			return MIDIControlChangeActionCommand(
				message: midiControlChange,
				midiService: midiService,
				hint: action.hint
			)
		}

		// Priority 5a: Gyro-control markers — never posted as key events; toggle
		// routes through the engine's gyro hook so it works from any executor
		// path (gestures, touchpad regions, command wheel).
		if let keyCode = action.keyCode, let gyroAction = GyroButtonAction(keyCode: keyCode) {
			return GyroActionCommand(
				gyroAction: gyroAction,
				gyroControl: scriptEngine?.gyroControl,
				action: action
			)
		}

		// Priority 5: Key press or modifier tap
        if let keyCode = action.keyCode {
            return KeyPressActionCommand(
                keyCode: keyCode,
                modifiers: action.modifiers,
                inputSimulator: inputSimulator,
                action: action
            )
        }

        if action.modifiers.hasAny {
            return ModifierTapActionCommand(
				modifiers: action.modifiers,
                inputSimulator: inputSimulator,
                inputQueue: inputQueue,
                action: action
            )
        }

        // No action configured
        return NoOpActionCommand(action: action)
    }
}
