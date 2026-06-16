import Foundation

public struct DelayStep: Codable, Equatable, Sendable {
	public var seconds: TimeInterval {
		didSet { seconds = Self.sanitizedSeconds(seconds) }
	}

	public init(seconds: TimeInterval) {
		self.seconds = Self.sanitizedSeconds(seconds)
	}

	public var displayDuration: String {
		let rounded = Int(seconds.rounded())
		if rounded < 60 { return "\(rounded)s" }
		let minutes = rounded / 60
		if minutes < 60 { return "\(minutes)m" }
		let hours = minutes / 60
		if hours < 24 { return "\(hours)h" }
		return "\(hours / 24)d"
	}

	private static func sanitizedSeconds(_ value: TimeInterval) -> TimeInterval {
		guard value.isFinite else { return 0 }
		return min(max(0, value), 315_360_000)
	}

	private enum CodingKeys: String, CodingKey {
		case seconds
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		self.init(seconds: try container.decode(TimeInterval.self, forKey: .seconds))
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(seconds, forKey: .seconds)
	}
}

public struct OpenAppStep: Codable, Equatable, Sendable {
	public var bundleIdentifier: String
	public var openNewWindow: Bool

	public init(bundleIdentifier: String, openNewWindow: Bool = false) {
		self.bundleIdentifier = bundleIdentifier
		self.openNewWindow = openNewWindow
	}
}

public struct OpenURLStep: Codable, Equatable, Sendable {
	public var url: String

	public init(url: String) {
		self.url = url
	}
}

public struct ShellCommandStep: Codable, Equatable, Sendable {
	public var command: String
	public var shellPath: String
	public var timeoutSeconds: TimeInterval {
		didSet { timeoutSeconds = Self.sanitizedTimeout(timeoutSeconds) }
	}

	/// Runs the command in a visible terminal window instead of silently.
	/// Terminal commands are fire-and-forget: no timeout or output capture.
	public var runsInTerminal: Bool

	public init(command: String, shellPath: String = "/bin/zsh", timeoutSeconds: TimeInterval = 10, runsInTerminal: Bool = false) {
		self.command = command
		self.shellPath = shellPath
		self.timeoutSeconds = Self.sanitizedTimeout(timeoutSeconds)
		self.runsInTerminal = runsInTerminal
	}

	public var displaySummary: String {
		command.isEmpty ? "Shell command" : String(command.prefix(56))
	}

	private static func sanitizedTimeout(_ value: TimeInterval) -> TimeInterval {
		value.isFinite ? max(1, value) : 1
	}

	private enum CodingKeys: String, CodingKey {
		case command
		case shellPath
		case timeoutSeconds
		case runsInTerminal
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		self.init(
			command: try container.decode(String.self, forKey: .command),
			shellPath: try container.decodeIfPresent(String.self, forKey: .shellPath) ?? "/bin/zsh",
			timeoutSeconds: try container.decodeIfPresent(TimeInterval.self, forKey: .timeoutSeconds) ?? 10,
			runsInTerminal: try container.decodeIfPresent(Bool.self, forKey: .runsInTerminal) ?? false
		)
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(command, forKey: .command)
		try container.encode(shellPath, forKey: .shellPath)
		try container.encode(timeoutSeconds, forKey: .timeoutSeconds)
		try container.encode(runsInTerminal, forKey: .runsInTerminal)
	}
}

public enum WebhookMethod: String, Codable, CaseIterable, Sendable {
	case get = "GET"
	case post = "POST"
	case put = "PUT"
	case delete = "DELETE"
	case patch = "PATCH"
}

public struct WebhookStep: Codable, Equatable, Sendable {
	public var url: String
	public var method: WebhookMethod
	public var headers: [String: String]
	public var body: String?
	public var timeoutSeconds: TimeInterval {
		didSet { timeoutSeconds = Self.sanitizedTimeout(timeoutSeconds) }
	}

	public init(
		url: String,
		method: WebhookMethod = .post,
		headers: [String: String] = [:],
		body: String? = nil,
		timeoutSeconds: TimeInterval = 10
	) {
		self.url = url
		self.method = method
		self.headers = headers
		self.body = body
		self.timeoutSeconds = Self.sanitizedTimeout(timeoutSeconds)
	}

	public var displaySummary: String {
		let target = url.isEmpty ? "Webhook" : String(url.prefix(48))
		return "\(method.rawValue) \(target)"
	}

	private static func sanitizedTimeout(_ value: TimeInterval) -> TimeInterval {
		value.isFinite ? max(1, value) : 1
	}

	private enum CodingKeys: String, CodingKey {
		case url
		case method
		case headers
		case body
		case timeoutSeconds
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		self.init(
			url: try container.decode(String.self, forKey: .url),
			method: try container.decodeIfPresent(WebhookMethod.self, forKey: .method) ?? .post,
			headers: try container.decodeIfPresent([String: String].self, forKey: .headers) ?? [:],
			body: try container.decodeIfPresent(String.self, forKey: .body),
			timeoutSeconds: try container.decodeIfPresent(TimeInterval.self, forKey: .timeoutSeconds) ?? 10
		)
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(url, forKey: .url)
		try container.encode(method, forKey: .method)
		try container.encode(headers, forKey: .headers)
		try container.encodeIfPresent(body, forKey: .body)
		try container.encode(timeoutSeconds, forKey: .timeoutSeconds)
	}
}

/// Sets the system clipboard (general pasteboard) to a fixed string. Pairs with
/// a later `keyPress` Cmd+V to paste, or just leaves the text ready to paste.
public struct ClipboardStep: Codable, Equatable, Sendable {
	public var text: String

	public init(text: String = "") {
		self.text = text
	}

	public var displaySummary: String {
		text.isEmpty ? "Set clipboard" : "Copy \"\(String(text.prefix(32)))\""
	}
}

/// Which system setting a `SystemSettingStep` changes.
public enum SystemSettingAction: String, Codable, CaseIterable, Sendable {
	case setVolume
	case mute
	case unmute
	case sleepDisplay
	case toggleDarkMode

	public var displayName: String {
		switch self {
		case .setVolume: return "Set Volume"
		case .mute: return "Mute"
		case .unmute: return "Unmute"
		case .sleepDisplay: return "Sleep Display"
		case .toggleDarkMode: return "Toggle Dark Mode"
		}
	}
}

/// Changes a system-level setting (output volume, mute, display sleep, dark
/// mode). Implemented host-side via signed system tools, so it needs no input
/// (Accessibility) permission.
public struct SystemSettingStep: Codable, Equatable, Sendable {
	public var action: SystemSettingAction
	/// Output volume 0–100, used only when `action == .setVolume`.
	public var volume: Int {
		didSet { volume = Self.clampedVolume(volume) }
	}

	public init(action: SystemSettingAction, volume: Int = 50) {
		self.action = action
		self.volume = Self.clampedVolume(volume)
	}

	public var displaySummary: String {
		switch action {
		case .setVolume: return "Set volume \(volume)"
		default: return action.displayName
		}
	}

	private static func clampedVolume(_ value: Int) -> Int {
		min(max(0, value), 100)
	}

	private enum CodingKeys: String, CodingKey {
		case action
		case volume
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		self.init(
			action: try container.decode(SystemSettingAction.self, forKey: .action),
			volume: try container.decodeIfPresent(Int.self, forKey: .volume) ?? 50
		)
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(action, forKey: .action)
		try container.encode(volume, forKey: .volume)
	}
}

/// What a `ConditionStep` tests before allowing the rest of the program to run.
public enum ConditionKind: String, Codable, CaseIterable, Sendable {
	case online
	case appRunning
	case timeWindow

	public var displayName: String {
		switch self {
		case .online: return "Online"
		case .appRunning: return "App Running"
		case .timeWindow: return "Time Window"
		}
	}
}

/// A guard step: if its condition isn't met, the rest of the program is skipped
/// (reported as a successful no-op, not a failure). Lets a program say "only
/// auto-play between 09:00–22:00" or "only run if online". `negate` flips the
/// test ("unless" instead of "only if").
public struct ConditionStep: Codable, Equatable, Sendable {
	public var kind: ConditionKind
	public var negate: Bool
	/// Bundle id tested when `kind == .appRunning`.
	public var bundleIdentifier: String
	/// Minutes since midnight; window is [start, end) when `kind == .timeWindow`.
	/// A start later than end wraps past midnight (e.g. 22:00–06:00).
	public var startMinutes: Int {
		didSet { startMinutes = Self.clampedMinutes(startMinutes) }
	}
	public var endMinutes: Int {
		didSet { endMinutes = Self.clampedMinutes(endMinutes) }
	}

	public init(
		kind: ConditionKind = .online,
		negate: Bool = false,
		bundleIdentifier: String = "",
		startMinutes: Int = 9 * 60,
		endMinutes: Int = 22 * 60
	) {
		self.kind = kind
		self.negate = negate
		self.bundleIdentifier = bundleIdentifier
		self.startMinutes = Self.clampedMinutes(startMinutes)
		self.endMinutes = Self.clampedMinutes(endMinutes)
	}

	public var displaySummary: String {
		let prefix = negate ? "Unless" : "Only if"
		switch kind {
		case .online:
			return "\(prefix) online"
		case .appRunning:
			let app = bundleIdentifier.isEmpty ? "app" : bundleIdentifier
			return "\(prefix) \(app) running"
		case .timeWindow:
			return "\(prefix) \(Self.clockString(startMinutes))–\(Self.clockString(endMinutes))"
		}
	}

	private static func clampedMinutes(_ value: Int) -> Int {
		min(max(0, value), 24 * 60 - 1)
	}

	static func clockString(_ minutes: Int) -> String {
		let clamped = min(max(0, minutes), 24 * 60 - 1)
		return String(format: "%02d:%02d", clamped / 60, clamped % 60)
	}

	private enum CodingKeys: String, CodingKey {
		case kind
		case negate
		case bundleIdentifier
		case startMinutes
		case endMinutes
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		self.init(
			kind: try container.decode(ConditionKind.self, forKey: .kind),
			negate: try container.decodeIfPresent(Bool.self, forKey: .negate) ?? false,
			bundleIdentifier: try container.decodeIfPresent(String.self, forKey: .bundleIdentifier) ?? "",
			startMinutes: try container.decodeIfPresent(Int.self, forKey: .startMinutes) ?? 9 * 60,
			endMinutes: try container.decodeIfPresent(Int.self, forKey: .endMinutes) ?? 22 * 60
		)
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(kind, forKey: .kind)
		try container.encode(negate, forKey: .negate)
		try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
		try container.encode(startMinutes, forKey: .startMinutes)
		try container.encode(endMinutes, forKey: .endMinutes)
	}
}

/// A host-app-specific step. TriggerKit carries it through programs and
/// persistence untouched; execution requires the host to supply a
/// `stepOverride` in `TriggerExecutionContext`, otherwise the step fails.
///
/// `namespace` identifies the action (reverse-DNS style, e.g.
/// "controllerkeys.obs-websocket"); `payload` is a serialized JSON document
/// whose schema is owned by the host app.
public struct CustomStep: Codable, Equatable, Sendable {
	public var namespace: String
	public var payload: String
	public var displayName: String?

	public init(namespace: String, payload: String = "{}", displayName: String? = nil) {
		self.namespace = namespace
		self.payload = payload
		self.displayName = displayName
	}

	public var displaySummary: String {
		if let displayName, !displayName.isEmpty { return displayName }
		return namespace.isEmpty ? "Custom action" : namespace
	}
}
