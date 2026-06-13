import XCTest
@testable import TriggerKitCore

final class AutomationModelTests: XCTestCase {
	func testProgramSummaryHandlesEmptySingleAndMultipleSteps() {
		XCTAssertTrue(AutomationProgram(name: "Empty").isEmpty)
		XCTAssertEqual(AutomationProgram(name: "Empty").displaySummary, "No actions")

		let single = AutomationProgram(name: "Single", steps: [.mouseClick(MouseClick(button: .left))])
		XCTAssertFalse(single.isEmpty)
		XCTAssertEqual(single.displaySummary, "Left click")

		let multiple = AutomationProgram(name: "Multiple", steps: [
			.delay(DelayStep(seconds: 1)),
			.openURL(OpenURLStep(url: "https://example.com"))
		])
		XCTAssertEqual(multiple.displaySummary, "2 steps")
	}

	func testMouseScrollClampsOutOfRangeDeltas() throws {
		// Memberwise init clamps.
		let constructed = MouseScroll(deltaX: 50_000, deltaY: -50_000)
		XCTAssertEqual(constructed.deltaX, MouseScroll.maximumMagnitude)
		XCTAssertEqual(constructed.deltaY, -MouseScroll.maximumMagnitude)

		// didSet clamps post-init mutation.
		var mutable = MouseScroll()
		mutable.deltaY = 99_999
		XCTAssertEqual(mutable.deltaY, MouseScroll.maximumMagnitude)

		// Decoding clamps too (a hostile/corrupt config can't fling the scroll).
		let decoded = try JSONDecoder().decode(MouseScroll.self, from: Data(#"{"deltaX":1000000,"deltaY":5}"#.utf8))
		XCTAssertEqual(decoded.deltaX, MouseScroll.maximumMagnitude)
		XCTAssertEqual(decoded.deltaY, 5)

		// In-range values round-trip unchanged.
		let inRange = MouseScroll(deltaX: 3, deltaY: -4)
		let roundTripped = try JSONDecoder().decode(MouseScroll.self, from: JSONEncoder().encode(inRange))
		XCTAssertEqual(roundTripped, inRange)
	}

	func testRequiresAccessibilityClassifiesInputAndNonInputSteps() {
		let inputSteps: [AutomationStep] = [
			.keyPress(KeyStroke(key: .return)),
			.keyDown(KeyEvent(key: .return)),
			.keyUp(KeyEvent(key: .return)),
			.mouseClick(MouseClick(button: .left)),
			.mouseDown(MouseButtonEvent(button: .left)),
			.mouseUp(MouseButtonEvent(button: .left)),
			.mouseMove(MouseMove(deltaX: 1, deltaY: 1)),
			.mouseScroll(MouseScroll(deltaY: 1)),
			.typeText(TypeTextStep(text: "hello")),
			.openApp(OpenAppStep(bundleIdentifier: "com.apple.TextEdit", openNewWindow: true))
		]
		let nonInputSteps: [AutomationStep] = [
			.delay(DelayStep(seconds: 1)),
			.openApp(OpenAppStep(bundleIdentifier: "com.apple.TextEdit")),
			.openURL(OpenURLStep(url: "https://example.com")),
			.shellCommand(ShellCommandStep(command: "echo hi"))
		]

		for step in inputSteps {
			XCTAssertTrue(step.requiresAccessibility, "\(step.kind.rawValue) should require Accessibility")
		}
		for step in nonInputSteps {
			XCTAssertFalse(step.requiresAccessibility, "\(step.kind.rawValue) should not require Accessibility")
		}

		XCTAssertTrue(AutomationProgram(name: "Input", steps: nonInputSteps + [.keyPress(KeyStroke(key: .return))]).requiresAccessibility)
		XCTAssertFalse(AutomationProgram(name: "System", steps: nonInputSteps).requiresAccessibility)
	}

	func testModelInitializersClampUnsafeValues() {
		XCTAssertEqual(DelayStep(seconds: -10).seconds, 0)
		XCTAssertEqual(DelayStep(seconds: .greatestFiniteMagnitude).seconds, 315_360_000)
		XCTAssertEqual(MouseClick(button: .left, clickCount: -3).clickCount, 1)
		XCTAssertEqual(MouseClick(button: .left, clickCount: 999).clickCount, MouseClick.maximumClickCount)
		XCTAssertEqual(ShellCommandStep(command: "echo hi", timeoutSeconds: 0).timeoutSeconds, 1)
	}

	func testModelMutationClampsUnsafeValues() {
		var delay = DelayStep(seconds: 2)
		delay.seconds = -.infinity
		XCTAssertEqual(delay.seconds, 0)

		var click = MouseClick(button: .left, clickCount: 2)
		click.clickCount = 0
		XCTAssertEqual(click.clickCount, 1)
		click.clickCount = 999
		XCTAssertEqual(click.clickCount, MouseClick.maximumClickCount)

		var shell = ShellCommandStep(command: "echo hi", timeoutSeconds: 2)
		shell.timeoutSeconds = .nan
		XCTAssertEqual(shell.timeoutSeconds, 1)
	}

	func testModelDecodingClampsUnsafeValues() throws {
		let delay = try JSONDecoder().decode(DelayStep.self, from: #"{"seconds":-10}"#.data(using: .utf8)!)
		XCTAssertEqual(delay.seconds, 0)
		let keyEvent = try JSONDecoder().decode(KeyEvent.self, from: #"{"key":{"id":"return","keyCode":36,"displayName":"Return"}}"#.data(using: .utf8)!)
		XCTAssertEqual(keyEvent.modifiers, ModifierSet())

		let click = try JSONDecoder().decode(MouseClick.self, from: #"{"button":"left","clickCount":0}"#.data(using: .utf8)!)
		XCTAssertEqual(click.clickCount, 1)
		XCTAssertEqual(click.modifiers, ModifierSet())
		let highClick = try JSONDecoder().decode(MouseClick.self, from: #"{"button":"left","clickCount":999}"#.data(using: .utf8)!)
		XCTAssertEqual(highClick.clickCount, MouseClick.maximumClickCount)
		let mouseButton = try JSONDecoder().decode(MouseButtonEvent.self, from: #"{"button":"right"}"#.data(using: .utf8)!)
		XCTAssertEqual(mouseButton.modifiers, ModifierSet())

		let shell = try JSONDecoder().decode(ShellCommandStep.self, from: #"{"command":"echo hi","timeoutSeconds":0}"#.data(using: .utf8)!)
		XCTAssertEqual(shell.timeoutSeconds, 1)
	}

	func testDisplaySummariesAreCompactAndStable() {
		XCTAssertEqual(KeyStroke(key: .return).displaySummary, "Return")
		XCTAssertEqual(KeyStroke(key: .return, modifiers: ModifierSet(command: .left, shift: .right)).displaySummary, "LCmd+RShift+Return")
		XCTAssertEqual(KeyEvent(key: .escape, modifiers: ModifierSet(control: .any)).displaySummary, "Ctrl+Escape")
		XCTAssertEqual(MouseClick(button: .right, clickCount: 2).displaySummary, "Right click x2")
		XCTAssertEqual(MouseClick(button: .left, modifiers: ModifierSet(command: .any)).displaySummary, "Cmd+Left click")
		XCTAssertEqual(MouseButtonEvent(button: .middle, modifiers: ModifierSet(option: .right)).displaySummary, "ROpt+Middle")
		XCTAssertEqual(MouseScroll(deltaY: 3).displaySummary, "Scroll up")
		XCTAssertEqual(MouseScroll(deltaY: -3).displaySummary, "Scroll down")
		XCTAssertEqual(MouseScroll(deltaX: 3).displaySummary, "Scroll right")
		XCTAssertEqual(MouseScroll(deltaX: -3).displaySummary, "Scroll left")
		XCTAssertEqual(MouseScroll().displaySummary, "Scroll")
		XCTAssertEqual(TypeTextStep(text: "\n hello\nworld ", pressReturn: true).displaySummary, "hello world + Return")
		XCTAssertEqual(ShellCommandStep(command: "").displaySummary, "Shell command")
		XCTAssertEqual(ShellCommandStep(command: String(repeating: "a", count: 70)).displaySummary.count, 56)
	}

	func testDelayDurationDisplayUsesLargestCoarseUnit() {
		XCTAssertEqual(DelayStep(seconds: 12.4).displayDuration, "12s")
		XCTAssertEqual(DelayStep(seconds: 59.6).displayDuration, "1m")
		XCTAssertEqual(DelayStep(seconds: 60).displayDuration, "1m")
		XCTAssertEqual(DelayStep(seconds: 3_600).displayDuration, "1h")
		XCTAssertEqual(DelayStep(seconds: 86_400).displayDuration, "1d")
	}

	func testDefaultStepFactoryCoversEveryKind() {
		for kind in AutomationStep.Kind.allCases {
			let step = AutomationStep.defaultValue(for: kind)
			XCTAssertEqual(step.kind, kind)
		}
	}

	func testDefaultStepPayloadsMatchEditorExpectations() {
		XCTAssertEqual(AutomationStep.defaultValue(for: .keyPress), .keyPress(KeyStroke(key: .return)))
		XCTAssertEqual(AutomationStep.defaultValue(for: .keyDown), .keyDown(KeyEvent(key: .return)))
		XCTAssertEqual(AutomationStep.defaultValue(for: .keyUp), .keyUp(KeyEvent(key: .return)))
		XCTAssertEqual(AutomationStep.defaultValue(for: .mouseClick), .mouseClick(MouseClick(button: .left)))
		XCTAssertEqual(AutomationStep.defaultValue(for: .mouseScroll), .mouseScroll(MouseScroll(deltaY: -4)))
		XCTAssertEqual(AutomationStep.defaultValue(for: .delay), .delay(DelayStep(seconds: 1)))
		XCTAssertEqual(AutomationStep.defaultValue(for: .typeText), .typeText(TypeTextStep(text: "", mode: .paste, pressReturn: true)))
		XCTAssertEqual(AutomationStep.defaultValue(for: .shellCommand), .shellCommand(ShellCommandStep(command: "")))
	}

	func testCapabilitiesCanRestrictAllowedActions() {
		XCTAssertTrue(AutomationCapabilities.all.allows(.shellCommand))
		XCTAssertTrue(AutomationCapabilities.inputOnly.allows(.keyPress))
		XCTAssertFalse(AutomationCapabilities.inputOnly.allows(.shellCommand))
	}
}
