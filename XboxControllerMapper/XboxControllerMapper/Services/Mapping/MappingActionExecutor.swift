import Foundation
import CoreGraphics
import TriggerKitCore
import TriggerKitLibrary

// MARK: - Mapping Executor

/// Executes action mappings via ActionCommandFactory (command pattern).
///
/// Priority chain: systemCommand > macro > script > MIDI > keyPress/modifier.
/// The factory creates the appropriate ActionCommand, which is then executed polymorphically.
struct MappingExecutor {
    private let inputLogService: InputLogService?
    private let usageStatsService: UsageStatsService?
    let systemCommandExecutor: SystemCommandExecutor
    let macroExecutor: MacroExecutor
    private let sharedMacroStore: AutomationMacroStore
    private let commandFactory: ActionCommandFactory
    let midiService: any MIDIControlChangeSending

    init(
        inputSimulator: InputSimulatorProtocol,
        inputQueue: DispatchQueue,
        inputLogService: InputLogService?,
        profileManager: ProfileManager,
        usageStatsService: UsageStatsService? = nil,
		scriptEngine: ScriptEngine? = nil,
		midiService: any MIDIControlChangeSending = VirtualMIDIService.shared
    ) {
        self.inputLogService = inputLogService
        self.usageStatsService = usageStatsService
        self.systemCommandExecutor = SystemCommandExecutor(profileManager: profileManager)
        self.macroExecutor = MacroExecutor(
            inputSimulator: inputSimulator,
            systemCommandExecutor: self.systemCommandExecutor
        )
        self.sharedMacroStore = profileManager.sharedMacroStore
		self.midiService = midiService
        self.commandFactory = ActionCommandFactory(
            inputSimulator: inputSimulator,
            inputQueue: inputQueue,
            macroExecutor: self.macroExecutor,
            systemCommandExecutor: self.systemCommandExecutor,
            scriptEngine: scriptEngine,
			sharedMacroStore: self.sharedMacroStore,
			midiService: midiService
        )
    }

    /// Executes any action mapping (key press, macro, script, or system command).
    func executeAction(
        _ action: any ExecutableAction,
        for button: ControllerButton,
        profile: Profile?,
        logType: InputEventType = .singlePress
    ) {
        executeAction(action, for: [button], profile: profile, logType: logType)
    }

    /// Executes any action mapping (key press, macro, script, or system command) for one or more buttons.
    func executeAction(
        _ action: any ExecutableAction,
        for buttons: [ControllerButton],
        profile: Profile?,
        logType: InputEventType = .singlePress
    ) {
        guard let button = buttons.first else {
            #if DEBUG
            NSLog("[MappingExecutor] executeAction called with empty buttons array — skipping")
            #endif
            return
        }
        let pressType: PressType
        switch logType {
        case .longPress: pressType = .longHold
        case .doubleTap: pressType = .doubleTap
        default: pressType = .press
        }
        let command = commandFactory.makeCommand(
            for: action,
            profile: profile,
            button: button,
            pressType: pressType
        )
        let outcome = command.executeWithOutcome()
        inputLogService?.log(buttons: buttons, type: logType, action: outcome.feedback)

        // Record button/action type stats
        if buttons.count > 1 {
            usageStatsService?.recordChord(buttons: buttons, type: logType)
        } else if let button = buttons.first {
            usageStatsService?.record(button: button, type: logType)
        }

        if outcome.didDispatch {
            // Count only configured output that actually reached its executor.
            recordOutputAction(action, profile: profile)
            let telemetry = telemetryCategory(for: action)
            TelemetryService.shared.recordSuccessfulAction(
                category: telemetry.category,
                isComplex: telemetry.isComplex
            )
        }
    }

    /// Executes any action mapping and returns feedback text without logging.
    func executeAction(
        _ action: any ExecutableAction,
        profile: Profile?,
        button: ControllerButton = .a,
        pressType: PressType = .press
    ) -> String {
        let command = commandFactory.makeCommand(for: action, profile: profile, button: button, pressType: pressType)
        return command.execute()
    }

    /// Record what type of output action was performed.
    private func recordOutputAction(_ action: any ExecutableAction, profile: Profile?) {
        guard let service = usageStatsService else { return }

        // System command
        if let command = action.systemCommand {
            switch command {
			case .switchProfile, .navigateProfile:
				break
            case .httpRequest:
                service.recordWebhook()
            case .launchApp:
                service.recordAppLaunch()
            case .obsWebSocket:
                service.recordWebhook()
            case .openLink:
                service.recordLinkOpened()
            case .shellCommand(_, let inTerminal):
                if inTerminal {
                    service.recordTerminalCommand()
                }
			case .centerOuraRing, .toggleOuraMotion:
				break
            }
            return
        }

        // Macro
        if let macroId = action.macroId {
            if let profile, let macro = profile.macros.first(where: { $0.id == macroId }) {
                service.recordMacro(stepCount: macro.steps.count)
            } else if let program = sharedMacroStore.macro(id: macroId)?.program
                        ?? profile?.sharedMacroSnapshots[macroId] {
                service.recordMacro(stepCount: program.steps.count)
            } else {
                service.recordMacro(stepCount: 1)
            }
            return
        }

        // Script (count as a macro with 1 step for stats purposes)
        if action.scriptId != nil {
            service.recordMacro(stepCount: 1)
            return
        }

		if action.midiControlChange != nil {
			return
		}

        // Key press or mouse click
        if let keyCode = action.keyCode {
            if KeyCodeMapping.isMouseButton(keyCode) {
                service.recordMouseClick()
            } else {
                service.recordKeyPress()
            }
        }
    }

    /// Privacy-safe category for aggregate product telemetry. Deliberately
    /// excludes the button, key code, target app, URL, script, and profile.
    private func telemetryCategory(
        for action: any ExecutableAction
    ) -> (category: TelemetryService.FeatureCategory, isComplex: Bool) {
        if let command = action.systemCommand {
            switch command {
            case .switchProfile, .navigateProfile, .centerOuraRing, .toggleOuraMotion:
                return (.profileControl, false)
            case .httpRequest, .launchApp, .obsWebSocket, .openLink, .shellCommand:
                return (.automation, true)
            }
        }
        if action.macroId != nil || action.scriptId != nil { return (.macro, true) }
        if action.midiControlChange != nil { return (.midi, false) }
        if let keyCode = action.keyCode {
            return (KeyCodeMapping.isMouseButton(keyCode) ? .pointer : .keyboard, false)
        }
        return (.other, false)
    }
}
