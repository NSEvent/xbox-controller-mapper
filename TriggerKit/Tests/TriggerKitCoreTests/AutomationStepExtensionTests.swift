import XCTest
@testable import TriggerKitCore

/// Covers the step kinds and fields added for ControllerKeys parity:
/// webhook, custom (host-app) steps, terminal shell commands, and paced typing.
final class AutomationStepExtensionTests: XCTestCase {

	// MARK: - Webhook

	func testWebhookStepRoundTripsThroughJSON() throws {
		let step = AutomationStep.webhook(WebhookStep(
			url: "https://example.com/hook",
			method: .patch,
			headers: ["Authorization": "Bearer x", "X-Source": "test"],
			body: #"{"a":1}"#,
			timeoutSeconds: 25
		))

		let data = try JSONEncoder().encode(step)
		let decoded = try JSONDecoder().decode(AutomationStep.self, from: data)

		XCTAssertEqual(decoded, step)
	}

	func testWebhookStepDecodesMinimalPayloadWithDefaults() throws {
		let data = #"{"kind":"webhook","webhook":{"url":"https://example.com"}}"#.data(using: .utf8)!
		let decoded = try JSONDecoder().decode(AutomationStep.self, from: data)

		XCTAssertEqual(decoded, .webhook(WebhookStep(
			url: "https://example.com",
			method: .post,
			headers: [:],
			body: nil,
			timeoutSeconds: 10
		)))
	}

	func testWebhookStepSanitizesTimeout() {
		XCTAssertEqual(WebhookStep(url: "x", timeoutSeconds: -3).timeoutSeconds, 1)
		XCTAssertEqual(WebhookStep(url: "x", timeoutSeconds: .infinity).timeoutSeconds, 1)
	}

	func testWebhookDisplaySummaryShowsMethodAndURL() {
		let step = WebhookStep(url: "https://example.com/hook", method: .get)
		XCTAssertEqual(step.displaySummary, "GET https://example.com/hook")
	}

	// MARK: - Custom (host app) steps

	func testCustomStepRoundTripsThroughJSON() throws {
		let step = AutomationStep.custom(CustomStep(
			namespace: "controllerkeys.obs-websocket",
			payload: #"{"requestType":"ToggleRecord"}"#,
			displayName: "OBS: ToggleRecord"
		))

		let data = try JSONEncoder().encode(step)
		let decoded = try JSONDecoder().decode(AutomationStep.self, from: data)

		XCTAssertEqual(decoded, step)
	}

	func testCustomStepDisplaySummaryPrefersDisplayName() {
		XCTAssertEqual(
			CustomStep(namespace: "app.thing", payload: "{}", displayName: "Do Thing").displaySummary,
			"Do Thing"
		)
		XCTAssertEqual(CustomStep(namespace: "app.thing").displaySummary, "app.thing")
		XCTAssertEqual(CustomStep(namespace: "").displaySummary, "Custom action")
	}

	// MARK: - Shell terminal flag

	func testShellCommandDecodesLegacyPayloadWithoutTerminalFlag() throws {
		let data = #"{"command":"echo hi","shellPath":"/bin/sh","timeoutSeconds":4}"#.data(using: .utf8)!
		let decoded = try JSONDecoder().decode(ShellCommandStep.self, from: data)

		XCTAssertFalse(decoded.runsInTerminal)
		XCTAssertEqual(decoded.command, "echo hi")
	}

	func testShellCommandTerminalFlagRoundTrips() throws {
		let step = ShellCommandStep(command: "top", runsInTerminal: true)
		let data = try JSONEncoder().encode(step)
		let decoded = try JSONDecoder().decode(ShellCommandStep.self, from: data)

		XCTAssertTrue(decoded.runsInTerminal)
	}

	func testNormalizationPreservesTerminalFlag() {
		let step = AutomationStep.shellCommand(ShellCommandStep(command: "  top  ", runsInTerminal: true))
		guard case .shellCommand(let normalized) = step.normalized() else {
			return XCTFail("Expected shellCommand")
		}
		XCTAssertEqual(normalized.command, "top")
		XCTAssertTrue(normalized.runsInTerminal)
	}

	// MARK: - Paced typing

	func testTypeTextDecodesLegacyPayloadWithoutPace() throws {
		let data = #"{"text":"hello","mode":"type","pressReturn":true}"#.data(using: .utf8)!
		let decoded = try JSONDecoder().decode(TypeTextStep.self, from: data)

		XCTAssertEqual(decoded, TypeTextStep(text: "hello", mode: .type, pressReturn: true))
		XCTAssertNil(decoded.charactersPerMinute)
	}

	func testTypeTextPaceRoundTrips() throws {
		let step = TypeTextStep(text: "hello", mode: .type, pressReturn: false, charactersPerMinute: 300)
		let data = try JSONEncoder().encode(step)
		let decoded = try JSONDecoder().decode(TypeTextStep.self, from: data)

		XCTAssertEqual(decoded.charactersPerMinute, 300)
	}

	func testTypeTextPaceSanitizesNonPositiveValues() {
		XCTAssertNil(TypeTextStep(text: "x", charactersPerMinute: 0).charactersPerMinute)
		XCTAssertNil(TypeTextStep(text: "x", charactersPerMinute: -5).charactersPerMinute)

		var step = TypeTextStep(text: "x", charactersPerMinute: 100)
		step.charactersPerMinute = -1
		XCTAssertNil(step.charactersPerMinute)
	}

	// MARK: - Capabilities and accessibility

	func testNewStepKindsDoNotRequireAccessibility() {
		XCTAssertFalse(AutomationStep.webhook(WebhookStep(url: "x")).requiresAccessibility)
		XCTAssertFalse(AutomationStep.custom(CustomStep(namespace: "x")).requiresAccessibility)
	}

	func testInputOnlyCapabilitiesExcludeWebhookAndCustom() {
		XCTAssertFalse(AutomationCapabilities.inputOnly.allows(.webhook))
		XCTAssertFalse(AutomationCapabilities.inputOnly.allows(.custom))
		XCTAssertTrue(AutomationCapabilities.all.allows(.webhook))
		XCTAssertTrue(AutomationCapabilities.all.allows(.custom))
	}

	func testNormalizationTrimsWebhookURLAndCustomNamespace() {
		guard case .webhook(let webhook) = AutomationStep.webhook(WebhookStep(url: " https://a.com ")).normalized() else {
			return XCTFail("Expected webhook")
		}
		XCTAssertEqual(webhook.url, "https://a.com")

		guard case .custom(let custom) = AutomationStep.custom(CustomStep(namespace: " app.x ")).normalized() else {
			return XCTFail("Expected custom")
		}
		XCTAssertEqual(custom.namespace, "app.x")
	}

	func testDefaultValueMatchesKindForEveryKind() {
		for kind in AutomationStep.Kind.allCases {
			XCTAssertEqual(AutomationStep.defaultValue(for: kind).kind, kind)
		}
	}
}
