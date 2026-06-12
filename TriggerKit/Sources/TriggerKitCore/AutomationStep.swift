import Foundation

public enum AutomationStep: Equatable, Sendable {
	case keyPress(KeyStroke)
	case keyDown(KeyEvent)
	case keyUp(KeyEvent)
	case mouseClick(MouseClick)
	case mouseDown(MouseButtonEvent)
	case mouseUp(MouseButtonEvent)
	case mouseMove(MouseMove)
	case mouseScroll(MouseScroll)
	case delay(DelayStep)
	case typeText(TypeTextStep)
	case openApp(OpenAppStep)
	case openURL(OpenURLStep)
	case shellCommand(ShellCommandStep)
	case webhook(WebhookStep)
	case custom(CustomStep)
}

public extension AutomationStep {
	enum Kind: String, Codable, CaseIterable, Sendable {
		case keyPress
		case keyDown
		case keyUp
		case mouseClick
		case mouseDown
		case mouseUp
		case mouseMove
		case mouseScroll
		case delay
		case typeText
		case openApp
		case openURL
		case shellCommand
		case webhook
		case custom

		public var displayName: String {
			switch self {
			case .keyPress: return "Key Shortcut"
			case .keyDown: return "Key Down"
			case .keyUp: return "Key Up"
			case .mouseClick: return "Mouse Click"
			case .mouseDown: return "Mouse Down"
			case .mouseUp: return "Mouse Up"
			case .mouseMove: return "Mouse Move"
			case .mouseScroll: return "Mouse Scroll"
			case .delay: return "Delay"
			case .typeText: return "Type Text"
			case .openApp: return "Open App"
			case .openURL: return "Open URL"
			case .shellCommand: return "Shell Command"
			case .webhook: return "Webhook"
			case .custom: return "App Action"
			}
		}
	}

	var kind: Kind {
		switch self {
		case .keyPress: return .keyPress
		case .keyDown: return .keyDown
		case .keyUp: return .keyUp
		case .mouseClick: return .mouseClick
		case .mouseDown: return .mouseDown
		case .mouseUp: return .mouseUp
		case .mouseMove: return .mouseMove
		case .mouseScroll: return .mouseScroll
		case .delay: return .delay
		case .typeText: return .typeText
		case .openApp: return .openApp
		case .openURL: return .openURL
		case .shellCommand: return .shellCommand
		case .webhook: return .webhook
		case .custom: return .custom
		}
	}

	var displaySummary: String {
		switch self {
		case .keyPress(let step):
			return step.displaySummary
		case .keyDown(let step):
			return "Hold \(step.displaySummary)"
		case .keyUp(let step):
			return "Release \(step.displaySummary)"
		case .mouseClick(let step):
			return step.displaySummary
		case .mouseDown(let step):
			return "Mouse down \(step.displaySummary)"
		case .mouseUp(let step):
			return "Mouse up \(step.displaySummary)"
		case .mouseMove(let step):
			return "Move mouse \(Int(step.deltaX)), \(Int(step.deltaY))"
		case .mouseScroll(let step):
			return step.displaySummary
		case .delay(let step):
			return "Wait \(step.displayDuration)"
		case .typeText(let step):
			return step.displaySummary
		case .openApp(let step):
			return "Open \(step.bundleIdentifier)"
		case .openURL(let step):
			return "Open \(step.url)"
		case .shellCommand(let step):
			return step.displaySummary
		case .webhook(let step):
			return step.displaySummary
		case .custom(let step):
			return step.displaySummary
		}
	}

	static func defaultValue(for kind: Kind) -> AutomationStep {
		switch kind {
		case .keyPress:
			return .keyPress(KeyStroke(key: .return))
		case .keyDown:
			return .keyDown(KeyEvent(key: .return))
		case .keyUp:
			return .keyUp(KeyEvent(key: .return))
		case .mouseClick:
			return .mouseClick(MouseClick(button: .left))
		case .mouseDown:
			return .mouseDown(MouseButtonEvent(button: .left))
		case .mouseUp:
			return .mouseUp(MouseButtonEvent(button: .left))
		case .mouseMove:
			return .mouseMove(MouseMove(deltaX: 0, deltaY: 0))
		case .mouseScroll:
			return .mouseScroll(MouseScroll(deltaY: -4))
		case .delay:
			return .delay(DelayStep(seconds: 1))
		case .typeText:
			return .typeText(TypeTextStep(text: "", mode: .paste, pressReturn: true))
		case .openApp:
			return .openApp(OpenAppStep(bundleIdentifier: ""))
		case .openURL:
			return .openURL(OpenURLStep(url: ""))
		case .shellCommand:
			return .shellCommand(ShellCommandStep(command: ""))
		case .webhook:
			return .webhook(WebhookStep(url: ""))
		case .custom:
			return .custom(CustomStep(namespace: ""))
		}
	}
}

extension AutomationStep: Codable {
	private enum CodingKeys: String, CodingKey {
		case kind
		case keyStroke
		case keyEvent
		case mouseClick
		case mouseButton
		case mouseMove
		case mouseScroll
		case delay
		case typeText
		case openApp
		case openURL
		case shellCommand
		case webhook
		case custom
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let kind = try container.decode(Kind.self, forKey: .kind)
		switch kind {
		case .keyPress:
			self = .keyPress(try container.decode(KeyStroke.self, forKey: .keyStroke))
		case .keyDown:
			self = .keyDown(try container.decode(KeyEvent.self, forKey: .keyEvent))
		case .keyUp:
			self = .keyUp(try container.decode(KeyEvent.self, forKey: .keyEvent))
		case .mouseClick:
			self = .mouseClick(try container.decode(MouseClick.self, forKey: .mouseClick))
		case .mouseDown:
			self = .mouseDown(try container.decode(MouseButtonEvent.self, forKey: .mouseButton))
		case .mouseUp:
			self = .mouseUp(try container.decode(MouseButtonEvent.self, forKey: .mouseButton))
		case .mouseMove:
			self = .mouseMove(try container.decode(MouseMove.self, forKey: .mouseMove))
		case .mouseScroll:
			self = .mouseScroll(try container.decode(MouseScroll.self, forKey: .mouseScroll))
		case .delay:
			self = .delay(try container.decode(DelayStep.self, forKey: .delay))
		case .typeText:
			self = .typeText(try container.decode(TypeTextStep.self, forKey: .typeText))
		case .openApp:
			self = .openApp(try container.decode(OpenAppStep.self, forKey: .openApp))
		case .openURL:
			self = .openURL(try container.decode(OpenURLStep.self, forKey: .openURL))
		case .shellCommand:
			self = .shellCommand(try container.decode(ShellCommandStep.self, forKey: .shellCommand))
		case .webhook:
			self = .webhook(try container.decode(WebhookStep.self, forKey: .webhook))
		case .custom:
			self = .custom(try container.decode(CustomStep.self, forKey: .custom))
		}
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(kind, forKey: .kind)
		switch self {
		case .keyPress(let step):
			try container.encode(step, forKey: .keyStroke)
		case .keyDown(let step), .keyUp(let step):
			try container.encode(step, forKey: .keyEvent)
		case .mouseClick(let step):
			try container.encode(step, forKey: .mouseClick)
		case .mouseDown(let step), .mouseUp(let step):
			try container.encode(step, forKey: .mouseButton)
		case .mouseMove(let step):
			try container.encode(step, forKey: .mouseMove)
		case .mouseScroll(let step):
			try container.encode(step, forKey: .mouseScroll)
		case .delay(let step):
			try container.encode(step, forKey: .delay)
		case .typeText(let step):
			try container.encode(step, forKey: .typeText)
		case .openApp(let step):
			try container.encode(step, forKey: .openApp)
		case .openURL(let step):
			try container.encode(step, forKey: .openURL)
		case .shellCommand(let step):
			try container.encode(step, forKey: .shellCommand)
		case .webhook(let step):
			try container.encode(step, forKey: .webhook)
		case .custom(let step):
			try container.encode(step, forKey: .custom)
		}
	}
}
