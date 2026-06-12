public extension AutomationProgram {
	var requiresAccessibility: Bool {
		steps.contains { $0.requiresAccessibility }
	}
}

public extension AutomationStep {
	var requiresAccessibility: Bool {
		switch self {
		case .keyPress, .keyDown, .keyUp, .mouseClick, .mouseDown, .mouseUp, .mouseMove, .mouseScroll, .typeText:
			return true
		case .openApp(let step):
			return step.openNewWindow
		case .delay, .openURL, .shellCommand, .webhook, .custom:
			return false
		}
	}
}
