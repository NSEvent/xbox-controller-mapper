import XCTest
import TriggerKitCore
@testable import TriggerKitRuntime

@MainActor
final class AutomationExecutorPolicyTests: XCTestCase {

	// MARK: - Step override hook

	func testStepOverrideReplacesNativeExecution() async {
		let input = RecordingInputSimulator()
		let executor = AutomationExecutor(input: input)
		var overriddenSteps: [AutomationStep.Kind] = []

		let result = await executor.execute(
			AutomationProgram(name: "Override", steps: [.keyPress(KeyStroke(key: .return))]),
			context: TriggerExecutionContext(stepOverride: { step in
				overriddenSteps.append(step.kind)
				return .success("handled by host")
			})
		)

		XCTAssertEqual(result, .success("Completed 1 step(s)"))
		XCTAssertEqual(overriddenSteps, [.keyPress])
		XCTAssertTrue(input.keyPresses.isEmpty, "Override should bypass the input simulator")
	}

	func testStepOverrideReturningNilFallsThroughToNativeExecution() async {
		let input = RecordingInputSimulator()
		let executor = AutomationExecutor(input: input)

		let result = await executor.execute(
			AutomationProgram(name: "Fallthrough", steps: [.keyPress(KeyStroke(key: .return))]),
			context: TriggerExecutionContext(stepOverride: { _ in nil })
		)

		XCTAssertEqual(result, .success("Completed 1 step(s)"))
		XCTAssertEqual(input.keyPresses.count, 1)
	}

	func testStepOverrideFailureStopsProgram() async {
		let input = RecordingInputSimulator()
		let executor = AutomationExecutor(input: input)

		let result = await executor.execute(
			AutomationProgram(name: "Fail", steps: [
				.custom(CustomStep(namespace: "app.fails")),
				.keyPress(KeyStroke(key: .return))
			]),
			context: TriggerExecutionContext(stepOverride: { step in
				if case .custom = step { return .failure("host error") }
				return nil
			})
		)

		XCTAssertEqual(result, .failure("host error"))
		XCTAssertTrue(input.keyPresses.isEmpty, "Steps after a failure should not run")
	}

	// MARK: - Custom steps

	func testCustomStepWithoutOverrideFailsWithNamespace() async {
		let executor = AutomationExecutor(input: RecordingInputSimulator())

		let result = await executor.execute(
			AutomationProgram(name: "Unhandled", steps: [
				.custom(CustomStep(namespace: "controllerkeys.obs-websocket"))
			])
		)

		XCTAssertEqual(result, .failure("No handler for app action: controllerkeys.obs-websocket"))
	}

	func testCustomStepHandledByOverrideSucceeds() async {
		let executor = AutomationExecutor(input: RecordingInputSimulator())
		var handledPayloads: [String] = []

		let result = await executor.execute(
			AutomationProgram(name: "Handled", steps: [
				.custom(CustomStep(namespace: "app.test", payload: #"{"x":1}"#))
			]),
			context: TriggerExecutionContext(stepOverride: { step in
				guard case .custom(let custom) = step, custom.namespace == "app.test" else { return nil }
				handledPayloads.append(custom.payload)
				return .success("done")
			})
		)

		XCTAssertEqual(result, .success("Completed 1 step(s)"))
		XCTAssertEqual(handledPayloads, [#"{"x":1}"#])
	}

	// MARK: - Concurrency policy

	func testConcurrentPolicyRunsProgramsInParallel() async {
		let executor = AutomationExecutor(input: RecordingInputSimulator())
		let context = TriggerExecutionContext(
			policy: TriggerExecutionPolicy(concurrencyPolicy: .concurrent)
		)
		let program = AutomationProgram(name: "Sleepy", steps: [.delay(DelayStep(seconds: 0.2))])

		let start = Date()
		async let first = executor.execute(program, context: context)
		async let second = executor.execute(program, context: context)
		let results = await [first, second]
		let elapsed = Date().timeIntervalSince(start)

		XCTAssertTrue(results.allSatisfy(\.isSuccess))
		XCTAssertLessThan(elapsed, 0.39, "Concurrent programs should overlap, not queue")
	}

	func testRejectPolicyStillRejectsWhileConcurrentRunIgnoresGate() async {
		let executor = AutomationExecutor(input: RecordingInputSimulator())
		let queuedContext = TriggerExecutionContext(
			policy: TriggerExecutionPolicy(concurrencyPolicy: .reject)
		)
		let concurrentContext = TriggerExecutionContext(
			policy: TriggerExecutionPolicy(concurrencyPolicy: .concurrent)
		)

		async let gated = executor.execute(
			AutomationProgram(name: "Gated", steps: [.delay(DelayStep(seconds: 0.25))]),
			context: queuedContext
		)
		try? await Task.sleep(nanoseconds: 50_000_000)
		let concurrent = await executor.execute(
			AutomationProgram(name: "Free", steps: [.delay(DelayStep(seconds: 0))]),
			context: concurrentContext
		)
		let gatedResult = await gated

		XCTAssertTrue(gatedResult.isSuccess)
		XCTAssertTrue(concurrent.isSuccess, "Concurrent policy should not be blocked by the gate")
	}

	// MARK: - Continue on failure

	func testContinueOnStepFailureRunsRemainingSteps() async {
		let input = RecordingInputSimulator()
		let executor = AutomationExecutor(input: input)
		var logged: [String] = []

		let result = await executor.execute(
			AutomationProgram(name: "Resilient", steps: [
				.custom(CustomStep(namespace: "app.unhandled")),
				.keyPress(KeyStroke(key: .return))
			]),
			context: TriggerExecutionContext(
				logger: { logged.append($0) },
				policy: TriggerExecutionPolicy(continuesOnStepFailure: true)
			)
		)

		XCTAssertEqual(result, .success("Completed 2 step(s), 1 failed"))
		XCTAssertEqual(input.keyPresses.count, 1, "Steps after the failure should still run")
		XCTAssertEqual(logged, ["Step failed: No handler for app action: app.unhandled"])
	}

	// MARK: - URL scheme policy

	func testOpenURLBlockedBySchemeAllowlist() async {
		let executor = AutomationExecutor(input: RecordingInputSimulator())
		let context = TriggerExecutionContext(
			policy: TriggerExecutionPolicy(allowedURLSchemes: ["http", "https"])
		)

		let result = await executor.execute(
			AutomationProgram(name: "Blocked", steps: [
				.openURL(OpenURLStep(url: "file:///etc/hosts"))
			]),
			context: context
		)

		XCTAssertEqual(result, .failure("URL scheme not allowed: file"))
	}

	func testOpenURLSchemeAllowlistIsCaseInsensitive() async {
		let executor = AutomationExecutor(input: RecordingInputSimulator())
		let context = TriggerExecutionContext(
			policy: TriggerExecutionPolicy(allowedURLSchemes: ["HTTPS"])
		)

		let result = await executor.execute(
			AutomationProgram(name: "Blocked", steps: [
				.openURL(OpenURLStep(url: "FILE:///etc/hosts"))
			]),
			context: context
		)

		XCTAssertEqual(result, .failure("URL scheme not allowed: file"))
	}

	// MARK: - Webhooks

	func testWebhookSuccessOnHTTP200() async {
		StubURLProtocol.handler = { request in
			XCTAssertEqual(request.httpMethod, "PUT")
			XCTAssertEqual(request.value(forHTTPHeaderField: "X-Test"), "1")
			return (200, Data())
		}
		let executor = AutomationExecutor(input: RecordingInputSimulator())

		let result = await executor.execute(
			AutomationProgram(name: "Hook", steps: [
				.webhook(WebhookStep(url: "https://example.com/hook", method: .put, headers: ["X-Test": "1"], body: #"{"v":2}"#))
			]),
			context: TriggerExecutionContext(urlSession: StubURLProtocol.session())
		)

		XCTAssertEqual(result, .success("Completed 1 step(s)"))
	}

	func testWebhookFailureOnHTTPError() async {
		StubURLProtocol.handler = { _ in (503, Data()) }
		let executor = AutomationExecutor(input: RecordingInputSimulator())

		let result = await executor.execute(
			AutomationProgram(name: "Hook", steps: [
				.webhook(WebhookStep(url: "https://example.com/hook"))
			]),
			context: TriggerExecutionContext(urlSession: StubURLProtocol.session())
		)

		XCTAssertEqual(result, .failure("Webhook HTTP 503"))
	}

	func testWebhookTimeoutFailure() async {
		StubURLProtocol.error = URLError(.timedOut)
		defer { StubURLProtocol.error = nil }
		let executor = AutomationExecutor(input: RecordingInputSimulator())

		let result = await executor.execute(
			AutomationProgram(name: "Hook", steps: [
				.webhook(WebhookStep(url: "https://example.com/hook", timeoutSeconds: 1))
			]),
			context: TriggerExecutionContext(urlSession: StubURLProtocol.session())
		)

		XCTAssertEqual(result, .failure(URLError(.timedOut).localizedDescription))
	}

	func testWebhookRejectsNonHTTPURL() async {
		let executor = AutomationExecutor(input: RecordingInputSimulator())

		let result = await executor.execute(
			AutomationProgram(name: "Hook", steps: [
				.webhook(WebhookStep(url: "ftp://example.com"))
			])
		)

		XCTAssertEqual(result, .failure("Invalid webhook URL"))
	}
}

// MARK: - Test doubles

private final class RecordingInputSimulator: InputSimulating {
	private(set) var keyPresses: [KeyStroke] = []

	func keyPress(_ stroke: KeyStroke) async { keyPresses.append(stroke) }
	func keyDown(_ event: KeyEvent) {}
	func keyUp(_ event: KeyEvent) {}
	func mouseClick(_ click: MouseClick) {}
	func mouseDown(_ event: MouseButtonEvent) {}
	func mouseUp(_ event: MouseButtonEvent) {}
	func mouseMove(_ move: MouseMove) {}
	func mouseScroll(_ scroll: MouseScroll) {}
	func typeText(_ step: TypeTextStep) async {}
}

private final class StubURLProtocol: URLProtocol {
	nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
	nonisolated(unsafe) static var error: Error?

	static func session() -> URLSession {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.protocolClasses = [StubURLProtocol.self]
		return URLSession(configuration: configuration)
	}

	override static func canInit(with request: URLRequest) -> Bool { true }
	override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

	override func startLoading() {
		if let error = Self.error {
			client?.urlProtocol(self, didFailWithError: error)
			return
		}
		guard let handler = Self.handler, let url = request.url else {
			client?.urlProtocol(self, didFailWithError: URLError(.badURL))
			return
		}
		let (status, data) = handler(request)
		let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
		client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
		client?.urlProtocol(self, didLoad: data)
		client?.urlProtocolDidFinishLoading(self)
	}

	override func stopLoading() {}
}
