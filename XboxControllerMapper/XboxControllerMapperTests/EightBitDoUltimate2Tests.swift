import XCTest
@testable import ControllerKeys

final class EightBitDoUltimate2DetectionTests: XCTestCase {
	func testDetectsUltimate2ByProductName() {
		XCTAssertTrue(ControllerService.isEightBitDoUltimate2(controllerName: "8BitDo Ultimate 2 Wireless"))
		XCTAssertTrue(ControllerService.isEightBitDoUltimate2(controllerName: "8BitDo Ultimate 2"))
		XCTAssertTrue(ControllerService.isEightBitDoUltimate2(controllerName: "8bitdo ultimate 2 wireless controller"))
	}

	func testDetectsUltimate2WhenVendorNameIsGeneric() {
		XCTAssertTrue(
			ControllerService.isEightBitDoUltimate2(
				vendorName: "Controller",
				productCategory: "8BitDo Ultimate 2 Wireless"
			)
		)
		XCTAssertTrue(
			ControllerService.isEightBitDoUltimate2(
				vendorName: nil,
				productCategory: "Ultimate 2 Wireless"
			)
		)
	}

	func testRejectsOtherEightBitDoPads() {
		XCTAssertFalse(ControllerService.isEightBitDoUltimate2(controllerName: "8BitDo Ultimate 2C"))
		XCTAssertFalse(ControllerService.isEightBitDoUltimate2(controllerName: "8BitDo Ultimate 2C Wireless Controller"))
		XCTAssertFalse(ControllerService.isEightBitDoUltimate2(controllerName: "8BitDo Ultimate"))
		XCTAssertFalse(ControllerService.isEightBitDoUltimate2(controllerName: "8BitDo Ultimate C"))
		XCTAssertFalse(ControllerService.isEightBitDoUltimate2(controllerName: "8BitDo Ultimate 24"))
		XCTAssertFalse(ControllerService.isEightBitDoUltimate2(controllerName: "8BitDo Lite 2"))
		XCTAssertFalse(ControllerService.isEightBitDoUltimate2(controllerName: "Xbox Wireless Controller"))
	}

	func testUltimate2IsNotASmallPadMinimapModel() {
		XCTAssertNil(ControllerService.eightBitDoMinimapModel(forControllerName: "8BitDo Ultimate 2 Wireless"))
	}
}

final class EightBitDoUltimate2HIDButtonTableTests: XCTestCase {
	func testRawUsagesMapToHomeAndElitePaddles() {
		let page = EightBitDoUltimate2HIDButtonTable.buttonUsagePage
		XCTAssertEqual(page, 0x09)
		XCTAssertEqual(EightBitDoUltimate2HIDButtonTable.button(usagePage: page, usage: 13), .xbox)
		XCTAssertEqual(EightBitDoUltimate2HIDButtonTable.button(usagePage: page, usage: 17), .xboxPaddle1)
		XCTAssertEqual(EightBitDoUltimate2HIDButtonTable.button(usagePage: page, usage: 18), .xboxPaddle2)
		XCTAssertEqual(EightBitDoUltimate2HIDButtonTable.button(usagePage: page, usage: 6), .xboxPaddle3)
		XCTAssertEqual(EightBitDoUltimate2HIDButtonTable.button(usagePage: page, usage: 3), .xboxPaddle4)
		XCTAssertEqual(EightBitDoUltimate2HIDButtonTable.buttonsByUsage.count, 5)
	}

	func testGameControllerDeliveredUsagesAndOtherPagesAreIgnored() {
		let page = EightBitDoUltimate2HIDButtonTable.buttonUsagePage
		// A (usage 1), B (2), X (4), Y (5), shoulders (7/8), Start (12) come
		// through GameController and must not be duplicated from raw HID.
		for usage in [1, 2, 4, 5, 7, 8, 9, 10, 11, 12, 14, 15, 16, 19] {
			XCTAssertNil(
				EightBitDoUltimate2HIDButtonTable.button(usagePage: page, usage: usage),
				"usage \(usage) should not be synthesized"
			)
		}
		// Same usage number on a non-Button page (e.g. Generic Desktop) is not a button.
		XCTAssertNil(EightBitDoUltimate2HIDButtonTable.button(usagePage: 0x01, usage: 13))
	}

	func testUsageTableMirrorsBundledSDLRow() {
		// HID Button usage N is SDL button index N-1.
		let expected: [String: ControllerButton] = [
			"guide": .xbox,
			"paddle1": .xboxPaddle1,
			"paddle2": .xboxPaddle2,
			"paddle3": .xboxPaddle3,
			"paddle4": .xboxPaddle4,
		]
		let sdlIndices = ["guide": 12, "paddle1": 16, "paddle2": 17, "paddle3": 5, "paddle4": 2]
		for (name, button) in expected {
			let index = sdlIndices[name]!
			XCTAssertEqual(
				EightBitDoUltimate2HIDButtonTable.button(
					usagePage: EightBitDoUltimate2HIDButtonTable.buttonUsagePage,
					usage: index + 1
				),
				button,
				"\(name) should map to \(button)"
			)
		}
	}

	func testDriverDescriptorMatchesUltimate2ProductID() {
		XCTAssertEqual(EightBitDoDInputHIDDriverDescriptor.ultimate2ProductID, 0x6012)
		XCTAssertTrue(
			EightBitDoDInputHIDDriverDescriptor().matchingCriteria.contains(
				.vendorProduct(vendorID: 0x2DC8, productID: 0x6012)
			)
		)
	}

	func testRawButtonLatchOnlyReportsEdgesAndReleasesHeldButtons() {
		let latch = RawHIDButtonLatch()
		XCTAssertTrue(latch.update(.xboxPaddle1, pressed: true))
		XCTAssertFalse(latch.update(.xboxPaddle1, pressed: true), "repeated press value is not an edge")
		XCTAssertTrue(latch.update(.xbox, pressed: true))
		XCTAssertTrue(latch.update(.xbox, pressed: false))
		XCTAssertFalse(latch.update(.xbox, pressed: false), "repeated release value is not an edge")
		XCTAssertEqual(latch.releaseAll(), [.xboxPaddle1])
		XCTAssertEqual(latch.heldButtons, [])
		XCTAssertTrue(latch.update(.xboxPaddle1, pressed: true), "a released latch accepts a fresh press")
	}
}

@MainActor
final class EightBitDoUltimate2RawHIDInputTests: XCTestCase {
	private var controllerService: ControllerService!

	override func setUp() async throws {
		try await super.setUp()
		controllerService = ControllerService(enableHardwareMonitoring: false)
	}

	override func tearDown() async throws {
		controllerService = nil
		try await super.tearDown()
	}

	func testRawPaddleValueSynthesizesPressAndReleaseOnce() async {
		controllerService.lowLatencyInputEnabled = true
		controllerService.chordParticipantButtons = []

		let pressed = expectation(description: "Paddle 1 press")
		let released = expectation(description: "Paddle 1 release")

		controllerService.onInputEvent = { event in
			switch event {
			case .buttonPressed(let button):
				XCTAssertEqual(button, .xboxPaddle1)
				pressed.fulfill()
			case .buttonReleased(let button, _):
				XCTAssertEqual(button, .xboxPaddle1)
				released.fulfill()
			default:
				break
			}
		}

		// IOKit re-delivers element values; duplicates must not re-press.
		controllerService.handleEightBitDoUltimate2ButtonValue(usagePage: 0x09, usage: 17, pressed: true)
		controllerService.handleEightBitDoUltimate2ButtonValue(usagePage: 0x09, usage: 17, pressed: true)
		controllerService.handleEightBitDoUltimate2ButtonValue(usagePage: 0x09, usage: 17, pressed: false)
		controllerService.handleEightBitDoUltimate2ButtonValue(usagePage: 0x09, usage: 17, pressed: false)

		await fulfillment(of: [pressed, released], timeout: 1.0)
	}

	func testUnmappedRawUsageIsIgnored() {
		controllerService.handleEightBitDoUltimate2ButtonValue(usagePage: 0x09, usage: 1, pressed: true)
		XCTAssertTrue(controllerService.eightBitDoUltimate2RawButtons.heldButtons.isEmpty)
	}
}

@MainActor
final class EightBitDoUltimate2PresentationTests: XCTestCase {
	func testActivePresentationResolvesEliteStyleUltimate2Preview() {
		let storage = ControllerStorage()
		let state = storage.lock.withLock {
			storage.isEightBitDoUltimate2 = true
			return storage.controllerPresentationStateLocked
		}

		XCTAssertTrue(state.isEightBitDoUltimate2)
		XCTAssertTrue(state.isXboxElite, "Ultimate 2 exposes the Elite paddle UI")
		XCTAssertNil(state.eightBitDoModel, "Ultimate 2 must not use the small-pad minimap path")

		let descriptor = ControllerVisualDescriptor.active(from: state)
		XCTAssertEqual(descriptor.family, .eightBitDoUltimate2)
		XCTAssertEqual(descriptor.minimapStyle, .xboxElite)
	}

	func testUltimate2DescriptorShowsPaddlesAndStandardControls() {
		let descriptor = ControllerVisualDescriptor(family: .eightBitDoUltimate2)
		XCTAssertTrue(descriptor.isEightBitDoUltimate2)
		XCTAssertTrue(descriptor.isXboxElite)
		XCTAssertNil(descriptor.eightBitDoModel)
		XCTAssertTrue(descriptor.hasSticks)
		XCTAssertTrue(descriptor.hasTriggers)
		XCTAssertTrue(descriptor.showsGripOrPaddleSection)
		XCTAssertEqual(descriptor.gripOrPaddleSectionTitle, "BACK PADDLES")
		XCTAssertEqual(descriptor.displayName, "8BitDo Ultimate 2")
		XCTAssertEqual(descriptor.leftSystemButtons, [.view, .xbox])
		XCTAssertEqual(descriptor.rightSystemButtons, [.menu])

		let supported = descriptor.supportedButtons
		XCTAssertTrue(supported.isSuperset(of: ControllerButton.xboxEliteButtons))
		XCTAssertTrue(supported.isSuperset(of: [.a, .b, .x, .y, .xbox, .leftTrigger, .rightTrigger]))
		XCTAssertFalse(supported.contains(.share))
		XCTAssertFalse(supported.contains(.leftPaddle), "DualSense Edge paddles are not on this pad")
	}

	func testUltimate2PreviewLayoutMetadata() {
		let layout = ControllerPreviewLayout.eightBitDoUltimate2
		XCTAssertEqual(layout.displayName, "8BitDo Ultimate 2")
		XCTAssertEqual(layout.platformLabel, "Ultimate 2 Wireless")
		XCTAssertEqual(ControllerVisualDescriptor.concrete(for: layout)?.family, .eightBitDoUltimate2)
		XCTAssertNotNil(layout.pairingGuide)
	}
}

final class EightBitDoUltimate2DatabaseTests: XCTestCase {
	private static var retainedDatabases: [GameControllerDatabase] = []

	func testBundledDatabaseCarriesUltimate2BluetoothMacRow() throws {
		let path = try XCTUnwrap(
			Bundle(for: GameControllerDatabase.self).path(forResource: "gamecontrollerdb", ofType: "txt"),
			"Bundled gamecontrollerdb.txt should ship in the app"
		)
		let content = try String(contentsOfFile: path, encoding: .utf8)
		let database = GameControllerDatabase(databaseContentOverride: content)
		Self.retainedDatabases.append(database)

		let guid = GameControllerDatabase.constructGUID(
			vendorID: 0x2DC8,
			productID: 0x6012,
			version: 0x0001,
			transport: "Bluetooth"
		)
		XCTAssertEqual(guid, "05000000c82d00001260000001000000")

		let mapping = try XCTUnwrap(database.lookup(guid: guid))
		XCTAssertEqual(mapping.name, "8BitDo Ultimate 2 Wireless")
		XCTAssertTrue(ControllerService.isEightBitDoUltimate2(controllerName: mapping.name))

		let expectedButtons: [String: Int] = [
			"a": 0, "b": 1, "x": 3, "y": 4,
			"back": 10, "start": 11, "guide": 12,
			"leftshoulder": 6, "rightshoulder": 7,
			"leftstick": 13, "rightstick": 14,
			"paddle1": 16, "paddle2": 17, "paddle3": 5, "paddle4": 2,
		]
		for (name, index) in expectedButtons {
			if case let .button(actual)? = mapping.buttonMap[name] {
				XCTAssertEqual(actual, index, "\(name) should be b\(index)")
			} else {
				XCTFail("Expected \(name) to map to button b\(index)")
			}
		}
	}
}
