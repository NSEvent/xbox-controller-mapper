import AppKit
import Carbon.HIToolbox
import TriggerKitCore

struct InputEventMapper {
	enum NXKeyType: UInt32 {
		case soundUp = 0
		case soundDown = 1
		case brightnessUp = 2
		case brightnessDown = 3
		case mute = 7
		case play = 16
		case next = 17
		case previous = 18
		case fast = 19
		case rewind = 20
	}

	static func modifierKeyCodes(for modifiers: ModifierSet) -> [CGKeyCode] {
		var codes: [CGKeyCode] = []
		appendModifier(modifiers.command, left: kVK_Command, right: kVK_RightCommand, to: &codes)
		appendModifier(modifiers.option, left: kVK_Option, right: kVK_RightOption, to: &codes)
		appendModifier(modifiers.control, left: kVK_Control, right: kVK_RightControl, to: &codes)
		appendModifier(modifiers.shift, left: kVK_Shift, right: kVK_RightShift, to: &codes)
		if modifiers.function { codes.append(CGKeyCode(kVK_Function)) }
		return codes
	}

	static func eventFlags(for modifiers: ModifierSet) -> CGEventFlags {
		var flags: CGEventFlags = []
		if modifiers.command != nil { flags.insert(.maskCommand) }
		if modifiers.option != nil { flags.insert(.maskAlternate) }
		if modifiers.control != nil { flags.insert(.maskControl) }
		if modifiers.shift != nil { flags.insert(.maskShift) }
		if modifiers.function { flags.insert(.maskSecondaryFn) }
		return flags
	}

	static func eventFlags(for stroke: KeyStroke) -> CGEventFlags {
		eventFlags(for: stroke.modifiers).union(specialKeyFlags(for: stroke.key))
	}

	static func specialKeyFlags(for key: TriggerKey) -> CGEventFlags {
		let keyCode = Int(key.keyCode)
		var flags: CGEventFlags = []
		if [
			kVK_LeftArrow,
			kVK_RightArrow,
			kVK_DownArrow,
			kVK_UpArrow,
			kVK_Home,
			kVK_End,
			kVK_PageUp,
			kVK_PageDown,
			kVK_ForwardDelete,
			kVK_Help
		].contains(keyCode) {
			flags.insert(.maskNumericPad)
		}
		if [
			kVK_F1,
			kVK_F2,
			kVK_F3,
			kVK_F4,
			kVK_F5,
			kVK_F6,
			kVK_F7,
			kVK_F8,
			kVK_F9,
			kVK_F10,
			kVK_F11,
			kVK_F12,
			kVK_F13,
			kVK_F14,
			kVK_F15,
			kVK_F16,
			kVK_F17,
			kVK_F18,
			kVK_F19,
			kVK_F20,
			kVK_Home,
			kVK_End,
			kVK_PageUp,
			kVK_PageDown,
			kVK_ForwardDelete,
			kVK_Help,
			kVK_LeftArrow,
			kVK_RightArrow,
			kVK_DownArrow,
			kVK_UpArrow
		].contains(keyCode) {
			flags.insert(.maskSecondaryFn)
		}
		if key.id.hasPrefix("keypad-") {
			flags.insert(.maskNumericPad)
		}
		return flags
	}

	static func nxKeyType(for key: TriggerKey) -> NXKeyType? {
		switch key.keyCode {
		case TriggerKey.mediaPlayPause.keyCode: return .play
		case TriggerKey.mediaNext.keyCode: return .next
		case TriggerKey.mediaPrevious.keyCode: return .previous
		case TriggerKey.mediaFastForward.keyCode: return .fast
		case TriggerKey.mediaRewind.keyCode: return .rewind
		case TriggerKey.volumeUp.keyCode: return .soundUp
		case TriggerKey.volumeDown.keyCode: return .soundDown
		case TriggerKey.volumeMute.keyCode: return .mute
		case TriggerKey.brightnessUp.keyCode: return .brightnessUp
		case TriggerKey.brightnessDown.keyCode: return .brightnessDown
		default: return nil
		}
	}

	static func cgButton(_ button: MouseButton) -> CGMouseButton {
		switch button {
		case .left: return .left
		case .right: return .right
		case .middle: return .center
		case .back: return CGMouseButton(rawValue: 3) ?? .center
		case .forward: return CGMouseButton(rawValue: 4) ?? .center
		}
	}

	static func mouseEventType(_ button: MouseButton, mouseDown: Bool) -> CGEventType {
		switch button {
		case .left:
			return mouseDown ? .leftMouseDown : .leftMouseUp
		case .right:
			return mouseDown ? .rightMouseDown : .rightMouseUp
		case .middle, .back, .forward:
			return mouseDown ? .otherMouseDown : .otherMouseUp
		}
	}

	private static func appendModifier(_ side: ModifierSidePreference?, left: Int, right: Int, to codes: inout [CGKeyCode]) {
		guard let side else { return }
		switch side {
		case .any, .left:
			codes.append(CGKeyCode(left))
		case .right:
			codes.append(CGKeyCode(right))
		}
	}
}
