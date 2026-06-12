import Carbon.HIToolbox
import Darwin
import AppKit
import Foundation
import TriggerKitCore

public enum TriggerExecutionConcurrencyPolicy: Equatable, Sendable {
	case queue
	case reject
	/// Runs immediately even if another automation is in flight. Hosts that
	/// fire independent programs from independent triggers (e.g. controller
	/// buttons) use this to keep programs from blocking each other.
	case concurrent
}

public struct TriggerExecutionPolicy: Sendable {
	public var capabilities: AutomationCapabilities
	public var concurrencyPolicy: TriggerExecutionConcurrencyPolicy
	public var validatesAccessibility: Bool
	public var maximumShellOutputBytes: Int

	/// Lowercased URL schemes `openURL` steps may launch. `nil` allows any
	/// scheme; an empty set blocks all `openURL` steps.
	public var allowedURLSchemes: Set<String>?

	/// When true, a failing step is logged and the program keeps running
	/// instead of aborting. Failures still cancel the program when false.
	public var continuesOnStepFailure: Bool

	public init(
		capabilities: AutomationCapabilities = .all,
		concurrencyPolicy: TriggerExecutionConcurrencyPolicy = .queue,
		validatesAccessibility: Bool = true,
		maximumShellOutputBytes: Int = 1_048_576,
		allowedURLSchemes: Set<String>? = nil,
		continuesOnStepFailure: Bool = false
	) {
		self.capabilities = capabilities
		self.concurrencyPolicy = concurrencyPolicy
		self.validatesAccessibility = validatesAccessibility
		self.maximumShellOutputBytes = max(1, maximumShellOutputBytes)
		self.allowedURLSchemes = allowedURLSchemes.map { Set($0.map { $0.lowercased() }) }
		self.continuesOnStepFailure = continuesOnStepFailure
	}

	public static let `default` = TriggerExecutionPolicy()
}

public struct TriggerExecutionContext {
	public var environment: [String: String]
	public var prepareTarget: (() async throws -> Void)?
	public var logger: (String) -> Void
	public var policy: TriggerExecutionPolicy

	/// Host hook consulted before every step. Return a result to replace the
	/// built-in behavior for that step (or to handle a `.custom` step); return
	/// `nil` to fall through to the executor's native implementation.
	public var stepOverride: ((AutomationStep) async -> TriggerExecutionResult?)?

	/// Session used for `.webhook` steps. Injectable for testing.
	public var urlSession: URLSession

	public init(
		environment: [String: String] = [:],
		prepareTarget: (() async throws -> Void)? = nil,
		logger: @escaping (String) -> Void = { _ in },
		policy: TriggerExecutionPolicy = .default,
		stepOverride: ((AutomationStep) async -> TriggerExecutionResult?)? = nil,
		urlSession: URLSession = .shared
	) {
		self.environment = environment
		self.prepareTarget = prepareTarget
		self.logger = logger
		self.policy = policy
		self.stepOverride = stepOverride
		self.urlSession = urlSession
	}
}

public enum TriggerExecutionResult: Equatable, Sendable {
	case success(String)
	case failure(String)

	public var isSuccess: Bool {
		if case .success = self { return true }
		return false
	}

	public var message: String {
		switch self {
		case .success(let message), .failure(let message):
			return message
		}
	}
}

@MainActor
public final class AutomationExecutor {
	private static let executionGate = AutomationExecutionGate()
	private let input: InputSimulating

	public convenience init() {
		self.init(input: InputSimulator())
	}

	public init(input: InputSimulating) {
		self.input = input
	}

	public func execute(
		_ program: AutomationProgram,
		context: TriggerExecutionContext = TriggerExecutionContext()
	) async -> TriggerExecutionResult {
		if context.policy.concurrencyPolicy == .concurrent {
			return await executeUnlocked(program, context: context)
		}
		do {
			guard try await Self.executionGate.begin(policy: context.policy.concurrencyPolicy) else {
				return .failure("Another automation is already running")
			}
		} catch is CancellationError {
			return .failure("Cancelled")
		} catch {
			return .failure(error.localizedDescription)
		}
		let result = await executeUnlocked(program, context: context)
		await Self.executionGate.finish()
		return result
	}

	private func executeUnlocked(
		_ program: AutomationProgram,
		context: TriggerExecutionContext
	) async -> TriggerExecutionResult {
		do {
			try Task.checkCancellation()
			if let disallowedStep = program.steps.first(where: { !context.policy.capabilities.allows($0.kind) }) {
				return .failure("Action not allowed: \(disallowedStep.kind.displayName)")
			}
			if context.policy.validatesAccessibility, program.requiresAccessibility, !input.isInputPostingAvailable {
				return .failure("Accessibility permission is required for input actions")
			}
			try await context.prepareTarget?()
			var failedSteps = 0
			for step in program.steps {
				try Task.checkCancellation()
				let result = await execute(step, context: context)
				if !result.isSuccess {
					guard context.policy.continuesOnStepFailure else {
						return result
					}
					failedSteps += 1
					context.logger("Step failed: \(result.message)")
				}
			}
			if program.steps.isEmpty {
				return .success("No actions")
			}
			if failedSteps > 0 {
				return .success("Completed \(program.steps.count) step(s), \(failedSteps) failed")
			}
			return .success("Completed \(program.steps.count) step(s)")
		} catch is CancellationError {
			return .failure("Cancelled")
		} catch {
			return .failure(error.localizedDescription)
		}
	}

	private func execute(_ step: AutomationStep, context: TriggerExecutionContext) async -> TriggerExecutionResult {
		if let stepOverride = context.stepOverride, let overridden = await stepOverride(step) {
			return overridden
		}
		switch step {
		case .keyPress(let keyStroke):
			await input.keyPress(keyStroke)
			return .success("Pressed \(keyStroke.displaySummary)")
		case .keyDown(let event):
			input.keyDown(event)
			return .success("Held \(event.displaySummary)")
		case .keyUp(let event):
			input.keyUp(event)
			return .success("Released \(event.displaySummary)")
		case .mouseClick(let click):
			input.mouseClick(click)
			return .success(click.displaySummary)
		case .mouseDown(let event):
			input.mouseDown(event)
			return .success("Mouse down \(event.displaySummary)")
		case .mouseUp(let event):
			input.mouseUp(event)
			return .success("Mouse up \(event.displaySummary)")
		case .mouseMove(let move):
			input.mouseMove(move)
			return .success("Moved mouse")
		case .mouseScroll(let scroll):
			input.mouseScroll(scroll)
			return .success(scroll.displaySummary)
		case .delay(let delay):
			return await wait(delay)
		case .typeText(let text):
			await input.typeText(text)
			return .success(text.displaySummary)
		case .openApp(let app):
			return await openApp(app)
		case .openURL(let url):
			return openURL(url, allowedSchemes: context.policy.allowedURLSchemes)
		case .shellCommand(let shell):
			if shell.runsInTerminal {
				return runShellInTerminal(shell)
			}
			let outcome = await runShell(
				shell,
				environment: context.environment,
				maximumOutputBytes: context.policy.maximumShellOutputBytes
			)
			if let output = outcome.outputToLog {
				context.logger(output)
			}
			return outcome.result
		case .webhook(let webhook):
			return await runWebhook(webhook, session: context.urlSession)
		case .custom(let custom):
			return .failure("No handler for app action: \(custom.namespace)")
		}
	}

	private func wait(_ delay: DelayStep) async -> TriggerExecutionResult {
		do {
			let seconds = delay.seconds.isFinite ? max(0, delay.seconds) : 0
			let nanoseconds = UInt64(seconds * 1_000_000_000)
			try await Task.sleep(nanoseconds: nanoseconds)
			return .success("Waited \(delay.displayDuration)")
		} catch {
			return .failure("Cancelled")
		}
	}

	private func openApp(_ step: OpenAppStep) async -> TriggerExecutionResult {
		guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: step.bundleIdentifier) else {
			return .failure("App not found: \(step.bundleIdentifier)")
		}
		let configuration = NSWorkspace.OpenConfiguration()
		configuration.activates = true
		let result: TriggerExecutionResult = await withCheckedContinuation { continuation in
			NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, error in
				if let error {
					continuation.resume(returning: .failure(error.localizedDescription))
				} else if app == nil {
					continuation.resume(returning: .failure("Could not open app: \(step.bundleIdentifier)"))
				} else {
					continuation.resume(returning: .success("Opened \(step.bundleIdentifier)"))
				}
			}
		}
		guard result.isSuccess else { return result }
		if step.openNewWindow {
			try? await Task.sleep(nanoseconds: 300_000_000)
			await input.keyPress(KeyStroke(key: newWindowKey, modifiers: ModifierSet(command: .any)))
			return .success("Opened \(step.bundleIdentifier) and requested a new window")
		}
		return result
	}

	private func openURL(_ step: OpenURLStep, allowedSchemes: Set<String>?) -> TriggerExecutionResult {
		let urlString = step.url.trimmingCharacters(in: .whitespacesAndNewlines)
		guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased(), !scheme.isEmpty else {
			return .failure("Invalid URL")
		}
		if let allowedSchemes, !allowedSchemes.contains(scheme) {
			return .failure("URL scheme not allowed: \(scheme)")
		}
		guard NSWorkspace.shared.open(url) else {
			return .failure("Could not open URL: \(urlString)")
		}
		return .success("Opened \(urlString)")
	}

	private func runWebhook(_ step: WebhookStep, session: URLSession) async -> TriggerExecutionResult {
		let urlString = step.url.trimmingCharacters(in: .whitespacesAndNewlines)
		guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
			return .failure("Invalid webhook URL")
		}
		var request = URLRequest(url: url, timeoutInterval: step.timeoutSeconds)
		request.httpMethod = step.method.rawValue
		for (field, value) in step.headers {
			request.setValue(value, forHTTPHeaderField: field)
		}
		if let body = step.body, !body.isEmpty {
			request.httpBody = Data(body.utf8)
		}
		do {
			let (_, response) = try await session.data(for: request)
			guard let http = response as? HTTPURLResponse else {
				return .success("Webhook sent")
			}
			if (200..<300).contains(http.statusCode) {
				return .success("Webhook \(http.statusCode)")
			}
			return .failure("Webhook HTTP \(http.statusCode)")
		} catch {
			return .failure(error.localizedDescription)
		}
	}

	private func runShellInTerminal(_ step: ShellCommandStep) -> TriggerExecutionResult {
		let command = step.command.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !command.isEmpty else {
			return .failure("Empty terminal command")
		}
		let escaped = command
			.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: "\"", with: "\\\"")
		let script = """
		tell application "Terminal"
			activate
			do script "\(escaped)"
		end tell
		"""
		var error: NSDictionary?
		NSAppleScript(source: script)?.executeAndReturnError(&error)
		if let error, let message = error[NSAppleScript.errorMessage] as? String {
			return .failure("Terminal launch failed: \(message)")
		}
		return .success("Ran in Terminal")
	}

	private nonisolated func runShell(
		_ step: ShellCommandStep,
		environment: [String: String],
		maximumOutputBytes: Int
	) async -> ShellRunOutcome {
		let runner = ShellCommandRunner(step: step, environment: environment, maximumOutputBytes: maximumOutputBytes)
		let task = Task.detached(priority: .userInitiated) {
			runner.run()
		}
		return await withTaskCancellationHandler {
			await task.value
		} onCancel: {
			runner.cancel()
			task.cancel()
		}
	}

	private var newWindowKey: TriggerKey {
		TriggerKey.catalogKey(keyCode: UInt16(kVK_ANSI_N)) ??
			TriggerKey(id: "n", keyCode: UInt16(kVK_ANSI_N), displayName: "N")
	}
}

private actor AutomationExecutionGate {
	private struct Waiter {
		let id: UUID
		let continuation: CheckedContinuation<Bool, Never>
	}

	private var isRunning = false
	private var waiters: [Waiter] = []

	func begin(policy: TriggerExecutionConcurrencyPolicy) async throws -> Bool {
		try Task.checkCancellation()
		if policy == .reject {
			guard !isRunning else { return false }
			isRunning = true
			return true
		}

		if !isRunning {
			isRunning = true
			return true
		}

		let waiterID = UUID()
		let didEnter = await withTaskCancellationHandler {
			await withCheckedContinuation { continuation in
				if Task.isCancelled {
					continuation.resume(returning: false)
				} else {
					waiters.append(Waiter(id: waiterID, continuation: continuation))
				}
			}
		} onCancel: {
			Task {
				await self.cancelWaiter(waiterID)
			}
		}

		if !didEnter {
			throw CancellationError()
		}
		return true
	}

	func finish() {
		if waiters.isEmpty {
			isRunning = false
		} else {
			waiters.removeFirst().continuation.resume(returning: true)
		}
	}

	private func cancelWaiter(_ id: UUID) {
		guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
		waiters.remove(at: index).continuation.resume(returning: false)
	}
}

private final class ShellCommandRunner: @unchecked Sendable {
	let step: ShellCommandStep
	let environment: [String: String]
	let maximumOutputBytes: Int
	private let processLock = NSLock()
	private var process: Process?
	private var wasCancelled = false

	init(step: ShellCommandStep, environment: [String: String], maximumOutputBytes: Int) {
		self.step = step
		self.environment = environment
		self.maximumOutputBytes = maximumOutputBytes
	}

	func run() -> ShellRunOutcome {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: step.shellPath)
		process.arguments = ["-lc", step.command]
		process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
		store(process)

		let pipe = Pipe()
		process.standardOutput = pipe
		process.standardError = pipe
		let outputBuffer = LockedDataBuffer(maxBytes: maximumOutputBytes)
		pipe.fileHandleForReading.readabilityHandler = { handle in
			let data = handle.availableData
			if !data.isEmpty {
				outputBuffer.append(data)
			}
		}

		let semaphore = DispatchSemaphore(value: 0)
		process.terminationHandler = { _ in semaphore.signal() }

		if cancelled {
			clearStoredProcess()
			pipe.fileHandleForReading.readabilityHandler = nil
			return ShellRunOutcome(result: .failure("Cancelled"))
		}

		do {
			try process.run()
		} catch {
			clearStoredProcess()
			pipe.fileHandleForReading.readabilityHandler = nil
			return ShellRunOutcome(result: .failure(error.localizedDescription))
		}
		if cancelled {
			terminateProcessTree(process, signal: SIGTERM)
		}

		let timeout = DispatchTime.now() + step.timeoutSeconds
		if semaphore.wait(timeout: timeout) == .timedOut {
			terminateProcessTree(process, signal: SIGTERM)
			_ = semaphore.wait(timeout: .now() + 1)
			if process.isRunning {
				terminateProcessTree(process, signal: SIGKILL)
			}
			clearStoredProcess()
			pipe.fileHandleForReading.readabilityHandler = nil
			return ShellRunOutcome(result: .failure("Shell command timed out"))
		}

		clearStoredProcess()
		pipe.fileHandleForReading.readabilityHandler = nil
		let remainingData = pipe.fileHandleForReading.readDataToEndOfFile()
		if !remainingData.isEmpty {
			outputBuffer.append(remainingData)
		}
		let output = String(data: outputBuffer.data, encoding: .utf8)?
			.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		let displayOutput = outputBuffer.truncated ? "\(output)\n[output truncated]" : output
		if cancelled {
			return ShellRunOutcome(result: .failure("Cancelled"), outputToLog: displayOutput.isEmpty ? nil : displayOutput)
		}

		if process.terminationStatus == 0 {
			return ShellRunOutcome(
				result: .success(displayOutput.isEmpty ? "Shell command completed" : displayOutput),
				outputToLog: displayOutput.isEmpty ? nil : displayOutput
			)
		}
		return ShellRunOutcome(result: .failure("Shell exit \(process.terminationStatus)"), outputToLog: displayOutput.isEmpty ? nil : displayOutput)
	}

	func cancel() {
		processLock.lock()
		wasCancelled = true
		let currentProcess = process
		processLock.unlock()
		if let currentProcess {
			terminateProcessTree(currentProcess, signal: SIGTERM)
		}
	}

	private func store(_ process: Process) {
		processLock.lock()
		self.process = process
		processLock.unlock()
	}

	private var cancelled: Bool {
		processLock.lock()
		defer { processLock.unlock() }
		return wasCancelled
	}

	private func clearStoredProcess() {
		processLock.lock()
		process = nil
		processLock.unlock()
	}

	private func terminateProcessTree(_ process: Process, signal: Int32) {
		guard process.isRunning, process.processIdentifier > 0 else { return }
		terminatePIDTree(process.processIdentifier, signal: signal)
		if process.isRunning {
			if signal == SIGTERM {
				process.terminate()
			} else {
				kill(process.processIdentifier, signal)
			}
		}
	}

	private func terminatePIDTree(_ pid: pid_t, signal: Int32) {
		guard pid > 0 else { return }
		for child in childPIDs(of: pid) {
			terminatePIDTree(child, signal: signal)
		}
		kill(pid, signal)
	}

	private func childPIDs(of pid: pid_t) -> [pid_t] {
		let pgrep = Process()
		pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
		pgrep.arguments = ["-P", "\(pid)"]
		let pipe = Pipe()
		pgrep.standardOutput = pipe
		pgrep.standardError = FileHandle.nullDevice
		do {
			try pgrep.run()
			pgrep.waitUntilExit()
		} catch {
			return []
		}
		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		let output = String(data: data, encoding: .utf8) ?? ""
		return output
			.split(whereSeparator: \.isNewline)
			.compactMap { pid_t(String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
	}
}

private struct ShellRunOutcome: Sendable {
	var result: TriggerExecutionResult
	var outputToLog: String?
}

private final class LockedDataBuffer: @unchecked Sendable {
	private let lock = NSLock()
	private let maxBytes: Int
	private var storage = Data()
	private var didTruncate = false

	init(maxBytes: Int) {
		self.maxBytes = max(1, maxBytes)
	}

	var data: Data {
		lock.lock()
		defer { lock.unlock() }
		return storage
	}

	var truncated: Bool {
		lock.lock()
		defer { lock.unlock() }
		return didTruncate
	}

	func append(_ data: Data) {
		lock.lock()
		let remaining = maxBytes - storage.count
		if remaining > 0 {
			storage.append(data.prefix(remaining))
		}
		if data.count > remaining {
			didTruncate = true
		}
		lock.unlock()
	}
}
