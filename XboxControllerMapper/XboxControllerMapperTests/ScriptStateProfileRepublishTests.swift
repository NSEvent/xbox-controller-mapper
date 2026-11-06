import XCTest
@testable import ControllerKeys

/// Script `state` must survive settings edits that republish the active
/// profile and be cleared only when a different profile becomes active.
final class ScriptStateProfileRepublishTests: MappingEngineTestCase {
	private let script = Script(name: "Counter", source: "")

	private func run(_ source: String) -> ScriptResult {
		var script = script
		script.source = source
		return mappingEngine.scriptEngine.execute(script: script, trigger: ScriptTrigger(button: .a))
	}

	private func stateSurvived() -> Bool {
		if case .success = run("if (!state.get('seen')) throw new Error('state cleared')") { return true }
		return false
	}

	func testSettingsEditKeepsScriptState() async throws {
		let profile = Profile(name: "Scripts")
		await MainActor.run { profileManager.installTestProfile(profile) }
		await waitForTasks(0.1)
		_ = run("state.set('seen', true)")

		await MainActor.run {
			var edited = profileManager.activeProfile!
			edited.name = "Scripts (renamed)"
			profileManager.updateProfile(edited)
		}
		await waitForTasks(0.2)

		XCTAssertTrue(stateSurvived(), "republishing the same profile must not wipe script state")
	}

	func testProfileSwitchClearsScriptState() async throws {
		await MainActor.run { profileManager.installTestProfile(Profile(name: "First")) }
		await waitForTasks(0.1)
		_ = run("state.set('seen', true)")

		await MainActor.run { profileManager.installTestProfile(Profile(name: "Second")) }
		await waitForTasks(0.2)

		XCTAssertFalse(stateSurvived(), "switching profiles must still clear script state")
	}
}
