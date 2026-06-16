import XCTest
@testable import TriggerKitCore

final class AutomationValidationTests: XCTestCase {
	func testValidationReportsProgramAndStepReadinessIssues() {
		let program = AutomationProgram(name: "Broken", steps: [
			.openURL(OpenURLStep(url: "http://example.com")),
			.shellCommand(ShellCommandStep(command: "  ", shellPath: "  ")),
			.openApp(OpenAppStep(bundleIdentifier: "  ")),
			.condition(ConditionStep(kind: .appRunning)),
			.custom(CustomStep(namespace: "  ")),
			.typeText(TypeTextStep(text: "", pressReturn: false))
		])

		let issues = program.validate(policy: AutomationValidationPolicy(allowedURLSchemes: ["https"]))

		XCTAssertEqual(issues.map(\.code), [
			.disallowedURLScheme,
			.emptyShellCommand,
			.missingShellPath,
			.missingAppBundleIdentifier,
			.invalidCondition,
			.missingCustomNamespace,
			.emptyText
		])
		XCTAssertTrue(issues.allSatisfy(\.isError))
	}

	func testValidationReportsEmptyProgram() {
		XCTAssertEqual(
			AutomationProgram(name: "Empty").validate().map(\.code),
			[.emptyProgram]
		)
		XCTAssertTrue(AutomationProgram(name: "Empty").validate(policy: AutomationValidationPolicy(allowsEmptyProgram: true)).isEmpty)
	}

	func testValidationUsesCapabilitiesAndOptionalHostLookups() {
		let program = AutomationProgram(name: "Host", steps: [
			.shellCommand(ShellCommandStep(command: "echo hi")),
			.openApp(OpenAppStep(bundleIdentifier: "com.example.Missing")),
			.custom(CustomStep(namespace: "plaque.music"))
		])

		let issues = program.validate(policy: AutomationValidationPolicy(
			capabilities: .inputOnly,
			installedApplicationBundleIdentifiers: ["com.apple.TextEdit"],
			supportedCustomNamespaces: ["controllerkeys.obs"]
		))

		XCTAssertEqual(issues.map(\.code), [
			.unsupportedCapability,
			.unsupportedCapability,
			.appBundleNotFound,
			.unsupportedCapability,
			.unsupportedCustomNamespace
		])
	}

	func testValidationNormalizesPlainWebURLButRequiresWebhookScheme() {
		XCTAssertTrue(AutomationProgram(name: "URL", steps: [
			.openURL(OpenURLStep(url: "kevintang.xyz"))
		]).validate(policy: AutomationValidationPolicy(allowedURLSchemes: ["https"])).isEmpty)

		XCTAssertEqual(
			AutomationProgram(name: "Hook", steps: [
				.webhook(WebhookStep(url: "example.com/hook"))
			]).validate().map(\.code),
			[.invalidWebhookURL]
		)
	}

	func testValidationFlagsInertPointerStepsAsWarnings() {
		let issues = AutomationProgram(name: "Inert", steps: [
			.mouseMove(MouseMove(deltaX: 0, deltaY: 0)),
			.mouseScroll(MouseScroll(deltaX: 0, deltaY: 0))
		]).validate()

		XCTAssertEqual(issues.map(\.code), [.inertStep, .inertStep])
		XCTAssertEqual(issues.map(\.severity), [.warning, .warning])
	}
}
