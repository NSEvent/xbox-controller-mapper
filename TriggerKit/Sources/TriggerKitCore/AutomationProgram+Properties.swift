public extension AutomationProgram {
	var requiresAccessibility: Bool {
		steps.contains { $0.traits.requiresAccessibility }
	}
}

public extension AutomationStep {
	var requiresAccessibility: Bool {
		traits.requiresAccessibility
	}
}
