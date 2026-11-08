import XCTest
@testable import ControllerKeys

@MainActor
final class ControllerSourceAuditTests: MappingEngineTestCase {
	func testAuxiliaryWiimoteButtonOverridesXiaomiPrimary() async {
		profileManager.bindControllerPreview(to: controllerService)
		controllerService.setXiaomiRemoteConnected(true)
		controllerService.handleWiimoteInput(button: .x, pressed: true)
		controllerService.handleWiimoteInput(button: .x, pressed: false)
		let followed = await waitForCondition { self.profileManager.activeProfile?.controllerPreviewLayout == .wiimote }
		XCTAssertTrue(followed)
		XCTAssertTrue(controllerService.isXiaomiRemoteActiveInputSource)
	}

	func testSteamDeckSharedButtonsFollowSourceWithPedalConnected() async throws {
		profileManager.bindControllerPreview(to: controllerService)
		controllerService.setFootPedalConnected(true)
		let input = SteamDeckInput(controller: controllerService, observe: false)
		defer { input.stop() }
		var frame = SteamDeckFrame.released
		frame.active = true; frame.session = UUID(); frame.sequence = 1
		input.receive(String(decoding: try JSONEncoder().encode(frame), as: UTF8.self))
		profileManager.setControllerPreviewLayout(.footPedal)
		frame.sequence = 2; frame.buttons = ["dpadUp"]
		input.receive(String(decoding: try JSONEncoder().encode(frame), as: UTF8.self))
		let followed = await waitForCondition { self.profileManager.activeProfile?.controllerPreviewLayout == .steam }
		XCTAssertTrue(followed)
	}

	func testBeamdeskGamepadTriggerOverridesXiaomiPrimary() async throws {
		profileManager.bindControllerPreview(to: controllerService)
		controllerService.setXiaomiRemoteConnected(true)
		let input = BeamdeskGamepadInput(controller: controllerService)
		defer { input.stop() }
		let session = UUID()
		func packet(_ sequence: Int, trigger: Double) throws -> String {
			String(decoding: try JSONSerialization.data(withJSONObject: ["version": 1, "session": session.uuidString,
				"sequence": sequence, "active": true, "buttons": [], "axes": [0, 0, 0, 0, trigger, 0]]), as: UTF8.self)
		}
		input.receive(try packet(1, trigger: 0))
		profileManager.setControllerPreviewLayout(.footPedal)
		input.receive(try packet(2, trigger: 0.8))
		let followed = await waitForCondition { self.profileManager.activeProfile?.controllerPreviewLayout == .xbox }
		XCTAssertTrue(followed)
	}

	func testEditorScopeRejectsStaleSaveAfterSwitchAndDoesNotRebind() {
		var scope = MappingEditorScope()
		let original = profileManager.activeProfileId
		scope.begin(profileId: original)
		profileManager.setControllerPreviewLayout(.footPedal)
		XCTAssertTrue(scope.canSave(to: profileManager.activeProfileId), "Controller changes must not discard the draft")
		profileManager.setActiveProfile(Profile(name: "Another app"), isAutomatic: true)
		XCTAssertFalse(scope.canSave(to: profileManager.activeProfileId), "Save is blocked even before dismissal runs")
		scope.profileChanged(to: profileManager.activeProfileId)
		scope.begin(profileId: profileManager.activeProfileId)
		XCTAssertFalse(scope.canSave(to: profileManager.activeProfileId))
		XCTAssertFalse(scope.canSave(to: original), "Returning to the original profile must not revive a stale draft")
	}
	func testRejectedSteamDeckSessionDoesNotStealSelectionFromXiaomi() throws {
		profileManager.bindControllerPreview(to: controllerService)
		controllerService.setXiaomiRemoteConnected(true)
		let input = SteamDeckInput(controller: controllerService, observe: false)
		defer { input.stop() }
		var frame = SteamDeckFrame.released
		frame.active = true; frame.session = UUID(); frame.sequence = 1
		input.receive(String(decoding: try JSONEncoder().encode(frame), as: UTF8.self))
		XCTAssertFalse(controllerService.isSteamDeckConnected, "Retain the existing routing policy")
		XCTAssertEqual(profileManager.activeProfile?.controllerPreviewLayout, .xiaomiRemote)
	}

	func testSameSharedButtonOnSecondDeviceStillChangesCanonicalController() async {
		profileManager.bindControllerPreview(to: controllerService)
		controllerService.setXiaomiRemoteConnected(true)
		controllerService.handleXiaomiRemoteInput(.init(button: .dpadUp, pressed: true))
		await waitForTasks(0.1)
		controllerService.handleWiimoteInput(button: .dpadUp, pressed: true)
		let followed = await waitForCondition { self.profileManager.activeProfile?.controllerPreviewLayout == .wiimote }
		XCTAssertTrue(followed, "A shared held identity must not hide the second device's fresh press")
		profileManager.setControllerPreviewLayout(.footPedal)
		controllerService.handleWiimoteInput(button: .dpadUp, pressed: true)
		await waitForTasks(0.1)
		XCTAssertEqual(profileManager.activeProfile?.controllerPreviewLayout, .footPedal, "A repeat from that same source must not steal a manual selection")
		controllerService.handleXiaomiRemoteInput(.init(button: .dpadUp, pressed: false))
		controllerService.handleWiimoteInput(button: .dpadUp, pressed: false)
	}

}
