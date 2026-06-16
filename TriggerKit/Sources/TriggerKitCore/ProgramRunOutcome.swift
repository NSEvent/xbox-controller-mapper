import Foundation

/// Result of running an `AutomationProgram` on demand from the editor's Test
/// button. Lives in Core (not Runtime) so `TriggerKitUI` can surface a test
/// result without depending on the execution engine — each host maps its own
/// `TriggerExecutionResult` into this small shape.
public struct ProgramRunOutcome: Equatable, Sendable {
	public let succeeded: Bool
	public let message: String

	public init(succeeded: Bool, message: String) {
		self.succeeded = succeeded
		self.message = message
	}

	public static func success(_ message: String) -> ProgramRunOutcome {
		ProgramRunOutcome(succeeded: true, message: message)
	}

	public static func failure(_ message: String) -> ProgramRunOutcome {
		ProgramRunOutcome(succeeded: false, message: message)
	}
}
