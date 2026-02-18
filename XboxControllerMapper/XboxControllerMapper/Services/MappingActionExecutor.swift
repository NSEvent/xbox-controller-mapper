import Foundation
import CoreGraphics

// MARK: - Mapping Action Strategy

private protocol MappingActionHandler {
    func canHandle(_ action: any ExecutableAction) -> Bool
    func execute(_ action: any ExecutableAction, button: ControllerButton, profile: Profile?) -> String
}

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

private struct SystemCommandActionHandler: MappingActionHandler {
    let systemCommandExecutor: SystemCommandExecutor

    func canHandle(_ action: any ExecutableAction) -> Bool {
        action.systemCommand != nil
    }

    func execute(_ action: any ExecutableAction, button: ControllerButton, profile: Profile?) -> String {
        guard let command = action.systemCommand else { return action.feedbackString }
        systemCommandExecutor.execute(command)
        return command.displayName
    }
}

private struct MacroActionHandler: MappingActionHandler {
    let inputSimulator: InputSimulatorProtocol

    func canHandle(_ action: any ExecutableAction) -> Bool {
        action.macroId != nil
    }

    func execute(_ action: any ExecutableAction, button: ControllerButton, profile: Profile?) -> String {
        guard let macroId = action.macroId else {
            return action.feedbackString
        }

        if let profile, let macro = profile.macros.first(where: { $0.id == macroId }) {
            inputSimulator.executeMacro(macro)
            return (action.hint?.isEmpty == false) ? action.hint! : macro.name
        }

        return (action.hint?.isEmpty == false) ? action.hint! : "Macro"
    }
}

private struct KeyOrModifierActionHandler: MappingActionHandler {
    let inputSimulator: InputSimulatorProtocol
    let tapModifierExecutor: TapModifierExecutor

    func canHandle(_ action: any ExecutableAction) -> Bool {
        true
    }

    func execute(_ action: any ExecutableAction, button: ControllerButton, profile: Profile?) -> String {
        if let keyCode = action.keyCode {
            inputSimulator.pressKey(keyCode, modifiers: action.modifiers.cgEventFlags)
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
    let systemCommandExecutor: SystemCommandExecutor
    private let actionHandlers: [any MappingActionHandler]

    init(
        inputSimulator: InputSimulatorProtocol,
        inputQueue: DispatchQueue,
        inputLogService: InputLogService?,
        profileManager: ProfileManager
    ) {
        self.inputLogService = inputLogService
        self.systemCommandExecutor = SystemCommandExecutor(profileManager: profileManager)

        let tapModifierExecutor = TapModifierExecutor(inputSimulator: inputSimulator, inputQueue: inputQueue)
        self.actionHandlers = [
            SystemCommandActionHandler(systemCommandExecutor: self.systemCommandExecutor),
            MacroActionHandler(inputSimulator: inputSimulator),
            KeyOrModifierActionHandler(inputSimulator: inputSimulator, tapModifierExecutor: tapModifierExecutor)
        ]
    }

    /// Executes any action mapping (key press, macro, or system command).
    func executeAction(
        _ action: any ExecutableAction,
        for button: ControllerButton,
        profile: Profile?,
        logType: InputEventType = .singlePress
    ) {
        for handler in actionHandlers where handler.canHandle(action) {
            let feedback = handler.execute(action, button: button, profile: profile)
            inputLogService?.log(buttons: [button], type: logType, action: feedback)
            return
        }

        inputLogService?.log(buttons: [button], type: logType, action: action.feedbackString)
    }
}
