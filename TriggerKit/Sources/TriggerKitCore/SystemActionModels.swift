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
