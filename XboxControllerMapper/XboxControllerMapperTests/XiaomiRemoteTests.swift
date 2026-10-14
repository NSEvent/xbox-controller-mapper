import AppKit
import SwiftUI
import XCTest
@testable import ControllerKeys

final class XiaomiRemoteDecoderTests: XCTestCase {
	private func report(_ a: UInt16, _ b: UInt16 = 0, _ c: UInt16 = 0) -> [UInt8] {
		[1] + [a, b, c].flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
	}

	func testLabelledPhysicalCaptureFixturesProduceAllThirteenControls() throws {
		let expected: [String: ControllerButton] = [
			"up": .dpadUp, "down": .dpadDown, "left": .dpadLeft, "right": .dpadRight,
			"ok": .xiaomiOK, "back": .xiaomiBack, "home": .xiaomiHome, "menu": .xiaomiMenu,
			"volumeUp": .xiaomiVolumeUp, "volumeDown": .xiaomiVolumeDown,
			"tv": .xiaomiTV, "microphone": .xiaomiMicrophone, "power": .xiaomiPower,
		]
		let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
		var observed = Set<ControllerButton>()
		for name in ["navigation", "function"] {
			let data = try Data(contentsOf: root.appendingPathComponent("Docs/xiaomi-remote-\(name)-fixture.json"))
			let packet = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
			for row in try XCTUnwrap(packet["cases"] as? [[String: Any]]) {
				let button = try XCTUnwrap(expected[try XCTUnwrap(row["button"] as? String)])
				var decoder = XiaomiRemoteReportDecoder()
				for (key, pressed) in [("press", true), ("release", false)] {
					let record = try XCTUnwrap(row[key] as? [String: Any])
					let hex = try XCTUnwrap(record["hex"] as? String)
					let bytes = hex.split(separator: " ").map { UInt8($0, radix: 16)! }
					XCTAssertEqual(decoder.process(report: bytes), [.init(button: button, pressed: pressed)])
				}
				observed.insert(button)
			}
		}
		XCTAssertEqual(observed, Set(expected.values))
	}

	func testEverySlotDuplicateSnapshotsAndPartialChordRelease() {
		var decoder = XiaomiRemoteReportDecoder()
		let chord = report(0x28, 0x52, 0x80)
		XCTAssertEqual(Set(decoder.process(report: chord).map(\.button)), [.xiaomiOK, .dpadUp, .xiaomiVolumeUp])
		XCTAssertTrue(decoder.process(report: chord).isEmpty, "a hold must not become repeated presses")
		XCTAssertEqual(decoder.process(report: report(0, 0x52)), [
			.init(button: .xiaomiOK, pressed: false), .init(button: .xiaomiVolumeUp, pressed: false),
		])
		XCTAssertEqual(decoder.reset(), [.init(button: .dpadUp, pressed: false)])
		XCTAssertTrue(decoder.reset().isEmpty)
	}

	func testMalformedRolloverAndVoiceReportsCannotReleaseHeldKeys() {
		var decoder = XiaomiRemoteReportDecoder()
		_ = decoder.process(report: report(0x28))
		for bytes in [[], [1], [1, 0, 0, 0], report(1), report(2), report(3), report(0x128)] {
			XCTAssertTrue(decoder.process(report: bytes).isEmpty)
		}
		XCTAssertTrue(decoder.process(report: [6] + Array(repeating: 0, count: 120), reportID: 6).isEmpty)
		XCTAssertEqual(decoder.reset(), [.init(button: .xiaomiOK, pressed: false)])
	}

	func testReportIDPayloadAndUnknownUsageAreHandledSafely() {
		var decoder = XiaomiRemoteReportDecoder()
		XCTAssertEqual(decoder.process(report: Array(report(0, 0xF1).dropFirst())), [.init(button: .xiaomiBack, pressed: true)])
		XCTAssertTrue(decoder.process(report: report(0), reportID: 8).isEmpty)
		XCTAssertEqual(decoder.process(report: report(0xF2)), [.init(button: .xiaomiBack, pressed: false)])
		XCTAssertTrue(decoder.reset().isEmpty, "unknown usages never become mappable buttons")
	}

	func testIdentityNeverMatchesOtherXiaomiDevicesOrUSB() {
		XCTAssertTrue(XiaomiRemoteIdentity.matches(vendorID: 0x2717, productID: 0x32B8, transport: "Bluetooth Low Energy"))
		XCTAssertFalse(XiaomiRemoteIdentity.matches(vendorID: 0x2717, productID: 0x32B9, transport: "Bluetooth Low Energy"))
		XCTAssertFalse(XiaomiRemoteIdentity.matches(vendorID: 0x2717, productID: 0x32B8, transport: "USB"))
		XCTAssertFalse(XiaomiRemoteIdentity.matches(vendorID: nil, productID: nil, transport: nil))
	}
}

final class XiaomiRemoteSuppressionTests: XCTestCase {
	func testQueuedReleaseDoesNotOverwriteThePendingNativePress() {
		var policy = XiaomiRemoteNativeEventPolicy()
		policy.record([.init(button: .xiaomiOK, pressed: true)], heldButtons: [.xiaomiOK], at: 1)
		policy.record([.init(button: .xiaomiOK, pressed: false)], heldButtons: [], at: 1.2)
		XCTAssertTrue(policy.shouldSuppress(.key(36), pressed: true, at: 1))
		XCTAssertTrue(policy.shouldSuppress(.key(36), pressed: false, at: 1.2))
		XCTAssertFalse(policy.shouldSuppress(.key(36), pressed: true, at: 1.3, isRepeat: true))
	}
	func testOnlyTimestampCorrelatedNativeEdgesAreConsumed() {
		var policy = XiaomiRemoteNativeEventPolicy()
		policy.record([.init(button: .xiaomiOK, pressed: true)], heldButtons: [.xiaomiOK], at: 10)
		XCTAssertFalse(policy.shouldSuppress(.key(36), pressed: true, at: 10, sourcePID: 42))
		XCTAssertFalse(policy.shouldSuppress(.key(36), pressed: true, at: 10, synthetic: true))
		XCTAssertFalse(policy.shouldSuppress(.key(37), pressed: true, at: 10))
		XCTAssertFalse(policy.shouldSuppress(.key(36), pressed: false, at: 10))
		XCTAssertTrue(policy.shouldSuppress(.key(36), pressed: true, at: 10.001, keyboardType: 7))
		XCTAssertFalse(policy.shouldSuppress(.key(36), pressed: true, at: 10.001, keyboardType: 7), "one remote edge cannot swallow two physical presses")
	}

	func testHeldRepeatsReleaseAndAnotherKeyboardCannotRetainOwnership() {
		var policy = XiaomiRemoteNativeEventPolicy()
		policy.record([.init(button: .dpadUp, pressed: true)], heldButtons: [.dpadUp], at: 20)
		XCTAssertTrue(policy.shouldSuppress(.key(126), pressed: true, at: 20, keyboardType: 7))
		XCTAssertTrue(policy.shouldSuppress(.key(126), pressed: true, at: 21, keyboardType: 7, isRepeat: true))
		XCTAssertFalse(policy.shouldSuppress(.key(126), pressed: true, at: 21, keyboardType: 44, isRepeat: true))
		XCTAssertFalse(policy.shouldSuppress(.key(126), pressed: true, at: 21.1, keyboardType: 44))
		XCTAssertFalse(policy.shouldSuppress(.key(126), pressed: true, at: 21.2, keyboardType: 7, isRepeat: true))
		policy.record([.init(button: .dpadUp, pressed: false)], heldButtons: [], at: 22)
		XCTAssertTrue(policy.shouldSuppress(.key(126), pressed: false, at: 22))
		XCTAssertFalse(policy.shouldSuppress(.key(126), pressed: true, at: 22.1, isRepeat: true))
	}

	func testUnrelatedVolumeAndStaleEventsPassThrough() {
		var policy = XiaomiRemoteNativeEventPolicy()
		policy.record([.init(button: .xiaomiVolumeUp, pressed: true)], heldButtons: [.xiaomiVolumeUp], at: 30)
		XCTAssertFalse(policy.shouldSuppress(.media(1), pressed: true, at: 30))
		XCTAssertFalse(policy.shouldSuppress(.media(0), pressed: true, at: 30.01))
		XCTAssertTrue(policy.shouldSuppress(.media(0), pressed: true, at: 30.002))
	}
}

@MainActor
final class XiaomiRemotePresentationTests: XCTestCase {
	func testDedicatedCanvasHasExactlyHardwareButtonsAndNoGamepadCapabilities() {
		let descriptor = ControllerVisualDescriptor.concrete(for: .xiaomiRemote)!
		XCTAssertEqual(descriptor.supportedButtons.count, 13)
		XCTAssertFalse(descriptor.hasSticks)
		XCTAssertFalse(descriptor.hasTriggers)
		XCTAssertFalse(descriptor.supportsMotionGestures)
		XCTAssertFalse(descriptor.supportsCommandWheel)
		XCTAssertTrue(descriptor.shoulderButtons(side: .left).isEmpty)
		XCTAssertTrue(descriptor.leftSystemButtons.isEmpty)
		XCTAssertFalse(descriptor.supportedButtons.contains(.menu), "no invented Play/Pause")
		for collection in [ControllerButton.xboxButtons, ControllerButton.dualSenseButtons,
			ControllerButton.dualShockButtons, ControllerButton.nintendoButtons, ControllerButton.appleTVRemoteButtons] {
			XCTAssertTrue(Set(collection).isDisjoint(with: ControllerButton.xiaomiRemoteActionButtons))
		}
	}

	func testDeviceIdentityAndDisplayRestoreAfterRemoteDisconnect() {
		let service = ControllerService(enableHardwareMonitoring: false)
		defer { service.cleanup() }
		service.setSteamDeckConnected(true)
		let identity = ControllerIdentity(stableId: "xiaomi-test", fallbackId: "rc003", vendorId: 0x2717, productId: 0x32B8,
			productName: "Xiaomi", transport: "Bluetooth Low Energy", serialNumber: nil, deviceAddress: nil)
		service.setXiaomiRemoteConnected(true, identity: identity)
		XCTAssertTrue(ControllerVisualDescriptor.active(using: service).isXiaomiRemote)
		XCTAssertEqual(service.currentControllerIdentity, identity)
		XCTAssertFalse(service.canAcceptSteamDeckInput)
		service.setXiaomiRemoteConnected(false)
		XCTAssertEqual(service.controllerName, "Steam Deck (ScreenShell)")
		XCTAssertNil(service.currentControllerIdentity)
	}

	func testPhotoMeasuredKeysStayWithinBodyAndUsePhysicalSymbols() {
		XCTAssertEqual(XiaomiRemoteMinimapLayout.aspectRatio, 145.0 / 570, accuracy: 0.002)
		for point in XiaomiRemoteMinimapLayout.keyCenters.values {
			XCTAssertTrue((0...1).contains(point.x) && (0...1).contains(point.y))
		}
		XCTAssertEqual(ControllerButton.xiaomiVolumeUp.systemImageName, "plus")
		XCTAssertEqual(ControllerButton.xiaomiVolumeDown.systemImageName, "minus")
		XCTAssertEqual(ControllerButton.xiaomiMicrophone.systemImageName, "mic")
		XCTAssertEqual(ControllerButton.xiaomiHome.systemImageName, "house")
		XCTAssertEqual(ControllerButton.xiaomiMenu.systemImageName, "line.3.horizontal")
		XCTAssertEqual(ControllerButton.xiaomiTV.shortLabel, "TV")
	}

	func testDisabledHardwareServiceCannotAcquireDevices() {
		let controller = ControllerService(enableHardwareMonitoring: false)
		let service = XiaomiRemoteInputService(controller: controller, hardwareEnabled: false)
		service.startIfPermitted()
		XCTAssertFalse(controller.isXiaomiRemoteConnected)
		service.stop(); service.stop(); controller.cleanup()
	}

	func testPhotoOutlineKeepsStraightEdgesImmediatelyBelowTinyCorners() {
		let rect = CGRect(origin: CGPoint(x: 20, y: 30), size: XiaomiRemoteMinimapLayout.bodySize)
		let path = XiaomiRemoteBodyShape().path(in: rect)
		XCTAssertEqual(path.boundingRect, rect)
		for y in [rect.minY + 3, rect.midY, rect.maxY - 3] {
			XCTAssertTrue(path.contains(CGPoint(x: rect.minX + 0.1, y: y)))
			XCTAssertTrue(path.contains(CGPoint(x: rect.maxX - 0.1, y: y)))
		}
		XCTAssertFalse(path.contains(CGPoint(x: rect.minX, y: rect.minY)))
	}
}

@MainActor
final class XiaomiRemoteMappingTests: MappingEngineTestCase {
	func testEveryRemoteButtonUsesItsSavedMappingThroughTheNormalInputPipeline() async throws {
		let buttons = ControllerButton.xiaomiRemoteButtons
		profileManager.setActiveProfile(Profile(name: "Xiaomi test", buttonMappings:
			Dictionary(uniqueKeysWithValues: buttons.enumerated().map { ($0.element, KeyMapping(keyCode: UInt16($0.offset))) })))
		await waitForTasks()
		for (index, button) in buttons.enumerated() {
			mockInputSimulator.clearEvents()
			controllerService.handleButton(button, pressed: true)
			controllerService.handleButton(button, pressed: false)
			await waitForTasks(0.2)
			let keys = mockInputSimulator.events.compactMap { event -> UInt16? in
				if case .pressKey(let key, _) = event { return key }
				return nil
			}
			XCTAssertEqual(keys, [UInt16(index)], "\(button) must reach its own saved mapping exactly once")
		}
	}
}
