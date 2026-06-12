import Carbon.HIToolbox
import Foundation

public struct TriggerKeyGroup: Identifiable, Equatable, Sendable {
	public var id: String { title }
	public var title: String
	public var keys: [TriggerKey]

	public init(title: String, keys: [TriggerKey]) {
		self.title = title
		self.keys = keys
	}
}

public extension TriggerKey {
	static let forwardDelete = TriggerKey(id: "forward-delete", keyCode: UInt16(kVK_ForwardDelete), displayName: "Forward Delete")
	static let help = TriggerKey(id: "help", keyCode: UInt16(kVK_Help), displayName: "Help")
	static let capsLock = TriggerKey(id: "caps-lock", keyCode: UInt16(kVK_CapsLock), displayName: "Caps Lock")
	static let function = TriggerKey(id: "function", keyCode: UInt16(kVK_Function), displayName: "Fn")

	static let mediaPlayPause = TriggerKey(id: "media-play-pause", keyCode: 0xF020, displayName: "Play/Pause")
	static let mediaNext = TriggerKey(id: "media-next", keyCode: 0xF021, displayName: "Next Track")
	static let mediaPrevious = TriggerKey(id: "media-previous", keyCode: 0xF022, displayName: "Previous Track")
	static let mediaFastForward = TriggerKey(id: "media-fast-forward", keyCode: 0xF023, displayName: "Fast Forward")
	static let mediaRewind = TriggerKey(id: "media-rewind", keyCode: 0xF024, displayName: "Rewind")
	static let volumeUp = TriggerKey(id: "volume-up", keyCode: 0xF030, displayName: "Volume Up")
	static let volumeDown = TriggerKey(id: "volume-down", keyCode: 0xF031, displayName: "Volume Down")
	static let volumeMute = TriggerKey(id: "volume-mute", keyCode: 0xF032, displayName: "Mute")
	static let brightnessUp = TriggerKey(id: "brightness-up", keyCode: 0xF040, displayName: "Brightness Up")
	static let brightnessDown = TriggerKey(id: "brightness-down", keyCode: 0xF041, displayName: "Brightness Down")

	static var catalogGroups: [TriggerKeyGroup] {
		[
			TriggerKeyGroup(title: "Common", keys: commonKeys),
			TriggerKeyGroup(title: "Letters", keys: letterKeys),
			TriggerKeyGroup(title: "Numbers", keys: numberKeys),
			TriggerKeyGroup(title: "Symbols", keys: symbolKeys),
			TriggerKeyGroup(title: "Navigation", keys: navigationKeys),
			TriggerKeyGroup(title: "Function", keys: functionKeys),
			TriggerKeyGroup(title: "Keypad", keys: keypadKeys),
			TriggerKeyGroup(title: "Modifiers", keys: modifierKeys),
			TriggerKeyGroup(title: "Media", keys: mediaKeys),
			TriggerKeyGroup(title: "System", keys: systemKeys)
		]
	}

	static var allCatalogKeys: [TriggerKey] {
		catalogGroups.flatMap(\.keys)
	}

	static func catalogKey(keyCode: UInt16) -> TriggerKey? {
		allCatalogKeys.first { $0.keyCode == keyCode }
	}

	static func isMediaOrSystemKeyCode(_ keyCode: UInt16) -> Bool {
		(0xF020...0xF024).contains(keyCode) ||
			(0xF030...0xF032).contains(keyCode) ||
			(0xF040...0xF041).contains(keyCode)
	}

	private static var commonKeys: [TriggerKey] {
		[
			.escape,
			.tab,
			.return,
			.space,
			.delete,
			.forwardDelete
		]
	}

	private static var letterKeys: [TriggerKey] {
		[
			key("A", kVK_ANSI_A), key("B", kVK_ANSI_B), key("C", kVK_ANSI_C), key("D", kVK_ANSI_D),
			key("E", kVK_ANSI_E), key("F", kVK_ANSI_F), key("G", kVK_ANSI_G), key("H", kVK_ANSI_H),
			key("I", kVK_ANSI_I), key("J", kVK_ANSI_J), key("K", kVK_ANSI_K), key("L", kVK_ANSI_L),
			key("M", kVK_ANSI_M), key("N", kVK_ANSI_N), key("O", kVK_ANSI_O), key("P", kVK_ANSI_P),
			key("Q", kVK_ANSI_Q), key("R", kVK_ANSI_R), key("S", kVK_ANSI_S), key("T", kVK_ANSI_T),
			key("U", kVK_ANSI_U), key("V", kVK_ANSI_V), key("W", kVK_ANSI_W), key("X", kVK_ANSI_X),
			key("Y", kVK_ANSI_Y), key("Z", kVK_ANSI_Z)
		]
	}

	private static var numberKeys: [TriggerKey] {
		[
			key("0", kVK_ANSI_0), key("1", kVK_ANSI_1), key("2", kVK_ANSI_2), key("3", kVK_ANSI_3),
			key("4", kVK_ANSI_4), key("5", kVK_ANSI_5), key("6", kVK_ANSI_6), key("7", kVK_ANSI_7),
			key("8", kVK_ANSI_8), key("9", kVK_ANSI_9)
		]
	}

	private static var symbolKeys: [TriggerKey] {
		[
			key("[", kVK_ANSI_LeftBracket, id: "left-bracket"),
			key("]", kVK_ANSI_RightBracket, id: "right-bracket"),
			key(";", kVK_ANSI_Semicolon, id: "semicolon"),
			key("'", kVK_ANSI_Quote, id: "quote"),
			key(",", kVK_ANSI_Comma, id: "comma"),
			key(".", kVK_ANSI_Period, id: "period"),
			key("/", kVK_ANSI_Slash, id: "slash"),
			key("\\", kVK_ANSI_Backslash, id: "backslash"),
			key("-", kVK_ANSI_Minus, id: "minus"),
			key("=", kVK_ANSI_Equal, id: "equal"),
			key("`", kVK_ANSI_Grave, id: "grave")
		]
	}

	private static var navigationKeys: [TriggerKey] {
		[
			TriggerKey(id: "left", keyCode: UInt16(kVK_LeftArrow), displayName: "Left Arrow"),
			TriggerKey(id: "right", keyCode: UInt16(kVK_RightArrow), displayName: "Right Arrow"),
			TriggerKey(id: "up", keyCode: UInt16(kVK_UpArrow), displayName: "Up Arrow"),
			TriggerKey(id: "down", keyCode: UInt16(kVK_DownArrow), displayName: "Down Arrow"),
			TriggerKey(id: "home", keyCode: UInt16(kVK_Home), displayName: "Home"),
			TriggerKey(id: "end", keyCode: UInt16(kVK_End), displayName: "End"),
			TriggerKey(id: "page-up", keyCode: UInt16(kVK_PageUp), displayName: "Page Up"),
			TriggerKey(id: "page-down", keyCode: UInt16(kVK_PageDown), displayName: "Page Down"),
			.help
		]
	}

	private static var functionKeys: [TriggerKey] {
		let codes = [
			kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
			kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20
		]
		return codes.enumerated().map { index, code in
			TriggerKey(id: "f\(index + 1)", keyCode: UInt16(code), displayName: "F\(index + 1)")
		}
	}

	private static var keypadKeys: [TriggerKey] {
		[
			key("Keypad 0", kVK_ANSI_Keypad0, id: "keypad-0"),
			key("Keypad 1", kVK_ANSI_Keypad1, id: "keypad-1"),
			key("Keypad 2", kVK_ANSI_Keypad2, id: "keypad-2"),
			key("Keypad 3", kVK_ANSI_Keypad3, id: "keypad-3"),
			key("Keypad 4", kVK_ANSI_Keypad4, id: "keypad-4"),
			key("Keypad 5", kVK_ANSI_Keypad5, id: "keypad-5"),
			key("Keypad 6", kVK_ANSI_Keypad6, id: "keypad-6"),
			key("Keypad 7", kVK_ANSI_Keypad7, id: "keypad-7"),
			key("Keypad 8", kVK_ANSI_Keypad8, id: "keypad-8"),
			key("Keypad 9", kVK_ANSI_Keypad9, id: "keypad-9"),
			key("Keypad .", kVK_ANSI_KeypadDecimal, id: "keypad-decimal"),
			key("Keypad *", kVK_ANSI_KeypadMultiply, id: "keypad-multiply"),
			key("Keypad +", kVK_ANSI_KeypadPlus, id: "keypad-plus"),
			key("Keypad /", kVK_ANSI_KeypadDivide, id: "keypad-divide"),
			key("Keypad -", kVK_ANSI_KeypadMinus, id: "keypad-minus"),
			key("Keypad =", kVK_ANSI_KeypadEquals, id: "keypad-equals"),
			key("Keypad Enter", kVK_ANSI_KeypadEnter, id: "keypad-enter"),
			key("Keypad Clear", kVK_ANSI_KeypadClear, id: "keypad-clear")
		]
	}

	private static var modifierKeys: [TriggerKey] {
		[
			TriggerKey(id: "left-command", keyCode: UInt16(kVK_Command), displayName: "Left Command"),
			TriggerKey(id: "right-command", keyCode: UInt16(kVK_RightCommand), displayName: "Right Command"),
			TriggerKey(id: "left-option", keyCode: UInt16(kVK_Option), displayName: "Left Option"),
			TriggerKey(id: "right-option", keyCode: UInt16(kVK_RightOption), displayName: "Right Option"),
			TriggerKey(id: "left-shift", keyCode: UInt16(kVK_Shift), displayName: "Left Shift"),
			TriggerKey(id: "right-shift", keyCode: UInt16(kVK_RightShift), displayName: "Right Shift"),
			TriggerKey(id: "left-control", keyCode: UInt16(kVK_Control), displayName: "Left Control"),
			TriggerKey(id: "right-control", keyCode: UInt16(kVK_RightControl), displayName: "Right Control"),
			.capsLock,
			.function
		]
	}

	private static var mediaKeys: [TriggerKey] {
		[
			.mediaPrevious,
			.mediaPlayPause,
			.mediaNext,
			.mediaFastForward,
			.mediaRewind
		]
	}

	private static var systemKeys: [TriggerKey] {
		[
			.volumeMute,
			.volumeDown,
			.volumeUp,
			.brightnessDown,
			.brightnessUp
		]
	}

	private static func key(_ label: String, _ keyCode: Int, id: String? = nil) -> TriggerKey {
		TriggerKey(id: id ?? label.lowercased(), keyCode: UInt16(keyCode), displayName: label)
	}
}
