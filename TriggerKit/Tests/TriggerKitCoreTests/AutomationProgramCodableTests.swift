import XCTest
@testable import TriggerKitCore

final class AutomationProgramCodableTests: XCTestCase {
	func testProgramRoundTripsThroughJSON() throws {
		let program = AutomationProgram(
			id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
			name: "Send message",
			steps: [
				.typeText(TypeTextStep(text: "hello", mode: .paste, pressReturn: true)),
				.delay(DelayStep(seconds: 1.5)),
				.keyPress(KeyStroke(key: .return, modifiers: ModifierSet(command: .left, shift: .right))),
				.mouseClick(MouseClick(button: .right, clickCount: 2, modifiers: ModifierSet(control: .any))),
				.shellCommand(ShellCommandStep(command: "echo done"))
			]
		)

		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		let data = try encoder.encode(program)
		let decoded = try JSONDecoder().decode(AutomationProgram.self, from: data)

		XCTAssertEqual(decoded, program)
	}

	func testAllStepKindsRoundTripThroughJSON() throws {
		let steps: [AutomationStep] = [
			.keyPress(KeyStroke(key: .tab, modifiers: ModifierSet(command: .left, option: .right))),
			.keyDown(KeyEvent(key: .escape, modifiers: ModifierSet(command: .left))),
			.keyUp(KeyEvent(key: .escape, modifiers: ModifierSet(command: .left))),
			.mouseClick(MouseClick(button: .middle, clickCount: 3, modifiers: ModifierSet(shift: .any))),
			.mouseDown(MouseButtonEvent(button: .back, modifiers: ModifierSet(command: .left))),
			.mouseUp(MouseButtonEvent(button: .forward, modifiers: ModifierSet(command: .left))),
			.mouseMove(MouseMove(deltaX: -12.5, deltaY: 44.25)),
			.mouseScroll(MouseScroll(deltaX: -2, deltaY: 9)),
			.delay(DelayStep(seconds: 12.75)),
			.typeText(TypeTextStep(text: "line 1\nline 2", mode: .type, pressReturn: true)),
			.openApp(OpenAppStep(bundleIdentifier: "com.apple.TextEdit", openNewWindow: true)),
			.openURL(OpenURLStep(url: "https://kevintang.xyz")),
			.shellCommand(ShellCommandStep(command: "echo hi", shellPath: "/bin/sh", timeoutSeconds: 4, runsInTerminal: true)),
			.webhook(WebhookStep(url: "https://example.com/hook", method: .put, headers: ["X-Token": "abc"], body: "{\"ok\":true}", timeoutSeconds: 6)),
			.clipboard(ClipboardStep(text: "copied text")),
			.systemSetting(SystemSettingStep(action: .setVolume, volume: 65)),
			.condition(ConditionStep(kind: .timeWindow, negate: true, bundleIdentifier: "com.spotify.client", startMinutes: 9 * 60, endMinutes: 22 * 60)),
			.custom(CustomStep(namespace: "controllerkeys.obs-websocket", payload: "{\"requestType\":\"ToggleRecord\"}", displayName: "OBS: ToggleRecord"))
		]

		XCTAssertEqual(Set(steps.map(\.kind)), Set(AutomationStep.Kind.allCases))

		for step in steps {
			let data = try JSONEncoder().encode(step)
			let decoded = try JSONDecoder().decode(AutomationStep.self, from: data)
			XCTAssertEqual(decoded, step)
			XCTAssertEqual(decoded.kind, step.kind)
		}
	}

	func testStepKindIsStableInEncodedJSON() throws {
		let program = AutomationProgram(
			name: "Shortcut",
			steps: [
				.keyPress(KeyStroke(key: TriggerKey(id: "k", keyCode: 40, displayName: "K"), modifiers: ModifierSet(command: .any)))
			]
		)

		let data = try JSONEncoder().encode(program)
		let json = String(data: data, encoding: .utf8) ?? ""

		XCTAssertTrue(json.contains(#""kind":"keyPress""#))
		XCTAssertTrue(json.contains(#""keyStroke""#))
		XCTAssertTrue(json.contains(#""command":"any""#))
	}

	func testMouseStepsDecodeOldPayloadsWithoutModifiers() throws {
		let click = try JSONDecoder().decode(MouseClick.self, from: #"{"button":"left","clickCount":2}"#.data(using: .utf8)!)
		let button = try JSONDecoder().decode(MouseButtonEvent.self, from: #"{"button":"right"}"#.data(using: .utf8)!)

		XCTAssertEqual(click, MouseClick(button: .left, clickCount: 2))
		XCTAssertEqual(button, MouseButtonEvent(button: .right))
	}

	func testKeyEventsDecodeOldPayloadsWithoutModifiers() throws {
		let data = #"{"key":{"id":"escape","keyCode":53,"displayName":"Escape"}}"#.data(using: .utf8)!
		let event = try JSONDecoder().decode(KeyEvent.self, from: data)

		XCTAssertEqual(event, KeyEvent(key: .escape))
	}

	func testStableJSONPayloadKeysForEveryStepKind() throws {
		let expectedPayloadKeys: [AutomationStep.Kind: String] = [
			.keyPress: "keyStroke",
			.keyDown: "keyEvent",
			.keyUp: "keyEvent",
			.mouseClick: "mouseClick",
			.mouseDown: "mouseButton",
			.mouseUp: "mouseButton",
			.mouseMove: "mouseMove",
			.mouseScroll: "mouseScroll",
			.delay: "delay",
			.typeText: "typeText",
			.openApp: "openApp",
			.openURL: "openURL",
			.shellCommand: "shellCommand",
			.webhook: "webhook",
			.clipboard: "clipboard",
			.systemSetting: "systemSetting",
			.condition: "condition",
			.custom: "custom"
		]

		for kind in AutomationStep.Kind.allCases {
			let step = AutomationStep.defaultValue(for: kind)
			let data = try JSONEncoder().encode(step)
			let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
			XCTAssertEqual(object["kind"] as? String, kind.rawValue)
			XCTAssertNotNil(object[try XCTUnwrap(expectedPayloadKeys[kind])])
		}
	}

	func testDecodingRejectsMissingPayloadForEveryStepKind() {
		for kind in AutomationStep.Kind.allCases {
			let data = #"{"kind":"\#(kind.rawValue)"}"#.data(using: .utf8)!
			XCTAssertThrowsError(try JSONDecoder().decode(AutomationStep.self, from: data), "Expected missing payload to fail for \(kind.rawValue)")
		}
	}

	func testDecodingRejectsUnknownStepKind() {
		let data = #"{"kind":"holographicGesture","openURL":{"url":"https://example.com"}}"#.data(using: .utf8)!
		XCTAssertThrowsError(try JSONDecoder().decode(AutomationStep.self, from: data))
	}

	func testProgramDecodingRejectsUnsupportedSchemaVersion() {
		let data = #"{"id":"11111111-1111-1111-1111-111111111111","schemaVersion":999,"name":"Future","steps":[]}"#.data(using: .utf8)!

		XCTAssertThrowsError(try JSONDecoder().decode(AutomationProgram.self, from: data))
	}

	func testProgramDecodingAcceptsPreviousSchemaVersion() throws {
		let data = #"{"id":"11111111-1111-1111-1111-111111111111","schemaVersion":1,"name":"Old","steps":[{"kind":"delay","delay":{"seconds":2}}]}"#.data(using: .utf8)!

		let program = try JSONDecoder().decode(AutomationProgram.self, from: data)

		XCTAssertEqual(program.schemaVersion, AutomationProgram.currentSchemaVersion)
		XCTAssertEqual(program.steps, [.delay(DelayStep(seconds: 2))])
	}

	func testProgramDecodingRejectsUnsupportedFutureSteps() {
		let data = """
		{
			"id": "11111111-1111-1111-1111-111111111111",
			"schemaVersion": \(AutomationProgram.currentSchemaVersion),
			"name": "Mixed",
			"steps": [
				{"kind": "delay", "delay": {"seconds": 2}},
				{"kind": "holographicGesture", "holographicGesture": {"angle": 12}},
				{"kind": "openURL", "openURL": {"url": "https://kevintang.xyz"}}
			]
		}
		""".data(using: .utf8)!

		XCTAssertThrowsError(try JSONDecoder().decode(AutomationProgram.self, from: data))
	}

	func testModifierDisplayPreservesSideLabels() {
		let modifiers = ModifierSet(command: .left, option: .right, control: .any, shift: .left, function: true)

		XCTAssertEqual(modifiers.displayString, "LCmd+ROpt+Ctrl+LShift+Fn")
	}

	func testKeyCatalogIncludesControllerKeysParityKeys() {
		let keys = TriggerKey.allCatalogKeys

		XCTAssertTrue(keys.contains(.mediaPlayPause))
		XCTAssertTrue(keys.contains(.volumeUp))
		XCTAssertTrue(keys.contains(.brightnessDown))
		XCTAssertTrue(keys.contains(.help))
		XCTAssertTrue(keys.contains(.capsLock))
		XCTAssertTrue(keys.contains(.function))
		XCTAssertTrue(keys.contains { $0.displayName == "F20" })
		XCTAssertTrue(keys.contains { $0.id == "keypad-enter" })
	}
}
