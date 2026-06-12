import XCTest
@testable import TriggerKitCore

final class AutomationMacroTests: XCTestCase {
	func testMacroNormalizesNameAndProgram() {
		let macro = AutomationMacro(
			name: "  ",
			program: AutomationProgram(
				name: "  ",
				steps: [
					.openURL(OpenURLStep(url: " kevintang.xyz ")),
					.shellCommand(ShellCommandStep(command: " echo done ", shellPath: " /bin/zsh "))
				]
			)
		)

		XCTAssertEqual(macro.name, "Untitled Macro")
		XCTAssertEqual(macro.program.name, "Untitled Macro")
		XCTAssertEqual(macro.program.steps, [
			.openURL(OpenURLStep(url: "https://kevintang.xyz")),
			.shellCommand(ShellCommandStep(command: "echo done", shellPath: "/bin/zsh"))
		])
	}

	func testMacroReferenceUsesLiveMacroBeforeSnapshot() {
		let live = AutomationMacro(
			id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
			name: "Live",
			program: AutomationProgram(name: "Live", steps: [.delay(DelayStep(seconds: 1))])
		)
		let snapshot = AutomationProgram(name: "Snapshot", steps: [.delay(DelayStep(seconds: 2))])
		let reference = AutomationMacroReference(macroID: live.id, snapshot: snapshot)

		XCTAssertEqual(reference.resolvedProgram(macro: live, fallbackName: "Fallback")?.steps, live.program.steps)
		XCTAssertEqual(reference.resolvedProgram(macro: nil, fallbackName: "Fallback")?.steps, snapshot.steps)
	}

	func testExistingEmptyLiveMacroResolvesAsEmptyInsteadOfSnapshot() {
		let live = AutomationMacro(
			name: "Empty",
			program: AutomationProgram(name: "Empty")
		)
		let snapshot = AutomationProgram(name: "Snapshot", steps: [.delay(DelayStep(seconds: 2))])
		let reference = AutomationMacroReference(macroID: live.id, snapshot: snapshot)

		XCTAssertEqual(reference.resolvedProgram(macro: live, fallbackName: "Fallback")?.steps, [])
	}
}
