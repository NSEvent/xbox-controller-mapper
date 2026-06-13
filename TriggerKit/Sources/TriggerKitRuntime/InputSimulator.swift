import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation
import TriggerKitCore

public protocol InputSimulating: Sendable {
	var isInputPostingAvailable: Bool { get }
	func keyPress(_ stroke: KeyStroke) async
	func keyDown(_ event: KeyEvent)
	func keyUp(_ event: KeyEvent)
	func mouseClick(_ click: MouseClick)
	func mouseDown(_ event: MouseButtonEvent)
	func mouseUp(_ event: MouseButtonEvent)
	func mouseMove(_ move: MouseMove)
	func mouseScroll(_ scroll: MouseScroll)
	func typeText(_ step: TypeTextStep) async
}

public extension InputSimulating {
	var isInputPostingAvailable: Bool { true }
}

/// Posts synthetic input via CoreGraphics. Deliberately *not* `@MainActor`:
/// CGEvent posting works from any thread, and keeping it off the main actor
/// lets the executor run programs on a background task (matching the original
/// `Task.detached` macro path) without blocking UI. The two modifier-tracking
/// dictionaries are the only mutable state, so they are guarded by `stateLock`
/// to stay safe when a host fires concurrent programs against one instance.
public final class InputSimulator: InputSimulating, @unchecked Sendable {
	private let source = CGEventSource(stateID: .hidSystemState)
	private let stateLock = NSLock()
	private var activeKeyDownModifiers: [TriggerKey: ModifierSet] = [:]
	private var activeMouseDownModifiers: [MouseButton: ModifierSet] = [:]

	public init() {}

	public var isInputPostingAvailable: Bool {
		AXIsProcessTrusted()
	}

	public func keyPress(_ stroke: KeyStroke) async {
		if TriggerKey.isMediaOrSystemKeyCode(stroke.key.keyCode) {
			// Honor modifiers on media/system keys (e.g. a configured
			// Shift+BrightnessUp) — mirror the keyDown path, which posts them.
			let flags = InputEventMapper.eventFlags(for: stroke)
			postModifierKeys(stroke.modifiers, keyDown: true, flags: flags)
			await pressMediaKey(stroke.key)
			postModifierKeys(stroke.modifiers, keyDown: false)
			return
		}
		let modifiers = InputEventMapper.modifierKeyCodes(for: stroke.modifiers)
		let flags = InputEventMapper.eventFlags(for: stroke)
		for code in modifiers { postKey(code, keyDown: true, flags: flags) }
		postKey(CGKeyCode(stroke.key.keyCode), keyDown: true, flags: flags)
		postKey(CGKeyCode(stroke.key.keyCode), keyDown: false, flags: flags)
		for code in modifiers.reversed() { postKey(code, keyDown: false) }
	}

	public func keyDown(_ event: KeyEvent) {
		let flags = InputEventMapper.eventFlags(for: event.modifiers).union(InputEventMapper.specialKeyFlags(for: event.key))
		postModifierKeys(event.modifiers, keyDown: true, flags: flags)
		if TriggerKey.isMediaOrSystemKeyCode(event.key.keyCode) {
			postMediaKey(event.key, keyDown: true)
			rememberKeyDownModifiers(event)
			return
		}
		postKey(CGKeyCode(event.key.keyCode), keyDown: true, flags: flags)
		rememberKeyDownModifiers(event)
	}

	public func keyUp(_ event: KeyEvent) {
		let storedModifiers = forgetKeyDownModifiers(event)
		let modifiers = storedModifiers ?? event.modifiers
		let flags = InputEventMapper.eventFlags(for: modifiers).union(InputEventMapper.specialKeyFlags(for: event.key))
		if storedModifiers == nil {
			postModifierKeys(modifiers, keyDown: true, flags: flags)
		}
		if TriggerKey.isMediaOrSystemKeyCode(event.key.keyCode) {
			postMediaKey(event.key, keyDown: false)
			postModifierKeys(storedModifiers ?? modifiers, keyDown: false)
			return
		}
		postKey(CGKeyCode(event.key.keyCode), keyDown: false, flags: flags)
		postModifierKeys(storedModifiers ?? modifiers, keyDown: false)
	}

	public func mouseClick(_ click: MouseClick) {
		performWithModifiers(click.modifiers) { flags in
			for _ in 0..<max(1, click.clickCount) {
				postMouse(click.button, mouseDown: true, flags: flags)
				postMouse(click.button, mouseDown: false, flags: flags)
			}
		}
	}

	public func mouseDown(_ event: MouseButtonEvent) {
		let flags = InputEventMapper.eventFlags(for: event.modifiers)
		postModifierKeys(event.modifiers, keyDown: true, flags: flags)
		postMouse(event.button, mouseDown: true, flags: flags)
		if !event.modifiers.isEmpty {
			stateLock.lock()
			activeMouseDownModifiers[event.button] = event.modifiers
			stateLock.unlock()
		}
	}

	public func mouseUp(_ event: MouseButtonEvent) {
		stateLock.lock()
		let storedModifiers = activeMouseDownModifiers.removeValue(forKey: event.button)
		stateLock.unlock()
		let modifiers = storedModifiers ?? event.modifiers
		let flags = InputEventMapper.eventFlags(for: modifiers)
		if storedModifiers == nil {
			postModifierKeys(modifiers, keyDown: true, flags: flags)
		}
		postMouse(event.button, mouseDown: false, flags: flags)
		postModifierKeys(storedModifiers ?? modifiers, keyDown: false)
	}

	public func mouseMove(_ move: MouseMove) {
		guard let event = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: currentMouseLocation(), mouseButton: .left) else {
			return
		}
		let current = currentMouseLocation()
		event.location = CGPoint(x: current.x + move.deltaX, y: current.y + move.deltaY)
		event.post(tap: .cghidEventTap)
	}

	public func mouseScroll(_ scroll: MouseScroll) {
		let event = CGEvent(
			scrollWheelEvent2Source: source,
			units: .line,
			wheelCount: 2,
			wheel1: scroll.deltaY,
			wheel2: scroll.deltaX,
			wheel3: 0
		)
		event?.post(tap: .cghidEventTap)
	}

	public func typeText(_ step: TypeTextStep) async {
		switch step.mode {
		case .paste:
			await pasteText(step.text)
			await settleAfterShortcut()
		case .type:
			await typeUnicode(step.text, charactersPerMinute: step.charactersPerMinute)
		}
		if step.pressReturn {
			releaseAllModifiers()
			await settleAfterShortcut()
			await keyPress(KeyStroke(key: .return))
		}
	}

	private func rememberKeyDownModifiers(_ event: KeyEvent) {
		guard !event.modifiers.isEmpty else { return }
		stateLock.lock()
		activeKeyDownModifiers[event.key] = event.modifiers
		stateLock.unlock()
	}

	private func forgetKeyDownModifiers(_ event: KeyEvent) -> ModifierSet? {
		stateLock.lock()
		defer { stateLock.unlock() }
		return activeKeyDownModifiers.removeValue(forKey: event.key)
	}

	private func postKey(_ keyCode: CGKeyCode, keyDown: Bool, flags: CGEventFlags = []) {
		guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else {
			return
		}
		event.flags = flags
		event.post(tap: .cghidEventTap)
	}

	private func performWithModifiers(_ modifiers: ModifierSet, _ body: (CGEventFlags) -> Void) {
		let flags = InputEventMapper.eventFlags(for: modifiers)
		postModifierKeys(modifiers, keyDown: true, flags: flags)
		body(flags)
		postModifierKeys(modifiers, keyDown: false)
	}

	private func postModifierKeys(_ modifiers: ModifierSet, keyDown: Bool, flags: CGEventFlags = []) {
		let codes = InputEventMapper.modifierKeyCodes(for: modifiers)
		let orderedCodes = keyDown ? codes : Array(codes.reversed())
		for code in orderedCodes {
			postKey(code, keyDown: keyDown, flags: keyDown ? flags : [])
		}
	}

	private func releaseAllModifiers() {
		[
			kVK_Command,
			kVK_RightCommand,
			kVK_Option,
			kVK_RightOption,
			kVK_Control,
			kVK_RightControl,
			kVK_Shift,
			kVK_RightShift,
			kVK_Function
		].forEach { postKey(CGKeyCode($0), keyDown: false) }
	}

	private func settleAfterShortcut() async {
		try? await Task.sleep(nanoseconds: 120_000_000)
	}

	private func postMouse(_ button: MouseButton, mouseDown: Bool, flags: CGEventFlags = []) {
		let location = currentMouseLocation()
		let cgButton = InputEventMapper.cgButton(button)
		guard let event = CGEvent(
			mouseEventSource: source,
			mouseType: InputEventMapper.mouseEventType(button, mouseDown: mouseDown),
			mouseCursorPosition: location,
			mouseButton: cgButton
		) else {
			return
		}
		event.flags = flags
		event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(cgButton.rawValue))
		event.post(tap: .cghidEventTap)
	}

	private func pasteText(_ text: String) async {
		let pasteboard = NSPasteboard.general
		let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
		pasteboard.clearContents()
		pasteboard.setString(text, forType: .string)
		let temporaryChangeCount = pasteboard.changeCount
		// Restore in a defer: the awaits below are cancellation points, and if
		// the program is cancelled mid-paste the user's real clipboard must not
		// be left holding our injected text.
		defer { snapshot.restore(to: .general, ifChangeCountMatches: temporaryChangeCount) }
		await keyPress(KeyStroke(key: TriggerKey(id: "v", keyCode: 9, displayName: "V"), modifiers: ModifierSet(command: .any)))
		try? await Task.sleep(nanoseconds: 200_000_000)
	}

	private func typeUnicode(_ text: String, charactersPerMinute: Int? = nil) async {
		let interCharacterDelay: UInt64? = charactersPerMinute.flatMap { pace in
			pace > 0 ? UInt64((60.0 / Double(pace)) * 1_000_000_000) : nil
		}
		// Iterate grapheme clusters, not scalars: flag emoji (🇺🇸), skin-tone /
		// ZWJ sequences (👨‍👩‍👧), and base+combining-mark characters are built from
		// multiple scalars and must be posted as one event or they render broken.
		for character in text {
			let chars = Array(String(character).utf16)
			guard !chars.isEmpty,
			      let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
			      let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
				continue
			}
			chars.withUnsafeBufferPointer { buffer in
				guard let baseAddress = buffer.baseAddress else { return }
				down.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: baseAddress)
				up.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: baseAddress)
			}
			down.post(tap: .cghidEventTap)
			up.post(tap: .cghidEventTap)
			if let interCharacterDelay {
				try? await Task.sleep(nanoseconds: interCharacterDelay)
			}
		}
	}

	private func currentMouseLocation() -> CGPoint {
		NSEvent.mouseLocation
	}

	private func pressMediaKey(_ key: TriggerKey) async {
		postMediaKey(key, keyDown: true)
		try? await Task.sleep(nanoseconds: 50_000_000)
		postMediaKey(key, keyDown: false)
	}

	private func postMediaKey(_ key: TriggerKey, keyDown: Bool) {
		guard let keyType = InputEventMapper.nxKeyType(for: key) else {
			return
		}

		let keyCode = Int(keyType.rawValue)
		let flags = keyDown ? 0x0A : 0x0B
		let data1 = (keyCode << 16) | (flags << 8)
		let modifierFlags = NSEvent.ModifierFlags(rawValue: UInt(keyDown ? 0xA00 : 0xB00))

		let event = NSEvent.otherEvent(
			with: .systemDefined,
			location: .zero,
			modifierFlags: modifierFlags,
			timestamp: 0,
			windowNumber: 0,
			context: nil,
			subtype: 8,
			data1: data1,
			data2: -1
		)
		event?.cgEvent?.post(tap: .cghidEventTap)
	}
}

struct PasteboardSnapshot: @unchecked Sendable {
	private let items: [NSPasteboardItem]

	init(pasteboard: NSPasteboard) {
		items = pasteboard.pasteboardItems?.map { original in
			let copy = NSPasteboardItem()
			for type in original.types {
				if let data = original.data(forType: type) {
					copy.setData(data, forType: type)
				}
			}
			return copy
		} ?? []
	}

	func restore(to pasteboard: NSPasteboard, ifChangeCountMatches expectedChangeCount: Int? = nil) {
		if let expectedChangeCount, pasteboard.changeCount != expectedChangeCount {
			return
		}
		pasteboard.clearContents()
		if !items.isEmpty {
			pasteboard.writeObjects(items)
		}
	}
}
