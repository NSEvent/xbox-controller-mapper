import Foundation
import TriggerKitCore
import TriggerKitRuntime

/// Executes macro sequences by converting them to TriggerKit
/// `AutomationProgram`s and running them through TriggerKit's
/// `AutomationExecutor`.
///
/// Responsibilities are split the same way they were before TriggerKit:
/// - Input steps flow back through ControllerKeys' `InputSimulator` (via
///   `TriggerKitInputAdapter`), so key/mouse/media semantics — and the mock
///   seam in tests — are identical to direct button mappings.
/// - Shell, webhook, and OBS steps are overridden to run through
///   `SystemCommandExecutor`, keeping terminal-app selection, webhook retry
///   and feedback, and OBS keychain behavior.
/// - Delays, app launches, and URL opens use TriggerKit's native handling,
///   with the http(s)-only scheme allowlist matching the previous executor.
///
/// Execution policy matches the previous executor: macros run concurrently
/// (one macro never blocks another) and a failing step logs and continues.
class MacroExecutor: @unchecked Sendable {
	private let automationExecutor: AutomationExecutor
	private let executionContext: TriggerExecutionContext

	init(
		inputSimulator: InputSimulatorProtocol,
		systemCommandExecutor: SystemCommandExecutor
	) {
		self.automationExecutor = AutomationExecutor(
			input: TriggerKitInputAdapter(inputSimulator: inputSimulator)
		)
		self.executionContext = TriggerExecutionContext(
			logger: { message in
				NSLog("[Macro] %@", message)
			},
			policy: TriggerExecutionPolicy(
				concurrencyPolicy: .concurrent,
				validatesAccessibility: false,
				allowedURLSchemes: ["http", "https"],
				continuesOnStepFailure: true,
				cleanupHeldInputs: .always
			),
			stepOverride: { [systemCommandExecutor] step in
				Self.systemCommand(for: step).map { command in
					systemCommandExecutor.execute(command)
					return .success(step.displaySummary)
				}
			}
		)
	}

	func execute(_ macro: Macro) {
		execute(program: MacroAutomationBridge.automationProgram(for: macro))
	}

	/// Runs a TriggerKit program directly — the execution path for shared
	/// library macros (and their snapshots), which are already programs.
	func execute(program: AutomationProgram) {
		Task(priority: .userInitiated) { [automationExecutor, executionContext] in
			let result = await automationExecutor.execute(program, context: executionContext)
			if !result.isSuccess {
				NSLog("[Macro] '%@' failed: %@", program.name, result.message)
			}
		}
	}

	/// Maps the steps SystemCommandExecutor owns; returns nil for steps
	/// TriggerKit should execute natively.
	private static func systemCommand(for step: AutomationStep) -> SystemCommand? {
		switch step {
		case .shellCommand(let shell):
			return .shellCommand(command: shell.command, inTerminal: shell.runsInTerminal)
		case .webhook(let webhook):
			return .httpRequest(
				url: webhook.url,
				method: MacroAutomationBridge.httpMethod(for: webhook.method),
				headers: webhook.headers.isEmpty ? nil : webhook.headers,
				body: webhook.body
			)
		case .custom(let custom) where custom.namespace == MacroAutomationBridge.obsNamespace:
			guard let command = MacroAutomationBridge.obsCommand(fromPayload: custom.payload) else {
				NSLog("[Macro] Malformed OBS payload in custom step")
				return nil
			}
			return command
		default:
			return nil
		}
	}
}
