import Foundation
import CoreGraphics

// MARK: - Mapping Executor

/// Executes action mappings via ActionCommandFactory (command pattern).
///
/// Priority chain: systemCommand > macro > script > keyPress/modifier.
/// The factory creates the appropriate ActionCommand, which is then executed polymorphically.
struct MappingExecutor {
    private let inputLogService: InputLogService?
    private let usageStatsService: UsageStatsService?
    let systemCommandExecutor: SystemCommandExecutor
    let macroExecutor: MacroExecutor
    private let commandFactory: ActionCommandFactory

    init(
        inputSimulator: InputSimulatorProtocol,
        inputQueue: DispatchQueue,
        inputLogService: InputLogService?,
        profileManager: ProfileManager,
        usageStatsService: UsageStatsService? = nil,
        scriptEngine: ScriptEngine? = nil
    ) {
        self.inputLogService = inputLogService
        self.usageStatsService = usageStatsService
        self.systemCommandExecutor = SystemCommandExecutor(profileManager: profileManager)
        self.macroExecutor = MacroExecutor(
            inputSimulator: inputSimulator,
            systemCommandExecutor: self.systemCommandExecutor
        )
        self.commandFactory = ActionCommandFactory(
            inputSimulator: inputSimulator,
            inputQueue: inputQueue,
            macroExecutor: self.macroExecutor,
            systemCommandExecutor: self.systemCommandExecutor,
            scriptEngine: scriptEngine
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
        let button = buttons.first ?? .a
        let pressType: PressType
        switch logType {
        case .longPress: pressType = .longHold
        case .doubleTap: pressType = .doubleTap
        default: pressType = .press
        }
        let feedback = executeAction(action, profile: profile, button: button, pressType: pressType)
        inputLogService?.log(buttons: buttons, type: logType, action: feedback)

        // Record button/action type stats
        if buttons.count > 1 {
            usageStatsService?.recordChord(buttons: buttons, type: logType)
        } else if let button = buttons.first {
            usageStatsService?.record(button: button, type: logType)
        }

        // Record output action category
        recordOutputAction(action, profile: profile)
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
            }
            return
        }

        // Macro
        if let macroId = action.macroId {
            if let profile, let macro = profile.macros.first(where: { $0.id == macroId }) {
                service.recordMacro(stepCount: macro.steps.count)
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

        // Key press or mouse click
        if let keyCode = action.keyCode {
            if KeyCodeMapping.isMouseButton(keyCode) {
                service.recordMouseClick()
            } else {
                service.recordKeyPress()
            }
        }
    }
}
