import Foundation

public struct AutomationValidationPolicy: Equatable, Sendable {
	public var allowsEmptyProgram: Bool
	public var capabilities: AutomationCapabilities
	/// Lowercased schemes `openURL` steps may launch. `nil` allows any scheme.
	public var allowedURLSchemes: Set<String>?
	/// Lowercased schemes webhook steps may call.
	public var allowedWebhookSchemes: Set<String>
	/// Optional installed-app universe. When nil, validation only checks that
	/// app bundle identifiers are configured, not whether macOS can resolve them.
	public var installedApplicationBundleIdentifiers: Set<String>?
	/// Optional host-owned custom namespaces. When nil, all non-empty custom
	/// namespaces are accepted.
	public var supportedCustomNamespaces: Set<String>?

	public init(
		allowsEmptyProgram: Bool = false,
		capabilities: AutomationCapabilities = .all,
		allowedURLSchemes: Set<String>? = nil,
		allowedWebhookSchemes: Set<String> = ["http", "https"],
		installedApplicationBundleIdentifiers: Set<String>? = nil,
		supportedCustomNamespaces: Set<String>? = nil
	) {
		self.allowsEmptyProgram = allowsEmptyProgram
		self.capabilities = capabilities
		self.allowedURLSchemes = allowedURLSchemes.map { Self.normalizedSet($0) }
		self.allowedWebhookSchemes = Self.normalizedSet(allowedWebhookSchemes)
		self.installedApplicationBundleIdentifiers = installedApplicationBundleIdentifiers
		self.supportedCustomNamespaces = supportedCustomNamespaces
	}

	public static let `default` = AutomationValidationPolicy()

	private static func normalizedSet(_ values: Set<String>) -> Set<String> {
		Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
	}
}

public enum AutomationValidationSeverity: String, Codable, Equatable, Sendable {
	case error
	case warning
}

public enum AutomationValidationIssueCode: String, Codable, Equatable, Sendable {
	case emptyProgram
	case unsupportedCapability
	case inertStep
	case emptyText
	case missingAppBundleIdentifier
	case appBundleNotFound
	case invalidURL
	case disallowedURLScheme
	case emptyShellCommand
	case missingShellPath
	case invalidWebhookURL
	case disallowedWebhookScheme
	case invalidCondition
	case missingCustomNamespace
	case unsupportedCustomNamespace
}

public struct AutomationValidationIssue: Codable, Equatable, Identifiable, Sendable {
	public var code: AutomationValidationIssueCode
	public var severity: AutomationValidationSeverity
	public var message: String
	public var stepIndex: Int?
	public var stepKind: AutomationStep.Kind?

	public init(
		code: AutomationValidationIssueCode,
		severity: AutomationValidationSeverity = .error,
		message: String,
		stepIndex: Int? = nil,
		stepKind: AutomationStep.Kind? = nil
	) {
		self.code = code
		self.severity = severity
		self.message = message
		self.stepIndex = stepIndex
		self.stepKind = stepKind
	}

	public var id: String {
		"\(stepIndex ?? -1):\(stepKind?.rawValue ?? "program"):\(code.rawValue):\(message)"
	}

	public var isError: Bool {
		severity == .error
	}
}

public extension AutomationProgram {
	func validate(policy: AutomationValidationPolicy = .default) -> [AutomationValidationIssue] {
		let program = normalized(fallbackName: name)
		var issues: [AutomationValidationIssue] = []
		if program.steps.isEmpty, !policy.allowsEmptyProgram {
			issues.append(AutomationValidationIssue(
				code: .emptyProgram,
				message: "Program has no steps"
			))
		}

		for (index, step) in program.steps.enumerated() {
			issues.append(contentsOf: step.validationIssues(index: index, policy: policy))
		}
		return issues
	}
}

private extension AutomationStep {
	func validationIssues(index: Int, policy: AutomationValidationPolicy) -> [AutomationValidationIssue] {
		var issues: [AutomationValidationIssue] = []
		if !policy.capabilities.allows(kind) {
			issues.append(issue(
				.unsupportedCapability,
				index: index,
				message: "\(kind.displayName) is not allowed by this policy"
			))
		}

		switch self {
		case .mouseMove(let move):
			if move.deltaX == 0, move.deltaY == 0 {
				issues.append(issue(.inertStep, severity: .warning, index: index, message: "Mouse move has no distance"))
			}
		case .mouseScroll(let scroll):
			if scroll.deltaX == 0, scroll.deltaY == 0 {
				issues.append(issue(.inertStep, severity: .warning, index: index, message: "Mouse scroll has no distance"))
			}
		case .delay(let delay):
			if delay.seconds <= 0 {
				issues.append(issue(.inertStep, severity: .warning, index: index, message: "Delay has no duration"))
			}
		case .typeText(let text):
			if text.text.isEmpty, !text.pressReturn {
				issues.append(issue(.emptyText, index: index, message: "Type Text has no text or Return key"))
			}
		case .openApp(let app):
			let bundleIdentifier = app.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
			if bundleIdentifier.isEmpty {
				issues.append(issue(.missingAppBundleIdentifier, index: index, message: "Open App has no bundle identifier"))
			} else if let installed = policy.installedApplicationBundleIdentifiers, !installed.contains(bundleIdentifier) {
				issues.append(issue(.appBundleNotFound, index: index, message: "App bundle not found: \(bundleIdentifier)"))
			}
		case .openURL(let step):
			issues.append(contentsOf: validateURL(
				rawURL: step.url,
				allowedSchemes: policy.allowedURLSchemes,
				invalidCode: .invalidURL,
				disallowedCode: .disallowedURLScheme,
				index: index,
				label: "URL"
			))
		case .shellCommand(let shell):
			if shell.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
				issues.append(issue(.emptyShellCommand, index: index, message: "Shell command is empty"))
			}
			if shell.shellPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
				issues.append(issue(.missingShellPath, index: index, message: "Shell path is empty"))
			}
		case .webhook(let webhook):
			issues.append(contentsOf: validateURL(
				rawURL: webhook.url,
				allowedSchemes: policy.allowedWebhookSchemes,
				invalidCode: .invalidWebhookURL,
				disallowedCode: .disallowedWebhookScheme,
				index: index,
				label: "Webhook URL",
				addDefaultHTTPS: false
			))
		case .condition(let condition):
			if condition.kind == .appRunning,
			   condition.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
				issues.append(issue(.invalidCondition, index: index, message: "App Running condition has no bundle identifier"))
			}
		case .custom(let custom):
			let namespace = custom.namespace.trimmingCharacters(in: .whitespacesAndNewlines)
			if namespace.isEmpty {
				issues.append(issue(.missingCustomNamespace, index: index, message: "Custom action has no namespace"))
			} else if let supported = policy.supportedCustomNamespaces, !supported.contains(namespace) {
				issues.append(issue(.unsupportedCustomNamespace, index: index, message: "Custom action is not supported: \(namespace)"))
			}
		case .keyPress, .keyDown, .keyUp, .mouseClick, .mouseDown, .mouseUp, .clipboard, .systemSetting:
			break
		}
		return issues
	}

	func validateURL(
		rawURL: String,
		allowedSchemes: Set<String>?,
		invalidCode: AutomationValidationIssueCode,
		disallowedCode: AutomationValidationIssueCode,
		index: Int,
		label: String,
		addDefaultHTTPS: Bool = true
	) -> [AutomationValidationIssue] {
		let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else {
			return [issue(invalidCode, index: index, message: "\(label) is empty")]
		}
		let resolved = addDefaultHTTPS && !trimmed.contains("://") ? "https://\(trimmed)" : trimmed
		guard let url = URL(string: resolved), let scheme = url.scheme?.lowercased(), !scheme.isEmpty else {
			return [issue(invalidCode, index: index, message: "\(label) is invalid")]
		}
		if let allowedSchemes, !allowedSchemes.contains(scheme) {
			return [issue(disallowedCode, index: index, message: "\(label) scheme is not allowed: \(scheme)")]
		}

		// Security: Block dangerous URL schemes that can bypass app sandboxing or manipulate system settings.
		let blockedSchemes: Set<String> = ["file", "x-apple.systempreferences"]
		if blockedSchemes.contains(scheme) {
			return [issue(disallowedCode, index: index, message: "\(label) scheme is dangerously blocked: \(scheme)")]
		}

		return []
	}

	func issue(
		_ code: AutomationValidationIssueCode,
		severity: AutomationValidationSeverity = .error,
		index: Int,
		message: String
	) -> AutomationValidationIssue {
		AutomationValidationIssue(
			code: code,
			severity: severity,
			message: message,
			stepIndex: index,
			stepKind: kind
		)
	}
}
