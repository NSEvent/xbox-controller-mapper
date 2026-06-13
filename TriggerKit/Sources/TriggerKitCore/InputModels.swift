import Foundation

public enum ModifierSidePreference: String, Codable, CaseIterable, Sendable {
	case any
	case left
	case right

	public var displayPrefix: String {
		switch self {
		case .any: return ""
		case .left: return "L"
		case .right: return "R"
		}
	}
}

public struct ModifierSet: Codable, Equatable, Sendable {
	public var command: ModifierSidePreference?
	public var option: ModifierSidePreference?
	public var control: ModifierSidePreference?
	public var shift: ModifierSidePreference?
	public var function: Bool

	public init(
		command: ModifierSidePreference? = nil,
		option: ModifierSidePreference? = nil,
		control: ModifierSidePreference? = nil,
		shift: ModifierSidePreference? = nil,
		function: Bool = false
	) {
		self.command = command
		self.option = option
		self.control = control
		self.shift = shift
		self.function = function
	}

	public var isEmpty: Bool {
		command == nil && option == nil && control == nil && shift == nil && !function
	}

	public var displayString: String {
		var parts: [String] = []
		append(command, label: "Cmd", to: &parts)
		append(option, label: "Opt", to: &parts)
		append(control, label: "Ctrl", to: &parts)
		append(shift, label: "Shift", to: &parts)
		if function { parts.append("Fn") }
		return parts.joined(separator: "+")
	}

	private func append(_ side: ModifierSidePreference?, label: String, to parts: inout [String]) {
		guard let side else { return }
		parts.append("\(side.displayPrefix)\(label)")
	}
}

public struct TriggerKey: Codable, Equatable, Hashable, Sendable {
	public var id: String
	public var keyCode: UInt16
	public var displayName: String

	public init(id: String, keyCode: UInt16, displayName: String) {
		self.id = id
		self.keyCode = keyCode
		self.displayName = displayName
	}
}

public extension TriggerKey {
	static let `return` = TriggerKey(id: "return", keyCode: 36, displayName: "Return")
	static let tab = TriggerKey(id: "tab", keyCode: 48, displayName: "Tab")
	static let space = TriggerKey(id: "space", keyCode: 49, displayName: "Space")
	static let escape = TriggerKey(id: "escape", keyCode: 53, displayName: "Escape")
	static let delete = TriggerKey(id: "delete", keyCode: 51, displayName: "Delete")
}

public struct KeyStroke: Codable, Equatable, Sendable {
	public var key: TriggerKey
	public var modifiers: ModifierSet

	public init(key: TriggerKey, modifiers: ModifierSet = ModifierSet()) {
		self.key = key
		self.modifiers = modifiers
	}

	public var displaySummary: String {
		if modifiers.isEmpty { return key.displayName }
		return "\(modifiers.displayString)+\(key.displayName)"
	}
}

public struct KeyEvent: Codable, Equatable, Sendable {
	public var key: TriggerKey
	public var modifiers: ModifierSet

	public init(key: TriggerKey, modifiers: ModifierSet = ModifierSet()) {
		self.key = key
		self.modifiers = modifiers
	}

	public var displaySummary: String {
		if modifiers.isEmpty { return key.displayName }
		return "\(modifiers.displayString)+\(key.displayName)"
	}

	private enum CodingKeys: String, CodingKey {
		case key
		case modifiers
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		self.init(
			key: try container.decode(TriggerKey.self, forKey: .key),
			modifiers: try container.decodeIfPresent(ModifierSet.self, forKey: .modifiers) ?? ModifierSet()
		)
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(key, forKey: .key)
		try container.encode(modifiers, forKey: .modifiers)
	}
}

public enum MouseButton: String, Codable, CaseIterable, Hashable, Sendable {
	case left
	case right
	case middle
	case back
	case forward

	public var displayName: String {
		switch self {
		case .left: return "Left"
		case .right: return "Right"
		case .middle: return "Middle"
		case .back: return "Back"
		case .forward: return "Forward"
		}
	}
}

public struct MouseButtonEvent: Codable, Equatable, Sendable {
	public var button: MouseButton
	public var modifiers: ModifierSet

	public init(button: MouseButton, modifiers: ModifierSet = ModifierSet()) {
		self.button = button
		self.modifiers = modifiers
	}

	public var displaySummary: String {
		if modifiers.isEmpty { return button.displayName }
		return "\(modifiers.displayString)+\(button.displayName)"
	}

	private enum CodingKeys: String, CodingKey {
		case button
		case modifiers
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		self.init(
			button: try container.decode(MouseButton.self, forKey: .button),
			modifiers: try container.decodeIfPresent(ModifierSet.self, forKey: .modifiers) ?? ModifierSet()
		)
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(button, forKey: .button)
		try container.encode(modifiers, forKey: .modifiers)
	}
}

public struct MouseClick: Codable, Equatable, Sendable {
	public static let maximumClickCount = 4

	public var button: MouseButton
	public var modifiers: ModifierSet
	public var clickCount: Int {
		didSet { clickCount = Self.sanitizedClickCount(clickCount) }
	}

	public init(button: MouseButton, clickCount: Int = 1, modifiers: ModifierSet = ModifierSet()) {
		self.button = button
		self.modifiers = modifiers
		self.clickCount = Self.sanitizedClickCount(clickCount)
	}

	public var displaySummary: String {
		let clickSummary = clickCount == 1 ? "\(button.displayName) click" : "\(button.displayName) click x\(clickCount)"
		if modifiers.isEmpty { return clickSummary }
		return "\(modifiers.displayString)+\(clickSummary)"
	}

	private static func sanitizedClickCount(_ value: Int) -> Int {
		min(max(1, value), maximumClickCount)
	}

	private enum CodingKeys: String, CodingKey {
		case button
		case clickCount
		case modifiers
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		self.init(
			button: try container.decode(MouseButton.self, forKey: .button),
			clickCount: try container.decodeIfPresent(Int.self, forKey: .clickCount) ?? 1,
			modifiers: try container.decodeIfPresent(ModifierSet.self, forKey: .modifiers) ?? ModifierSet()
		)
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(button, forKey: .button)
		try container.encode(clickCount, forKey: .clickCount)
		try container.encode(modifiers, forKey: .modifiers)
	}
}

public struct MouseMove: Codable, Equatable, Sendable {
	public var deltaX: Double
	public var deltaY: Double

	public init(deltaX: Double, deltaY: Double) {
		self.deltaX = deltaX
		self.deltaY = deltaY
	}
}

public struct MouseScroll: Codable, Equatable, Sendable {
	/// Largest line-scroll delta a single step may emit per axis. A configured
	/// or decoded value beyond this would fling the scroll position; clamp it
	/// the same way `MouseClick`/`TypeTextStep` sanitize their inputs.
	public static let maximumMagnitude: Int32 = 10_000

	public var deltaX: Int32 {
		didSet { deltaX = Self.sanitized(deltaX) }
	}
	public var deltaY: Int32 {
		didSet { deltaY = Self.sanitized(deltaY) }
	}

	public init(deltaX: Int32 = 0, deltaY: Int32 = 0) {
		self.deltaX = Self.sanitized(deltaX)
		self.deltaY = Self.sanitized(deltaY)
	}

	private static func sanitized(_ value: Int32) -> Int32 {
		min(maximumMagnitude, max(-maximumMagnitude, value))
	}

	private enum CodingKeys: String, CodingKey {
		case deltaX
		case deltaY
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		self.init(
			deltaX: try container.decodeIfPresent(Int32.self, forKey: .deltaX) ?? 0,
			deltaY: try container.decodeIfPresent(Int32.self, forKey: .deltaY) ?? 0
		)
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(deltaX, forKey: .deltaX)
		try container.encode(deltaY, forKey: .deltaY)
	}

	public var displaySummary: String {
		if deltaY > 0 { return "Scroll up" }
		if deltaY < 0 { return "Scroll down" }
		if deltaX > 0 { return "Scroll right" }
		if deltaX < 0 { return "Scroll left" }
		return "Scroll"
	}
}

public enum TextEntryMode: String, Codable, CaseIterable, Sendable {
	case paste
	case type
}

public struct TypeTextStep: Codable, Equatable, Sendable {
	public var text: String
	public var mode: TextEntryMode
	public var pressReturn: Bool

	/// Pacing for `.type` mode in characters per minute. `nil` types at full speed.
	/// Ignored in `.paste` mode.
	public var charactersPerMinute: Int? {
		didSet { charactersPerMinute = Self.sanitizedCharactersPerMinute(charactersPerMinute) }
	}

	public init(text: String, mode: TextEntryMode = .paste, pressReturn: Bool = false, charactersPerMinute: Int? = nil) {
		self.text = text
		self.mode = mode
		self.pressReturn = pressReturn
		self.charactersPerMinute = Self.sanitizedCharactersPerMinute(charactersPerMinute)
	}

	public var displaySummary: String {
		let trimmed = text.replacingOccurrences(of: "\n", with: " ")
			.trimmingCharacters(in: .whitespacesAndNewlines)
		let visible = trimmed.isEmpty ? "Text" : String(trimmed.prefix(48))
		return pressReturn ? "\(visible) + Return" : visible
	}

	private static func sanitizedCharactersPerMinute(_ value: Int?) -> Int? {
		guard let value, value > 0 else { return nil }
		return value
	}

	private enum CodingKeys: String, CodingKey {
		case text
		case mode
		case pressReturn
		case charactersPerMinute
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		self.init(
			text: try container.decode(String.self, forKey: .text),
			mode: try container.decodeIfPresent(TextEntryMode.self, forKey: .mode) ?? .paste,
			pressReturn: try container.decodeIfPresent(Bool.self, forKey: .pressReturn) ?? false,
			charactersPerMinute: try container.decodeIfPresent(Int.self, forKey: .charactersPerMinute)
		)
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(text, forKey: .text)
		try container.encode(mode, forKey: .mode)
		try container.encode(pressReturn, forKey: .pressReturn)
		try container.encodeIfPresent(charactersPerMinute, forKey: .charactersPerMinute)
	}
}
