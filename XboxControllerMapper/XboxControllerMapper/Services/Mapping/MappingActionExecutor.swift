import Foundation
import CoreGraphics

// MARK: - Mapping Action Strategy

private struct TapModifierExecutor {
    let inputSimulator: InputSimulatorProtocol
    let inputQueue: DispatchQueue

    func execute(_ flags: CGEventFlags) {
        inputSimulator.holdModifier(flags)
        inputQueue.asyncAfter(deadline: .now() + Config.modifierReleaseCheckDelay) { [inputSimulator] in
            inputSimulator.releaseModifier(flags)
        }
    }
}

private struct SystemCommandActionHandler {
    let systemCommandExecutor: SystemCommandExecutor

    func executeIfPossible(_ action: any ExecutableAction) -> String? {
        guard action.systemCommand != nil else { return nil }
        systemCommandExecutor.execute(action.systemCommand!)
        return action.feedbackString
    }
}

private struct MacroActionHandler {
    let inputSimulator: InputSimulatorProtocol

    func executeIfPossible(_ action: any ExecutableAction, profile: Profile?) -> String? {
        guard let macroId = action.macroId else { return nil }

        if let profile, let macro = profile.macros.first(where: { $0.id == macroId }) {
            inputSimulator.executeMacro(macro)
            return (action.hint?.isEmpty == false) ? action.hint! : macro.name
        }

        return (action.hint?.isEmpty == false) ? action.hint! : "Macro"
    }
}

private struct KeyOrModifierActionHandler {
    let inputSimulator: InputSimulatorProtocol
    let tapModifierExecutor: TapModifierExecutor

    func execute(_ action: any ExecutableAction) -> String {
        if let keyCode = action.keyCode {
            inputSimulator.pressKey(keyCode, modifiers: action.modifiers.cgEventFlags)
            // Update typing buffer if on-screen keyboard is visible
            OnScreenKeyboardManager.shared.notifyControllerKeyPress(
                keyCode: keyCode, modifiers: action.modifiers.cgEventFlags
            )
        } else if action.modifiers.hasAny {
            tapModifierExecutor.execute(action.modifiers.cgEventFlags)
        }
        return action.feedbackString
    }
}

// MARK: - Mapping Executor

/// Executes action mappings via a strategy chain (system command, macro, key/modifier).
struct MappingExecutor {
    private let inputLogService: InputLogService?
    private let usageStatsService: UsageStatsService?
    let systemCommandExecutor: SystemCommandExecutor
    private let systemCommandHandler: SystemCommandActionHandler
    private let macroHandler: MacroActionHandler
    private let keyOrModifierHandler: KeyOrModifierActionHandler

    init(
        inputSimulator: InputSimulatorProtocol,
        inputQueue: DispatchQueue,
        inputLogService: InputLogService?,
        profileManager: ProfileManager,
        usageStatsService: UsageStatsService? = nil
    ) {
        self.inputLogService = inputLogService
        self.usageStatsService = usageStatsService
        self.systemCommandExecutor = SystemCommandExecutor(profileManager: profileManager)
        let tapModifierExecutor = TapModifierExecutor(inputSimulator: inputSimulator, inputQueue: inputQueue)
        self.systemCommandHandler = SystemCommandActionHandler(systemCommandExecutor: self.systemCommandExecutor)
        self.macroHandler = MacroActionHandler(inputSimulator: inputSimulator)
        self.keyOrModifierHandler = KeyOrModifierActionHandler(inputSimulator: inputSimulator, tapModifierExecutor: tapModifierExecutor)

        // Wire up system command handler for macro steps
        let executor = self.systemCommandExecutor
        (inputSimulator as? InputSimulator)?.systemCommandHandler = { command in
            executor.execute(command)
        }
    }

    /// Executes any action mapping (key press, macro, or system command).
    func executeAction(
        _ action: any ExecutableAction,
        for button: ControllerButton,
        profile: Profile?,
        logType: InputEventType = .singlePress
    ) {
        executeAction(action, for: [button], profile: profile, logType: logType)
    }

    /// Executes any action mapping (key press, macro, or system command) for one or more buttons.
    func executeAction(
        _ action: any ExecutableAction,
        for buttons: [ControllerButton],
        profile: Profile?,
        logType: InputEventType = .singlePress
    ) {
        let feedback = executeAction(action, profile: profile)
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
        profile: Profile?
    ) -> String {
        if let feedback = systemCommandHandler.executeIfPossible(action) {
            return feedback
        }
        if let feedback = macroHandler.executeIfPossible(action, profile: profile) {
            return feedback
        }
        return keyOrModifierHandler.execute(action)
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
