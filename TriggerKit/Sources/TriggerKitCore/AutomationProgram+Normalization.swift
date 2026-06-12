import Foundation

public extension AutomationProgram {
	func normalized(fallbackName: String) -> AutomationProgram {
		var copy = self
		let trimmedName = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
		copy.name = trimmedName.isEmpty ? fallbackName : trimmedName
		copy.steps = copy.steps.map { $0.normalized() }
		return copy
	}

	func persistable(fallbackName: String) -> AutomationProgram? {
		let copy = normalized(fallbackName: fallbackName)
		return copy.steps.isEmpty ? nil : copy
	}
}

public extension AutomationStep {
	func normalized() -> AutomationStep {
		switch self {
		case .openApp(let app):
			return .openApp(OpenAppStep(
				bundleIdentifier: app.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
				openNewWindow: app.openNewWindow
			))
		case .openURL(let url):
			let trimmed = url.url.trimmingCharacters(in: .whitespacesAndNewlines)
			return .openURL(OpenURLStep(url: normalizedURL(trimmed)?.absoluteString ?? trimmed))
		case .shellCommand(let shell):
			return .shellCommand(ShellCommandStep(
				command: shell.command.trimmingCharacters(in: .whitespacesAndNewlines),
				shellPath: shell.shellPath.trimmingCharacters(in: .whitespacesAndNewlines),
				timeoutSeconds: shell.timeoutSeconds,
				runsInTerminal: shell.runsInTerminal
			))
		case .webhook(let webhook):
			return .webhook(WebhookStep(
				url: webhook.url.trimmingCharacters(in: .whitespacesAndNewlines),
				method: webhook.method,
				headers: webhook.headers,
				body: webhook.body,
				timeoutSeconds: webhook.timeoutSeconds
			))
		case .custom(let custom):
			return .custom(CustomStep(
				namespace: custom.namespace.trimmingCharacters(in: .whitespacesAndNewlines),
				payload: custom.payload,
				displayName: custom.displayName
			))
		default:
			return self
		}
	}

	private func normalizedURL(_ rawURL: String) -> URL? {
		guard !rawURL.isEmpty else { return nil }
		let resolved = rawURL.contains("://") ? rawURL : "https://\(rawURL)"
		guard let url = URL(string: resolved), url.scheme != nil else { return nil }
		return url
	}
}
