import Combine
import XCTest
@testable import ControllerKeys

final class ControllerPreviewAutoFollowTests: XCTestCase {
	func testTaggedSourceOverridesPrimaryHardwareIncludingSharedDPad() {
		for layout in ControllerPreviewLayout.concreteLayouts {
			XCTAssertEqual(ControllerPreviewAutoFollow.layout(button: .dpadUp, source: layout,
				activeDescriptor: .init(family: .xbox)), layout)
		}
	}

	func testDedicatedControlsIdentifyAuxiliaryDevicesWithoutTag() {
		let cases: [(ControllerButton, ControllerPreviewLayout)] = [
			(.footPedalLeft, .footPedal), (.footPedalMiddle, .footPedal), (.footPedalRight, .footPedal),
			(.xiaomiOK, .xiaomiRemote), (.s29Camera, .s29Ring), (.ouraTap, .ouraRing)
		]
		for (button, layout) in cases {
			XCTAssertEqual(ControllerPreviewAutoFollow.layout(button: button, source: nil,
				activeDescriptor: .init(family: .xbox)), layout)
		}
	}

	func testUntaggedGamepadButtonsUseHardwareSnapshot() {
		XCTAssertEqual(ControllerPreviewAutoFollow.layout(button: .a, source: nil,
			activeDescriptor: .init(family: .dualSense)), .dualSense)
		XCTAssertEqual(ControllerPreviewAutoFollow.layout(button: .dpadUp, source: nil,
			activeDescriptor: .init(family: .steam)), .steam)
	}

	func testGestureAndStickNoiseNeverChangesPreview() {
		for button: ControllerButton in [.gestureTiltBack, .leftStickUp] {
			XCTAssertNil(ControllerPreviewAutoFollow.layout(button: button, source: .dualSense,
				activeDescriptor: .init(family: .xbox)))
		}
	}
}

@MainActor
final class MultiDevicePreviewActivityTests: MappingEngineTestCase {
	func testPedalAndXiaomiAlternateThroughProductionInputRouting() async {
		controllerService.setFootPedalConnected(true)
		controllerService.setXiaomiRemoteConnected(true)
		profileManager.setControllerPreviewLayout(.xiaomiRemote)
		var layouts: [ControllerPreviewLayout] = []
		let subscription = controllerService.previewActivity.sink { [self] layout in
			layouts.append(layout)
			profileManager.setControllerPreviewLayout(layout)
		}
		defer { subscription.cancel() }
		var pedal = FootPedalReportDecoder()
		var remote = XiaomiRemoteReportDecoder()
		for event in pedal.process(report: [1, 0]) { controllerService.handleFootPedalInput(event) }
		let selectedPedal = await waitForCondition { self.profileManager.activeProfile?.controllerPreviewLayout == .footPedal }
		XCTAssertTrue(selectedPedal)
		XCTAssertEqual(ControllerVisualDescriptor.resolved(previewLayout: profileManager.activeProfile!.controllerPreviewLayout,
			using: controllerService).supportedButtons, Set(ControllerButton.footPedalButtons))
		// The remote's shared D-pad input must win even while a pedal is held.
		for event in remote.process(report: [0x52, 0, 0, 0, 0, 0]) { controllerService.handleXiaomiRemoteInput(event) }
		let selectedRemote = await waitForCondition { self.profileManager.activeProfile?.controllerPreviewLayout == .xiaomiRemote }
		XCTAssertTrue(selectedRemote)
		for event in pedal.process(report: [0, 0]) { controllerService.handleFootPedalInput(event) }
		for event in remote.reset() { controllerService.handleXiaomiRemoteInput(event) }
		for event in pedal.process(report: [4, 0]) { controllerService.handleFootPedalInput(event) }
		for event in pedal.reset() { controllerService.handleFootPedalInput(event) }
		let finished = await waitForCondition { layouts.count == 3 && self.controllerService.activeButtons.isEmpty }
		XCTAssertTrue(finished)
		XCTAssertEqual(layouts, [.footPedal, .xiaomiRemote, .footPedal])
		XCTAssertEqual(profileManager.activeProfile?.controllerPreviewLayout, .footPedal)
		XCTAssertTrue(controllerService.isXiaomiRemoteActiveInputSource,
			"Editor activity must not rewrite the primary hardware connection or mapping routing")
	}

	func testRapidQueuedPressesPreserveTheirOwnDeviceSource() async {
		controllerService.setFootPedalConnected(true)
		controllerService.setXiaomiRemoteConnected(true)
		var layouts: [ControllerPreviewLayout] = []
		let subscription = controllerService.previewActivity.sink { layouts.append($0) }
		defer { subscription.cancel() }
		for _ in 0..<5 {
			controllerService.handleFootPedalInput(.init(button: .footPedalMiddle, pressed: true))
			controllerService.handleFootPedalInput(.init(button: .footPedalMiddle, pressed: false))
			controllerService.handleXiaomiRemoteInput(.init(button: .dpadUp, pressed: true))
			controllerService.handleXiaomiRemoteInput(.init(button: .dpadUp, pressed: false))
		}
		let finished = await waitForCondition { layouts.count == 10 && self.controllerService.activeButtons.isEmpty }
		XCTAssertTrue(finished)
		XCTAssertEqual(layouts, (0..<5).flatMap { _ in [ControllerPreviewLayout.footPedal, .xiaomiRemote] })
	}

	func testHeldRepeatsReleasesAndConnectionChangesPreserveManualSelection() async {
		controllerService.setFootPedalConnected(true)
		controllerService.setXiaomiRemoteConnected(true)
		var layouts: [ControllerPreviewLayout] = []
		let subscription = controllerService.previewActivity.sink { [self] layout in
			layouts.append(layout)
			profileManager.setControllerPreviewLayout(layout)
		}
		defer { subscription.cancel() }
		controllerService.handleFootPedalInput(.init(button: .footPedalLeft, pressed: true))
		let pressed = await waitForCondition { layouts.count == 1 }
		XCTAssertTrue(pressed)
		profileManager.setControllerPreviewLayout(.nintendo)
		controllerService.handleFootPedalInput(.init(button: .footPedalLeft, pressed: true))
		controllerService.handleFootPedalInput(.init(button: .footPedalLeft, pressed: false))
		let released = await waitForCondition { self.controllerService.activeButtons.isEmpty }
		XCTAssertTrue(released)
		controllerService.setFootPedalConnected(false)
		await waitForTasks(0.05)
		XCTAssertEqual(layouts, [.footPedal])
		XCTAssertEqual(profileManager.activeProfile?.controllerPreviewLayout, .nintendo)
	}

	func testGamepadIdentityIsCapturedBeforeQueuedUIUpdate() async {
		var layouts: [ControllerPreviewLayout] = []
		let subscription = controllerService.previewActivity.sink { layouts.append($0) }
		defer { subscription.cancel() }
		controllerService.storage.lock.withLock { controllerService.storage.applyControllerTypeLocked(.dualSense) }
		controllerService.buttonPressed(.a)
		controllerService.buttonReleased(.a)
		controllerService.storage.lock.withLock { controllerService.storage.applyControllerTypeLocked(.xbox) }
		let received = await waitForCondition { layouts.count == 1 }
		XCTAssertTrue(received)
		XCTAssertEqual(layouts, [.dualSense])
	}
	func testSwitchingPreviewKeepsPedalModifierHeldUntilPhysicalRelease() async {
		profileManager.setActiveProfile(Profile(name: "Pedal modifier", buttonMappings: [
			.footPedalLeft: .holdModifier(.command)
		]))
		let subscription = controllerService.previewActivity.sink { [self] in profileManager.setControllerPreviewLayout($0) }
		defer { subscription.cancel() }
		controllerService.handleFootPedalInput(.init(button: .footPedalLeft, pressed: true))
		let held = await waitForCondition { self.mockInputSimulator.heldModifiers.contains(.maskCommand) }
		XCTAssertTrue(held)
		controllerService.handleXiaomiRemoteInput(.init(button: .dpadUp, pressed: true))
		let switched = await waitForCondition { self.profileManager.activeProfile?.controllerPreviewLayout == .xiaomiRemote }
		XCTAssertTrue(switched)
		await waitForTasks(0.1)
		XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskCommand), "Changing the displayed device must not release the pedal action")
		controllerService.handleFootPedalInput(.init(button: .footPedalLeft, pressed: false))
		controllerService.handleXiaomiRemoteInput(.init(button: .dpadUp, pressed: false))
		let released = await waitForCondition { !self.mockInputSimulator.heldModifiers.contains(.maskCommand) }
		XCTAssertTrue(released)
	}

	func testSequenceAcrossDevicesSurvivesAutoFollowUpdates() async {
		var profile = Profile(name: "Mixed device sequence")
		profile.sequenceMappings = [SequenceMapping(steps: [.footPedalLeft, .xiaomiOK], stepTimeout: 1.5, keyCode: 48)]
		profileManager.setActiveProfile(profile)
		let subscription = controllerService.previewActivity.sink { [self] in profileManager.setControllerPreviewLayout($0) }
		defer { subscription.cancel() }
		controllerService.handleFootPedalInput(.init(button: .footPedalLeft, pressed: true))
		controllerService.handleFootPedalInput(.init(button: .footPedalLeft, pressed: false))
		await waitForTasks(0.15)
		controllerService.handleXiaomiRemoteInput(.init(button: .xiaomiOK, pressed: true))
		controllerService.handleXiaomiRemoteInput(.init(button: .xiaomiOK, pressed: false))
		let fired = await waitForCondition { self.mockInputSimulator.events.contains(.pressKey(48, [])) }
		XCTAssertTrue(fired, "Changing the displayed device must not discard the previous sequence step")
		XCTAssertEqual(mockInputSimulator.events.filter { $0 == .pressKey(48, []) }.count, 1)
	}

	func testRealMappingChangeAlongsidePreviewStillCleansUpHeldAction() async {
		profileManager.setActiveProfile(Profile(name: "Real mapping edit", buttonMappings: [
			.footPedalLeft: .holdModifier(.command)
		]))
		controllerService.handleFootPedalInput(.init(button: .footPedalLeft, pressed: true))
		let held = await waitForCondition { self.mockInputSimulator.heldModifiers.contains(.maskCommand) }
		XCTAssertTrue(held)
		var changed = profileManager.activeProfile!
		changed.controllerPreviewLayout = .footPedal
		changed.buttonMappings[.footPedalLeft] = .holdModifier(.option)
		profileManager.updateProfile(changed)
		XCTAssertFalse(mockInputSimulator.heldModifiers.contains(.maskCommand), "A real mapping edit must still clean up held output")
		controllerService.handleFootPedalInput(.init(button: .footPedalLeft, pressed: false))
	}

}
