import Foundation
import CoreGraphics
import TriggerKitCore

/// Converts ControllerKeys macros into TriggerKit `AutomationProgram`s.
///
/// `Macro`/`MacroStep` remain ControllerKeys' persisted and UI model; this
/// bridge translates them at execution time so macros run through TriggerKit's
/// `AutomationExecutor`. The conversion is total: every `MacroStep` maps to one
/// or more `AutomationStep`s.
///
/// Synthetic marker key codes (`KeyCodeMapping.isSpecialMarker`) translate to
/// semantic TriggerKit steps where one exists (mouse clicks, scrolls) so
/// converted programs stay meaningful to other TriggerKit hosts. Markers with
/// no TriggerKit equivalent (special actions like the on-screen keyboard, and
/// modified scrolls, whose modifiers `MouseScroll` cannot carry) pass through
/// as key strokes with the raw marker code, which `TriggerKitInputAdapter`
/// routes back into ControllerKeys' InputSimulator unchanged.
enum MacroAutomationBridge {

	/// Namespace for OBS WebSocket steps carried as TriggerKit custom steps.
	static let obsNamespace = "controllerkeys.obs-websocket"

	/// Payload schema for `obsNamespace` custom steps.
	///
	/// The payload may contain a plaintext password (resolved from the
	/// Keychain when the macro was decoded). Programs built by this bridge are
	/// transient execution artifacts; persistence stays on `MacroStep`, which
	/// re-encodes passwords as Keychain references.
	struct OBSPayload: Codable, Equatable {
		var url: String
		var password: String?
		var requestType: String
		var requestData: String?
	}

	// MARK: - Macro -> AutomationProgram

	static func automationProgram(for macro: Macro) -> AutomationProgram {
		AutomationProgram(
			id: macro.id,
			name: macro.name,
			steps: macro.steps.flatMap(automationSteps(for:))
		)
	}

	static func automationSteps(for step: MacroStep) -> [AutomationStep] {
		switch step {
		case .press(let mapping):
			return pressSteps(for: mapping)

		case .hold(let mapping, let duration):
			return holdSteps(for: mapping, duration: duration)

		case .delay(let duration):
			return [.delay(DelayStep(seconds: max(0, duration)))]

		case .typeText(let text, let speed, let pressEnter):
			let step = TypeTextStep(
				text: text,
				mode: speed <= 0 ? .paste : .type,
				pressReturn: pressEnter,
				charactersPerMinute: speed > 0 ? speed : nil
			)
			return [.typeText(step)]

		case .openApp(let bundleIdentifier, let newWindow):
			return [.openApp(OpenAppStep(bundleIdentifier: bundleIdentifier, openNewWindow: newWindow))]

		case .openLink(let url):
			return [.openURL(OpenURLStep(url: url))]

		case .shellCommand(let command, let inTerminal):
			return [.shellCommand(ShellCommandStep(command: command, runsInTerminal: inTerminal))]

		case .webhook(let url, let method, let headers, let body):
			let step = WebhookStep(
				url: url,
				method: webhookMethod(for: method),
				headers: headers ?? [:],
				body: body
			)
			return [.webhook(step)]

		case .obsWebSocket(let url, let password, let requestType, let requestData):
			let payload = OBSPayload(url: url, password: password, requestType: requestType, requestData: requestData)
			let json = (try? JSONEncoder().encode(payload)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
			return [.custom(CustomStep(
				namespace: obsNamespace,
				payload: json,
				displayName: "OBS: \(requestType)"
			))]
		}
	}

	private static func pressSteps(for mapping: KeyMapping) -> [AutomationStep] {
		guard let keyCode = mapping.keyCode else {
			guard let stroke = modifierOnlyStroke(for: mapping.modifiers) else { return [] }
			return [.keyPress(stroke)]
		}

		if KeyCodeMapping.isMouseButton(keyCode), let button = mouseButton(for: keyCode) {
			return [.mouseClick(MouseClick(button: button, modifiers: modifierSet(for: mapping.modifiers)))]
		}

		// Unmodified scrolls become semantic scroll steps; modified scrolls
		// (e.g. Ctrl+scroll zoom) pass through as marker key strokes because
		// MouseScroll cannot carry modifiers.
		if KeyCodeMapping.isScrollAction(keyCode), !mapping.modifiers.hasAny, let scroll = mouseScroll(for: keyCode) {
			return [.mouseScroll(scroll)]
		}

		return [.keyPress(KeyStroke(key: triggerKey(for: keyCode), modifiers: modifierSet(for: mapping.modifiers)))]
	}

	private static func holdSteps(for mapping: KeyMapping, duration: TimeInterval) -> [AutomationStep] {
		let delay = AutomationStep.delay(DelayStep(seconds: max(0, duration)))

		if let keyCode = mapping.keyCode, KeyCodeMapping.isMouseButton(keyCode), let button = mouseButton(for: keyCode) {
			let event = MouseButtonEvent(button: button, modifiers: modifierSet(for: mapping.modifiers))
			return [.mouseDown(event), delay, .mouseUp(event)]
		}

		let event: KeyEvent
		if let keyCode = mapping.keyCode {
			event = KeyEvent(key: triggerKey(for: keyCode), modifiers: modifierSet(for: mapping.modifiers))
		} else if let stroke = modifierOnlyStroke(for: mapping.modifiers) {
			event = KeyEvent(key: stroke.key, modifiers: stroke.modifiers)
		} else {
			return []
		}
		return [.keyDown(event), delay, .keyUp(event)]
	}

	// MARK: - Modifier conversion

	static func modifierSet(for flags: ModifierFlags) -> ModifierSet {
		ModifierSet(
			command: flags.command ? sidePreference(for: flags.commandSide) : nil,
			option: flags.option ? sidePreference(for: flags.optionSide) : nil,
			control: flags.control ? sidePreference(for: flags.controlSide) : nil,
			shift: flags.shift ? sidePreference(for: flags.shiftSide) : nil
		)
	}

	static func modifierFlags(for set: ModifierSet) -> ModifierFlags {
		ModifierFlags(
			command: set.command != nil,
			option: set.option != nil,
			shift: set.shift != nil,
			control: set.control != nil,
			commandSide: modifierSide(for: set.command),
			optionSide: modifierSide(for: set.option),
			shiftSide: modifierSide(for: set.shift),
			controlSide: modifierSide(for: set.control)
		)
	}

	private static func sidePreference(for side: ModifierSide?) -> ModifierSidePreference {
		switch side {
		case .left: return .left
		case .right: return .right
		case .none: return .any
		}
	}

	private static func modifierSide(for preference: ModifierSidePreference?) -> ModifierSide? {
		switch preference {
		case .left: return .left
		case .right: return .right
		case .any, .none: return nil
		}
	}

	/// A modifier-only mapping (e.g. "press ⌘⇧") carries one modifier as the
	/// stroke's key — the last in ControllerKeys' press order, so it lands on
	/// top of the others — and the rest as stroke modifiers.
	private static func modifierOnlyStroke(for flags: ModifierFlags) -> KeyStroke? {
		var remaining = flags
		let carried: TriggerKey
		if flags.control {
			carried = modifierTriggerKey(mask: .maskControl, side: flags.controlSide)
			remaining.control = false
		} else if flags.option {
			carried = modifierTriggerKey(mask: .maskAlternate, side: flags.optionSide)
			remaining.option = false
		} else if flags.shift {
			carried = modifierTriggerKey(mask: .maskShift, side: flags.shiftSide)
			remaining.shift = false
		} else if flags.command {
			carried = modifierTriggerKey(mask: .maskCommand, side: flags.commandSide)
			remaining.command = false
		} else {
			return nil
		}
		return KeyStroke(key: carried, modifiers: modifierSet(for: remaining))
	}

	private static func modifierTriggerKey(mask: CGEventFlags, side: ModifierSide?) -> TriggerKey {
		let flags = ModifierFlags(
			command: mask == .maskCommand,
			option: mask == .maskAlternate,
			shift: mask == .maskShift,
			control: mask == .maskControl,
			commandSide: side,
			optionSide: side,
			shiftSide: side,
			controlSide: side
		)
		let keyCode = flags.virtualKey(forMask: mask) ?? 0
		return triggerKey(for: keyCode)
	}

	// MARK: - Key and button conversion

	static func triggerKey(for keyCode: CGKeyCode) -> TriggerKey {
		if let catalogKey = TriggerKey.catalogKey(keyCode: UInt16(keyCode)) {
			return catalogKey
		}
		return TriggerKey(
			id: "ck-key-\(keyCode)",
			keyCode: UInt16(keyCode),
			displayName: KeyCodeMapping.displayName(for: keyCode)
		)
	}

	static func mouseButton(for keyCode: CGKeyCode) -> MouseButton? {
		switch keyCode {
		case KeyCodeMapping.mouseLeftClick: return .left
		case KeyCodeMapping.mouseRightClick: return .right
		case KeyCodeMapping.mouseMiddleClick: return .middle
		case KeyCodeMapping.mouseBackClick: return .back
		case KeyCodeMapping.mouseForwardClick: return .forward
		default: return nil
		}
	}

	static func markerKeyCode(for button: MouseButton) -> CGKeyCode {
		switch button {
		case .left: return KeyCodeMapping.mouseLeftClick
		case .right: return KeyCodeMapping.mouseRightClick
		case .middle: return KeyCodeMapping.mouseMiddleClick
		case .back: return KeyCodeMapping.mouseBackClick
		case .forward: return KeyCodeMapping.mouseForwardClick
		}
	}

	/// Canonical line deltas mirroring `KeyCodeMapping.scrollDelta` signs:
	/// up/left are positive, down/right negative.
	static func mouseScroll(for keyCode: CGKeyCode) -> MouseScroll? {
		switch keyCode {
		case KeyCodeMapping.scrollUp: return MouseScroll(deltaY: 3)
		case KeyCodeMapping.scrollDown: return MouseScroll(deltaY: -3)
		case KeyCodeMapping.scrollLeft: return MouseScroll(deltaX: 3)
		case KeyCodeMapping.scrollRight: return MouseScroll(deltaX: -3)
		default: return nil
		}
	}

	static func scrollMarkerKeyCode(for scroll: MouseScroll) -> CGKeyCode? {
		if abs(scroll.deltaY) >= abs(scroll.deltaX) {
			if scroll.deltaY > 0 { return KeyCodeMapping.scrollUp }
			if scroll.deltaY < 0 { return KeyCodeMapping.scrollDown }
		}
		if scroll.deltaX > 0 { return KeyCodeMapping.scrollLeft }
		if scroll.deltaX < 0 { return KeyCodeMapping.scrollRight }
		return nil
	}

	// MARK: - System command conversion

	static func webhookMethod(for method: HTTPMethod) -> WebhookMethod {
		WebhookMethod(rawValue: method.rawValue) ?? .post
	}

	static func httpMethod(for method: WebhookMethod) -> HTTPMethod {
		HTTPMethod(rawValue: method.rawValue) ?? .POST
	}

	static func obsCommand(fromPayload payload: String) -> SystemCommand? {
		guard let data = payload.data(using: .utf8),
		      let decoded = try? JSONDecoder().decode(OBSPayload.self, from: data) else {
			return nil
		}
		return .obsWebSocket(
			url: decoded.url,
			password: decoded.password,
			requestType: decoded.requestType,
			requestData: decoded.requestData
		)
	}
}
