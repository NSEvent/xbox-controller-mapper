import XCTest
import TriggerKitCore
@testable import TriggerKitRuntime

@MainActor
final class AutomationExecutorTests: XCTestCase {
	func testExecutorRunsInputStepsInOrder() async {
		let input = FakeInputSimulator()
		let executor = AutomationExecutor(input: input)
		let keyStroke = KeyStroke(key: .tab, modifiers: ModifierSet(command: .left))
		let keyDown = KeyEvent(key: .escape, modifiers: ModifierSet(shift: .left))
		let keyUp = KeyEvent(key: .escape, modifiers: ModifierSet(shift: .left))
		let text = TypeTextStep(text: "hello", mode: .type, pressReturn: true)
		let move = MouseMove(deltaX: 12, deltaY: -8)
		let scroll = MouseScroll(deltaX: 1, deltaY: -2)
		let click = MouseClick(button: .right, clickCount: 2, modifiers: ModifierSet(command: .left))
		let mouseDown = MouseButtonEvent(button: .middle, modifiers: ModifierSet(option: .any))
		let mouseUp = MouseButtonEvent(button: .middle, modifiers: ModifierSet(option: .any))

		let result = await executor.execute(AutomationProgram(name: "Input", steps: [
			.keyPress(keyStroke),
			.keyDown(keyDown),
			.keyUp(keyUp),
			.mouseClick(click),
			.mouseDown(mouseDown),
			.mouseUp(mouseUp),
			.mouseMove(move),
			.mouseScroll(scroll),
			.delay(DelayStep(seconds: 0)),
			.typeText(text)
		]))

		XCTAssertEqual(result, .success("Completed 10 step(s)"))
		XCTAssertEqual(input.calls, [
			.keyPress(keyStroke),
			.keyDown(keyDown),
			.keyUp(keyUp),
			.mouseClick(click),
			.mouseDown(mouseDown),
			.mouseUp(mouseUp),
			.mouseMove(move),
			.mouseScroll(scroll),
			.typeText(text)
		])
	}

	func testExecutorRunsPrepareTargetBeforeSteps() async {
		var events: [String] = []
		let input = FakeInputSimulator { call in
			events.append("input:\(call.label)")
		}
		let executor = AutomationExecutor(input: input)

		let result = await executor.execute(
			AutomationProgram(name: "Prepare", steps: [.keyPress(KeyStroke(key: .return))]),
			context: TriggerExecutionContext(prepareTarget: {
				events.append("prepare")
			})
		)

		XCTAssertEqual(result, .success("Completed 1 step(s)"))
		XCTAssertEqual(events, ["prepare", "input:keyPress(Return)"])
		XCTAssertEqual(input.calls, [.keyPress(KeyStroke(key: .return))])
	}

	func testExecutorAwaitsAsyncKeyPressBeforeNextStep() async {
		let input = SequencedInputSimulator()
		let executor = AutomationExecutor(input: input)

		let result = await executor.execute(AutomationProgram(name: "Sequenced", steps: [
			.keyPress(KeyStroke(key: .mediaPlayPause)),
			.keyDown(KeyEvent(key: .return))
		]))

		XCTAssertEqual(result, .success("Completed 2 step(s)"))
		XCTAssertEqual(input.events, ["keyPress-start", "keyPress-end", "keyDown"])
	}

	func testExecutorSerializesConcurrentExecutions() async {
		let input = SequencedInputSimulator()
		let firstExecutor = AutomationExecutor(input: input)
		let secondExecutor = AutomationExecutor(input: input)
		let first = Task { @MainActor in
			await firstExecutor.execute(AutomationProgram(name: "First", steps: [
				.keyPress(KeyStroke(key: .mediaPlayPause)),
				.keyDown(KeyEvent(key: .return))
			]))
		}
		try? await Task.sleep(nanoseconds: 5_000_000)
		let second = Task { @MainActor in
			await secondExecutor.execute(AutomationProgram(name: "Second", steps: [
				.keyPress(KeyStroke(key: .tab))
			]))
		}

		let firstResult = await first.value
		let secondResult = await second.value

		XCTAssertEqual(firstResult, .success("Completed 2 step(s)"))
		XCTAssertEqual(secondResult, .success("Completed 1 step(s)"))
		XCTAssertEqual(input.events, ["keyPress-start", "keyPress-end", "keyDown", "keyPress-start", "keyPress-end"])
	}

	func testRejectPolicyFailsWhenExecutionIsAlreadyRunning() async {
		let input = SequencedInputSimulator()
		let firstExecutor = AutomationExecutor(input: input)
		let secondExecutor = AutomationExecutor(input: input)
		let context = TriggerExecutionContext(policy: TriggerExecutionPolicy(concurrencyPolicy: .reject))
		let first = Task { @MainActor in
			await firstExecutor.execute(
				AutomationProgram(name: "First", steps: [.keyPress(KeyStroke(key: .mediaPlayPause))]),
				context: context
			)
		}
		try? await Task.sleep(nanoseconds: 5_000_000)

		let secondResult = await secondExecutor.execute(AutomationProgram(name: "Second"), context: context)
		let firstResult = await first.value

		XCTAssertEqual(secondResult, .failure("Another automation is already running"))
		XCTAssertEqual(firstResult, .success("Completed 1 step(s)"))
	}

	func testQueuedExecutionCancellationPreventsLaterRun() async {
		let firstInput = SequencedInputSimulator()
		let secondInput = FakeInputSimulator()
		let firstExecutor = AutomationExecutor(input: firstInput)
		let secondExecutor = AutomationExecutor(input: secondInput)
		let first = Task { @MainActor in
			await firstExecutor.execute(AutomationProgram(name: "First", steps: [
				.keyPress(KeyStroke(key: .mediaPlayPause))
			]))
		}
		try? await Task.sleep(nanoseconds: 5_000_000)
		let second = Task { @MainActor in
			await secondExecutor.execute(AutomationProgram(name: "Second", steps: [
				.keyPress(KeyStroke(key: .tab))
			]))
		}

		try? await Task.sleep(nanoseconds: 5_000_000)
		second.cancel()

		let secondResult = await second.value
		let firstResult = await first.value

		XCTAssertEqual(secondResult, .failure("Cancelled"))
		XCTAssertEqual(firstResult, .success("Completed 1 step(s)"))
		XCTAssertTrue(secondInput.calls.isEmpty)

		let followUp = await secondExecutor.execute(AutomationProgram(name: "Follow-up", steps: [
			.keyPress(KeyStroke(key: .tab))
		]))

		XCTAssertEqual(followUp, .success("Completed 1 step(s)"))
		XCTAssertEqual(secondInput.calls, [.keyPress(KeyStroke(key: .tab))])
	}

	func testExecutorStopsWhenPrepareTargetFails() async {
		let input = FakeInputSimulator()
		let executor = AutomationExecutor(input: input)

		let result = await executor.execute(
			AutomationProgram(name: "Prepare", steps: [.keyPress(KeyStroke(key: .return))]),
			context: TriggerExecutionContext(prepareTarget: {
				throw TestError.prepareFailed
			})
		)

		XCTAssertEqual(result, .failure("prepare failed"))
		XCTAssertTrue(input.calls.isEmpty)
	}

	func testExecutorRejectsDisallowedActionsBeforeRunning() async {
		let input = FakeInputSimulator()
		let executor = AutomationExecutor(input: input)
		let result = await executor.execute(
			AutomationProgram(name: "Disallowed", steps: [
				.shellCommand(ShellCommandStep(command: "echo should-not-run"))
			]),
			context: TriggerExecutionContext(policy: TriggerExecutionPolicy(capabilities: .inputOnly))
		)

		XCTAssertEqual(result, .failure("Action not allowed: Shell Command"))
		XCTAssertTrue(input.calls.isEmpty)
	}

	func testExecutorReportsMissingAccessibilityBeforeInputActions() async {
		let input = UnavailableInputSimulator()
		let executor = AutomationExecutor(input: input)

		let result = await executor.execute(AutomationProgram(name: "Input", steps: [
			.keyPress(KeyStroke(key: .return))
		]))

		XCTAssertEqual(result, .failure("Accessibility permission is required for input actions"))
		XCTAssertTrue(input.calls.isEmpty)
	}

	func testExecutorReportsEmptyProgram() async {
		let executor = AutomationExecutor(input: FakeInputSimulator())

		let result = await executor.execute(AutomationProgram(name: "Empty"))

		XCTAssertEqual(result, .success("No actions"))
	}

	func testExecutorCancelsDelayStep() async {
		let executor = AutomationExecutor(input: FakeInputSimulator())
		let task = Task { @MainActor in
			await executor.execute(AutomationProgram(name: "Delay", steps: [.delay(DelayStep(seconds: 5))]))
		}

		try? await Task.sleep(nanoseconds: 10_000_000)
		task.cancel()

		let result = await task.value
		XCTAssertEqual(result, .failure("Cancelled"))
	}

	func testExecutorReleasesHeldInputsWhenStepFailureAbortsProgram() async {
		let input = FakeInputSimulator()
		let executor = AutomationExecutor(input: input)
		let key = KeyEvent(key: .escape, modifiers: ModifierSet(shift: .left))
		let mouse = MouseButtonEvent(button: .right, modifiers: ModifierSet(command: .left))

		let result = await executor.execute(
			AutomationProgram(name: "Abort", steps: [
				.keyDown(key),
				.mouseDown(mouse),
				.delay(DelayStep(seconds: 0)),
				.keyUp(key),
				.mouseUp(mouse)
			]),
			context: TriggerExecutionContext(stepOverride: { step in
				if case .delay = step {
					return .failure("boom")
				}
				return nil
			})
		)

		XCTAssertEqual(result, .failure("boom"))
		XCTAssertEqual(input.calls, [
			.keyDown(key),
			.mouseDown(mouse),
			.mouseUp(mouse),
			.keyUp(key)
		])
	}

	func testExecutorReleasesHeldInputsWhenContinuingAfterFailure() async {
		let input = FakeInputSimulator()
		let executor = AutomationExecutor(input: input)
		let key = KeyEvent(key: .escape)
		let trailingPress = KeyStroke(key: .return)
		var logs: [String] = []

		let result = await executor.execute(
			AutomationProgram(name: "Continue", steps: [
				.keyDown(key),
				.delay(DelayStep(seconds: 0)),
				.keyPress(trailingPress)
			]),
			context: TriggerExecutionContext(
				logger: { logs.append($0) },
				policy: TriggerExecutionPolicy(continuesOnStepFailure: true),
				stepOverride: { step in
					if case .delay = step {
						return .failure("boom")
					}
					return nil
				}
			)
		)

		XCTAssertEqual(result, .success("Completed 3 step(s), 1 failed"))
		XCTAssertEqual(logs, ["Step failed: boom"])
		XCTAssertEqual(input.calls, [
			.keyDown(key),
			.keyPress(trailingPress),
			.keyUp(key)
		])
	}

	func testExecutorReleasesHeldInputsWhenCancelled() async {
		let input = FakeInputSimulator()
		let executor = AutomationExecutor(input: input)
		let key = KeyEvent(key: .tab)
		let task = Task { @MainActor in
			await executor.execute(AutomationProgram(name: "Cancel Held", steps: [
				.keyDown(key),
				.delay(DelayStep(seconds: 5)),
				.keyUp(key)
			]))
		}

		try? await Task.sleep(nanoseconds: 10_000_000)
		task.cancel()

		let result = await task.value
		XCTAssertEqual(result, .failure("Cancelled"))
		XCTAssertEqual(input.calls, [
			.keyDown(key),
			.keyUp(key)
		])
	}

	func testExecutorReleasesHeldInputsWhenConditionSkipsRemainder() async {
		let input = FakeInputSimulator()
		let executor = AutomationExecutor(input: input)
		let key = KeyEvent(key: .space)

		let result = await executor.execute(AutomationProgram(name: "Condition Skip", steps: [
			.keyDown(key),
			.condition(ConditionStep(kind: .appRunning, bundleIdentifier: "com.triggerkit.tests.missing-app")),
			.keyUp(key)
		]))

		XCTAssertEqual(result, .success("Skipped — Only if com.triggerkit.tests.missing-app running"))
		XCTAssertEqual(input.calls, [
			.keyDown(key),
			.keyUp(key)
		])
	}

	func testShellCommandSuccessReturnsOutputAndLogsIt() async {
		let executor = AutomationExecutor(input: FakeInputSimulator())
		var logs: [String] = []
		let result = await executor.execute(
			AutomationProgram(name: "Shell", steps: [
				.shellCommand(ShellCommandStep(command: #"printf "$TRIGGERKIT_TEST_VALUE""#, shellPath: "/bin/sh"))
			]),
			context: TriggerExecutionContext(environment: ["TRIGGERKIT_TEST_VALUE": "hello"], logger: { logs.append($0) })
		)

		XCTAssertEqual(result, .success("Completed 1 step(s)"))
		XCTAssertEqual(logs, ["hello"])
	}

	func testShellCommandDrainsLargeOutputWithoutDeadlocking() async throws {
		let executor = AutomationExecutor(input: FakeInputSimulator())
		var logs: [String] = []
		let result = await executor.execute(
			AutomationProgram(name: "Large Shell Output", steps: [
				.shellCommand(ShellCommandStep(command: "yes 0123456789 | head -c 200000", shellPath: "/bin/sh", timeoutSeconds: 3))
			]),
			context: TriggerExecutionContext(logger: { logs.append($0) })
		)

		XCTAssertEqual(result, .success("Completed 1 step(s)"))
		let output = try XCTUnwrap(logs.first)
		XCTAssertGreaterThan(output.count, 100_000)
	}

	func testShellCommandOutputIsBoundedByPolicy() async throws {
		let executor = AutomationExecutor(input: FakeInputSimulator())
		var logs: [String] = []
		let result = await executor.execute(
			AutomationProgram(name: "Bounded Shell Output", steps: [
				.shellCommand(ShellCommandStep(command: "yes abcdefghij | head -c 5000", shellPath: "/bin/sh", timeoutSeconds: 3))
			]),
			context: TriggerExecutionContext(
				logger: { logs.append($0) },
				policy: TriggerExecutionPolicy(maximumShellOutputBytes: 64)
			)
		)

		XCTAssertEqual(result, .success("Completed 1 step(s)"))
		let output = try XCTUnwrap(logs.first)
		XCTAssertLessThan(output.count, 120)
		XCTAssertTrue(output.hasSuffix("[output truncated]"))
	}

	func testShellCommandFailureStopsProgram() async {
		let input = FakeInputSimulator()
		let executor = AutomationExecutor(input: input)
		let result = await executor.execute(AutomationProgram(name: "Shell", steps: [
			.shellCommand(ShellCommandStep(command: "exit 7", shellPath: "/bin/sh")),
			.keyPress(KeyStroke(key: .return))
		]))

		XCTAssertEqual(result, .failure("Shell exit 7"))
		XCTAssertTrue(input.calls.isEmpty)
	}

	func testShellCommandCancellationStopsRunningProcess() async {
		let executor = AutomationExecutor(input: FakeInputSimulator())
		let task = Task { @MainActor in
			await executor.execute(AutomationProgram(name: "Shell Cancel", steps: [
				.shellCommand(ShellCommandStep(command: "sleep 5", shellPath: "/bin/sh", timeoutSeconds: 10))
			]))
		}

		try? await Task.sleep(nanoseconds: 20_000_000)
		task.cancel()

		let result = await task.value
		XCTAssertEqual(result, .failure("Cancelled"))
	}
}

private enum TestError: LocalizedError {
	case prepareFailed

	var errorDescription: String? {
		switch self {
		case .prepareFailed:
			return "prepare failed"
		}
	}
}

private enum RecordedInputCall: Equatable {
	case keyPress(KeyStroke)
	case keyDown(KeyEvent)
	case keyUp(KeyEvent)
	case mouseClick(MouseClick)
	case mouseDown(MouseButtonEvent)
	case mouseUp(MouseButtonEvent)
	case mouseMove(MouseMove)
	case mouseScroll(MouseScroll)
	case typeText(TypeTextStep)

	var label: String {
		switch self {
		case .keyPress(let stroke): return "keyPress(\(stroke.displaySummary))"
		case .keyDown(let event): return "keyDown(\(event.displaySummary))"
		case .keyUp(let event): return "keyUp(\(event.displaySummary))"
		case .mouseClick(let click): return "mouseClick(\(click.displaySummary))"
		case .mouseDown(let event): return "mouseDown(\(event.displaySummary))"
		case .mouseUp(let event): return "mouseUp(\(event.displaySummary))"
		case .mouseMove(let move): return "mouseMove(\(move.deltaX),\(move.deltaY))"
		case .mouseScroll(let scroll): return "mouseScroll(\(scroll.displaySummary))"
		case .typeText(let step): return "typeText(\(step.displaySummary))"
		}
	}
}

@MainActor
private final class UnavailableInputSimulator: InputSimulating {
	var calls: [RecordedInputCall] = []
	var isInputPostingAvailable: Bool { false }

	func keyPress(_ stroke: KeyStroke) async {
		calls.append(.keyPress(stroke))
	}

	func keyDown(_ event: KeyEvent) {
		calls.append(.keyDown(event))
	}

	func keyUp(_ event: KeyEvent) {
		calls.append(.keyUp(event))
	}

	func mouseClick(_ click: MouseClick) {
		calls.append(.mouseClick(click))
	}

	func mouseDown(_ event: MouseButtonEvent) {
		calls.append(.mouseDown(event))
	}

	func mouseUp(_ event: MouseButtonEvent) {
		calls.append(.mouseUp(event))
	}

	func mouseMove(_ move: MouseMove) {
		calls.append(.mouseMove(move))
	}

	func mouseScroll(_ scroll: MouseScroll) {
		calls.append(.mouseScroll(scroll))
	}

	func typeText(_ step: TypeTextStep) async {
		calls.append(.typeText(step))
	}
}

@MainActor
private final class FakeInputSimulator: InputSimulating {
	var calls: [RecordedInputCall] = []
	private let onCall: (RecordedInputCall) -> Void

	init(onCall: @escaping (RecordedInputCall) -> Void = { _ in }) {
		self.onCall = onCall
	}

	func keyPress(_ stroke: KeyStroke) async {
		record(.keyPress(stroke))
	}

	func keyDown(_ event: KeyEvent) {
		record(.keyDown(event))
	}

	func keyUp(_ event: KeyEvent) {
		record(.keyUp(event))
	}

	func mouseClick(_ click: MouseClick) {
		record(.mouseClick(click))
	}

	func mouseDown(_ event: MouseButtonEvent) {
		record(.mouseDown(event))
	}

	func mouseUp(_ event: MouseButtonEvent) {
		record(.mouseUp(event))
	}

	func mouseMove(_ move: MouseMove) {
		record(.mouseMove(move))
	}

	func mouseScroll(_ scroll: MouseScroll) {
		record(.mouseScroll(scroll))
	}

	func typeText(_ step: TypeTextStep) async {
		record(.typeText(step))
	}

	private func record(_ call: RecordedInputCall) {
		calls.append(call)
		onCall(call)
	}
}

@MainActor
private final class SequencedInputSimulator: InputSimulating {
	var events: [String] = []

	func keyPress(_ stroke: KeyStroke) async {
		events.append("keyPress-start")
		try? await Task.sleep(nanoseconds: 20_000_000)
		events.append("keyPress-end")
	}

	func keyDown(_ event: KeyEvent) {
		events.append("keyDown")
	}

	func keyUp(_ event: KeyEvent) {
		events.append("keyUp")
	}

	func mouseClick(_ click: MouseClick) {}
	func mouseDown(_ event: MouseButtonEvent) {}
	func mouseUp(_ event: MouseButtonEvent) {}
	func mouseMove(_ move: MouseMove) {}
	func mouseScroll(_ scroll: MouseScroll) {}
	func typeText(_ step: TypeTextStep) async {}
}
