import Foundation

public struct AutomationCapabilities: Codable, Equatable, Sendable {
	public var allowedStepKinds: Set<AutomationStep.Kind>

	public init(allowedStepKinds: Set<AutomationStep.Kind> = Set(AutomationStep.Kind.allCases)) {
		self.allowedStepKinds = allowedStepKinds
	}

	public static let all = AutomationCapabilities()

	public static let inputOnly = AutomationCapabilities(allowedStepKinds: [
		.keyPress,
		.keyDown,
		.keyUp,
		.mouseClick,
		.mouseDown,
		.mouseUp,
		.mouseMove,
		.mouseScroll,
		.delay,
		.typeText
	])

	public func allows(_ kind: AutomationStep.Kind) -> Bool {
		allowedStepKinds.contains(kind)
	}
}
