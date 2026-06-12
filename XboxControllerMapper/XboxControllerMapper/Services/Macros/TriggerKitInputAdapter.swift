import Foundation
import CoreGraphics
import Carbon.HIToolbox
import TriggerKitCore
import TriggerKitRuntime

/// Bridges TriggerKit's `InputSimulating` protocol onto ControllerKeys'
/// `InputSimulatorProtocol`, so automation programs execute through the same
/// tuned key/mouse/media simulation (and the same mock seam in tests) as
/// direct button mappings.
///
/// The adapter reproduces the exact call sequences the pre-TriggerKit
/// MacroExecutor made: modifiers are held before key events and released
/// after, modifier key codes route through the modifier-hold path, and
/// synthetic marker key codes flow back through `pressKey`/`keyDown`, where
/// ControllerKeys dispatches them to mouse, scroll, and media handling.
final class TriggerKitInputAdapter: InputSimulating {
	/// Matches the pre-TriggerKit modifier-only press hold time
	/// (`Config.keyPressDuration`, microseconds).
	private static let modifierTapNanoseconds = UInt64(Config.keyPressDuration) * 1_000

	/// Typing pace when a `.type`-mode step carries no explicit pace.
	/// ControllerKeys-authored macros always set one; this covers programs
	/// authored by other TriggerKit hosts.
	private static let fallbackTypingCharactersPerMinute = 6000

	private let inputSimulator: InputSimulatorProtocol

	init(inputSimulator: InputSimulatorProtocol) {
		self.inputSimulator = inputSimulator
	}

	/// ControllerKeys manages Accessibility permission prompts itself;
	/// `InputSimulator.pressKey` re-checks before posting.
	var isInputPostingAvailable: Bool { true }

	func keyPress(_ stroke: KeyStroke) async {
		let keyCode = CGKeyCode(stroke.key.keyCode)
		if KeyCodeMapping.isModifierKey(keyCode) {
			// Modifier-only press: hold the combined set briefly, then release.
			let combined = combinedModifierFlags(carriedKey: keyCode, modifiers: stroke.modifiers)
			inputSimulator.holdModifiers(combined)
			try? await Task.sleep(nanoseconds: Self.modifierTapNanoseconds)
			inputSimulator.releaseModifiers(combined)
			return
		}
		inputSimulator.pressKey(keyCode, modifiers: MacroAutomationBridge.modifierFlags(for: stroke.modifiers))
	}

	func keyDown(_ event: KeyEvent) {
		let keyCode = CGKeyCode(event.key.keyCode)
		let flags = MacroAutomationBridge.modifierFlags(for: event.modifiers)
		if flags.hasAny {
			inputSimulator.holdModifiers(flags)
		}
		if KeyCodeMapping.isModifierKey(keyCode) {
			inputSimulator.holdModifierKey(keyCode)
		} else {
			inputSimulator.keyDown(keyCode, modifiers: flags.cgEventFlags)
		}
	}

	func keyUp(_ event: KeyEvent) {
		let keyCode = CGKeyCode(event.key.keyCode)
		let flags = MacroAutomationBridge.modifierFlags(for: event.modifiers)
		if KeyCodeMapping.isModifierKey(keyCode) {
			inputSimulator.releaseModifierKey(keyCode)
		} else {
			inputSimulator.keyUp(keyCode)
		}
		if flags.hasAny {
			inputSimulator.releaseModifiers(flags)
		}
	}

	func mouseClick(_ click: MouseClick) {
		let marker = MacroAutomationBridge.markerKeyCode(for: click.button)
		let flags = MacroAutomationBridge.modifierFlags(for: click.modifiers)
		for _ in 0..<max(1, click.clickCount) {
			inputSimulator.pressKey(marker, modifiers: flags)
		}
	}

	func mouseDown(_ event: MouseButtonEvent) {
		let flags = MacroAutomationBridge.modifierFlags(for: event.modifiers)
		if flags.hasAny {
			inputSimulator.holdModifiers(flags)
		}
		inputSimulator.keyDown(MacroAutomationBridge.markerKeyCode(for: event.button), modifiers: flags.cgEventFlags)
	}

	func mouseUp(_ event: MouseButtonEvent) {
		let flags = MacroAutomationBridge.modifierFlags(for: event.modifiers)
		inputSimulator.keyUp(MacroAutomationBridge.markerKeyCode(for: event.button))
		if flags.hasAny {
			inputSimulator.releaseModifiers(flags)
		}
	}

	func mouseMove(_ move: MouseMove) {
		inputSimulator.moveMouse(dx: CGFloat(move.deltaX), dy: CGFloat(move.deltaY))
	}

	func mouseScroll(_ scroll: MouseScroll) {
		// ControllerKeys macros express scrolls as canonical marker presses;
		// route through pressKey so scroll amount and feel match button
		// mappings exactly.
		guard let marker = MacroAutomationBridge.scrollMarkerKeyCode(for: scroll) else { return }
		inputSimulator.pressKey(marker, modifiers: ModifierFlags())
	}

	func typeText(_ step: TypeTextStep) async {
		let speed: Int
		switch step.mode {
		case .paste:
			speed = 0
		case .type:
			speed = step.charactersPerMinute ?? Self.fallbackTypingCharactersPerMinute
		}
		inputSimulator.typeText(step.text, speed: speed, pressEnter: step.pressReturn)
	}

	/// Rebuilds the full modifier set for a modifier-only stroke: the carried
	/// key's own modifier plus any additional stroke modifiers, preserving
	/// left/right side selection.
	private func combinedModifierFlags(carriedKey: CGKeyCode, modifiers: ModifierSet) -> ModifierFlags {
		var flags = MacroAutomationBridge.modifierFlags(for: modifiers)
		let side: ModifierSide? = Self.isRightSideModifierKey(carriedKey) ? .right : nil
		switch KeyCodeMapping.modifierFlag(for: carriedKey) {
		case .maskCommand:
			flags.command = true
			flags.commandSide = side
		case .maskAlternate:
			flags.option = true
			flags.optionSide = side
		case .maskShift:
			flags.shift = true
			flags.shiftSide = side
		case .maskControl:
			flags.control = true
			flags.controlSide = side
		default:
			break
		}
		return flags
	}

	private static func isRightSideModifierKey(_ keyCode: CGKeyCode) -> Bool {
		switch Int(keyCode) {
		case kVK_RightCommand, kVK_RightOption, kVK_RightShift, kVK_RightControl:
			return true
		default:
			return false
		}
	}
}
