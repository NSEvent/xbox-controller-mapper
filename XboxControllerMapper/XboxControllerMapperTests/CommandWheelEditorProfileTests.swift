import XCTest
@testable import ControllerKeys

/// An add sheet opened on one profile must not save into a profile that
/// became active (e.g. by app auto-switch) while it was open.
final class CommandWheelEditorProfileTests: MappingEngineTestCase {
	func testAddFromEditorOfPreviousProfileIsDropped() async {
		let first = Profile(name: "First")
		let second = Profile(name: "Second")
		let action = CommandWheelAction(displayName: "Late", keyCode: 12)

		let actions = await MainActor.run { () -> [CommandWheelAction] in
			profileManager.profiles = [first, second]
			profileManager.setActiveProfile(first)
			let editorProfileId = profileManager.activeProfile?.id
			profileManager.setActiveProfile(second, isAutomatic: true)
			profileManager.addCommandWheelAction(action, profileId: editorProfileId)
			return profileManager.activeProfile?.commandWheelActions ?? []
		}
		XCTAssertFalse(actions.contains { $0.id == action.id })
	}

	func testAddFromEditorOfActiveProfileSaves() async {
		let action = CommandWheelAction(displayName: "Now", keyCode: 12)
		let actions = await MainActor.run { () -> [CommandWheelAction] in
			profileManager.installTestProfile(Profile(name: "Only"))
			profileManager.addCommandWheelAction(action, profileId: profileManager.activeProfile?.id)
			return profileManager.activeProfile?.commandWheelActions ?? []
		}
		XCTAssertTrue(actions.contains { $0.id == action.id })
	}
}
