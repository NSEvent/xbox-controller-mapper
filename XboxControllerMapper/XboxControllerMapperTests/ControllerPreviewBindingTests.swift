import XCTest
@testable import ControllerKeys

@MainActor
final class ControllerPreviewBindingTests: MappingEngineTestCase {
	func testMostRecentConnectionWinsOverPrimaryDeviceWithoutAWindow() {
		profileManager.bindControllerPreview(to: controllerService)
		controllerService.setXiaomiRemoteConnected(true)
		XCTAssertEqual(profileManager.activeProfile?.controllerPreviewLayout, .xiaomiRemote)
		controllerService.setFootPedalConnected(true)
		XCTAssertEqual(profileManager.activeProfile?.controllerPreviewLayout, .footPedal)
		XCTAssertTrue(controllerService.isXiaomiRemoteActiveInputSource)
	}

	func testReverseConnectionOrderAndReconnect() {
		profileManager.bindControllerPreview(to: controllerService)
		controllerService.setFootPedalConnected(true)
		controllerService.setXiaomiRemoteConnected(true)
		XCTAssertEqual(profileManager.activeProfile?.controllerPreviewLayout, .xiaomiRemote)
		controllerService.setFootPedalConnected(false)
		controllerService.setFootPedalConnected(true)
		XCTAssertEqual(profileManager.activeProfile?.controllerPreviewLayout, .footPedal)
	}

	func testStartupConnectionIsReplayedWhenAppBinds() {
		controllerService.setXiaomiRemoteConnected(true)
		controllerService.setFootPedalConnected(true)
		profileManager.bindControllerPreview(to: controllerService)
		XCTAssertEqual(profileManager.activeProfile?.controllerPreviewLayout, .footPedal)
	}

	func testDuplicateConnectionAndDisconnectPreserveManualSelection() {
		profileManager.bindControllerPreview(to: controllerService)
		controllerService.setFootPedalConnected(true)
		profileManager.setControllerPreviewLayout(.dualSense)
		controllerService.setFootPedalConnected(true)
		XCTAssertEqual(profileManager.activeProfile?.controllerPreviewLayout, .dualSense)
		controllerService.setFootPedalConnected(false)
		XCTAssertEqual(profileManager.activeProfile?.controllerPreviewLayout, .dualSense)
	}

	func testInputThenConnectionThenOtherDeviceInputUpdatesSharedSelection() async {
		profileManager.bindControllerPreview(to: controllerService)
		controllerService.setXiaomiRemoteConnected(true)
		controllerService.setFootPedalConnected(true)
		controllerService.handleXiaomiRemoteInput(.init(button: .dpadUp, pressed: true))
		controllerService.handleXiaomiRemoteInput(.init(button: .dpadUp, pressed: false))
		let remoteSelected = await waitForCondition { self.profileManager.activeProfile?.controllerPreviewLayout == .xiaomiRemote }
		XCTAssertTrue(remoteSelected)
		controllerService.setS29RingConnected(true)
		XCTAssertEqual(profileManager.activeProfile?.controllerPreviewLayout, .s29Ring)
		controllerService.handleFootPedalInput(.init(button: .footPedalRight, pressed: true))
		controllerService.handleFootPedalInput(.init(button: .footPedalRight, pressed: false))
		let pedalSelected = await waitForCondition { self.profileManager.activeProfile?.controllerPreviewLayout == .footPedal }
		XCTAssertTrue(pedalSelected)
	}

	func testDelayedOlderInputCannotReplaceNewerConnection() {
		profileManager.bindControllerPreview(to: controllerService)
		controllerService.recordPreviewActivity(.footPedal, at: 20)
		controllerService.recordPreviewActivity(.xiaomiRemote, at: 10)
		XCTAssertEqual(profileManager.activeProfile?.controllerPreviewLayout, .footPedal)
		controllerService.recordPreviewActivity(.xiaomiRemote, at: 21)
		XCTAssertEqual(profileManager.activeProfile?.controllerPreviewLayout, .xiaomiRemote)
	}

	func testGamepadConnectionUsesItsSpecificModel() {
		profileManager.bindControllerPreview(to: controllerService)
		for type: ControllerTypeState in [.dualSenseEdge, .steam, .xbox] {
			controllerService.storage.lock.withLock { controllerService.storage.applyControllerTypeLocked(type) }
			controllerService.recordCurrentControllerConnectionPreview()
			XCTAssertEqual(ControllerVisualDescriptor.concrete(for: profileManager.activeProfile!.controllerPreviewLayout),
				ControllerVisualDescriptor.active(using: controllerService))
		}
	}
	func testBoundSelectionSurvivesAutomaticAndManualProfileSwitches() {
		profileManager.bindControllerPreview(to: controllerService)
		controllerService.setFootPedalConnected(true)
		var second = Profile(name: "Other app")
		second.controllerPreviewLayout = .xbox
		profileManager.setActiveProfile(second, isAutomatic: true)
		XCTAssertEqual(profileManager.activeProfile?.controllerPreviewLayout, .footPedal)
		profileManager.setControllerPreviewLayout(.wiimote)
		profileManager.setActiveProfile(Profile(name: "Manual switch"))
		XCTAssertEqual(profileManager.activeProfile?.controllerPreviewLayout, .wiimote)
	}

	func testStaleProfileEditCannotRestoreAnOldControllerSelection() {
		profileManager.bindControllerPreview(to: controllerService)
		var draft = profileManager.activeProfile!
		controllerService.setFootPedalConnected(true)
		draft.name = "Renamed"
		profileManager.updateProfile(draft)
		XCTAssertEqual(profileManager.activeProfile?.name, "Renamed")
		XCTAssertEqual(profileManager.activeProfile?.controllerPreviewLayout, .footPedal)
	}

	func testRestoringMappingsFromHistoryKeepsCurrentController() throws {
		profileManager.bindControllerPreview(to: controllerService)
		profileManager.setControllerPreviewLayout(.xbox)
		profileManager.setMapping(KeyMapping(keyCode: 12), for: .a)
		profileManager.snapshotCurrentState(reason: "Before editing")
		let snapshot = try XCTUnwrap(profileManager.availableSnapshots().first)
		controllerService.setFootPedalConnected(true)
		profileManager.setMapping(KeyMapping(keyCode: 13), for: .a)
		XCTAssertTrue(profileManager.restoreSnapshot(snapshot))
		XCTAssertEqual(profileManager.activeProfile?.buttonMappings[.a]?.keyCode, 12)
		XCTAssertEqual(profileManager.activeProfile?.controllerPreviewLayout, .footPedal)
	}

}
