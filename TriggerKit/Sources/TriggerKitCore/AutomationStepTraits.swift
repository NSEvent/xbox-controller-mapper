import Foundation

public struct AutomationStepTraits: Codable, Equatable, Sendable {
	public var requiresAccessibility: Bool
	public var opensNetwork: Bool
	public var runsProcess: Bool
	public var modifiesClipboard: Bool
	public var changesSystemState: Bool
	public var needsAppleEvents: Bool

	public init(
		requiresAccessibility: Bool = false,
		opensNetwork: Bool = false,
		runsProcess: Bool = false,
		modifiesClipboard: Bool = false,
		changesSystemState: Bool = false,
		needsAppleEvents: Bool = false
	) {
		self.requiresAccessibility = requiresAccessibility
		self.opensNetwork = opensNetwork
		self.runsProcess = runsProcess
		self.modifiesClipboard = modifiesClipboard
		self.changesSystemState = changesSystemState
		self.needsAppleEvents = needsAppleEvents
	}
}

public extension AutomationStep.Kind {
	/// Conservative static traits for this step kind. Use `AutomationStep.traits`
	/// when an individual payload can narrow or widen the answer.
	var traits: AutomationStepTraits {
		switch self {
		case .keyPress, .keyDown, .keyUp, .mouseClick, .mouseDown, .mouseUp, .mouseMove, .mouseScroll:
			return AutomationStepTraits(requiresAccessibility: true)
		case .typeText:
			return AutomationStepTraits(requiresAccessibility: true, modifiesClipboard: true)
		case .openApp:
			return AutomationStepTraits(changesSystemState: true)
		case .openURL:
			return AutomationStepTraits(opensNetwork: true, changesSystemState: true)
		case .shellCommand:
			return AutomationStepTraits(runsProcess: true, changesSystemState: true)
		case .webhook:
			return AutomationStepTraits(opensNetwork: true)
		case .clipboard:
			return AutomationStepTraits(modifiesClipboard: true)
		case .systemSetting:
			return AutomationStepTraits(runsProcess: true, changesSystemState: true, needsAppleEvents: true)
		case .delay, .condition, .custom:
			return AutomationStepTraits()
		}
	}
}

public extension AutomationStep {
	var traits: AutomationStepTraits {
		switch self {
		case .keyPress, .keyDown, .keyUp, .mouseClick, .mouseDown, .mouseUp, .mouseMove, .mouseScroll:
			return AutomationStepTraits(requiresAccessibility: true)
		case .typeText(let step):
			return AutomationStepTraits(
				requiresAccessibility: true,
				modifiesClipboard: step.mode == .paste
			)
		case .openApp(let step):
			return AutomationStepTraits(
				requiresAccessibility: step.openNewWindow,
				changesSystemState: true
			)
		case .openURL(let step):
			return AutomationStepTraits(
				opensNetwork: step.normalizedNetworkURL != nil,
				changesSystemState: true
			)
		case .shellCommand:
			return AutomationStepTraits(runsProcess: true, changesSystemState: true)
		case .webhook:
			return AutomationStepTraits(opensNetwork: true)
		case .clipboard:
			return AutomationStepTraits(modifiesClipboard: true)
		case .systemSetting(let step):
			return AutomationStepTraits(
				runsProcess: true,
				changesSystemState: true,
				needsAppleEvents: step.action == .toggleDarkMode
			)
		case .delay, .condition, .custom:
			return AutomationStepTraits()
		}
	}
}

private extension OpenURLStep {
	var normalizedNetworkURL: URL? {
		let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return nil }
		let resolved = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
		guard let url = URL(string: resolved),
			  let scheme = url.scheme?.lowercased(),
			  ["http", "https"].contains(scheme) else {
			return nil
		}
		return url
	}
}
