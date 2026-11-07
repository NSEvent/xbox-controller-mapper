import IOKit.hid
import XCTest
@testable import ControllerKeys

final class FootPedalIdentityTests: XCTestCase {
	func testMatchesVECInfinityVendorAndProduct() {
		XCTAssertTrue(FootPedalIdentity.matches(vendorID: 0x05F3, productID: 0x00FF))
		XCTAssertFalse(FootPedalIdentity.matches(vendorID: 0x05F3, productID: 0x00FE))
		XCTAssertFalse(FootPedalIdentity.matches(vendorID: 0x05AC, productID: 0x00FF))
		XCTAssertFalse(FootPedalIdentity.matches(vendorID: nil, productID: nil))
	}

	@MainActor
	func testDriverDescriptorMatchesOnlyThePedal() {
		let descriptor = FootPedalHIDDriverDescriptor()
		XCTAssertEqual(descriptor.matchingCriteria, [.vendorProduct(vendorID: 0x05F3, productID: 0x00FF)])
		XCTAssertEqual(CFArrayGetCount(descriptor.matchingCFArray), 1)
	}

	func testPedalVendorIsNotAdoptedByGenericHIDPath() {
		// The pedal is a Consumer-page device, so it must never satisfy the
		// generic gamepad/joystick usage criteria.
		let usages = GenericHIDDriverDescriptor.standardControllerCriteria
		XCTAssertFalse(usages.contains(.usage(page: Int(kHIDPage_Consumer), usage: Int(kHIDUsage_Csmr_ConsumerControl))))
	}
}

final class FootPedalReportDecoderTests: XCTestCase {
	private typealias Event = FootPedalReportDecoder.Event

	func testEachBitMapsToItsPedalLeftToRight() {
		var decoder = FootPedalReportDecoder()
		XCTAssertEqual(decoder.process(report: [0x01, 0x00]), [Event(button: .footPedalLeft, pressed: true)])
		XCTAssertEqual(decoder.process(report: [0x00, 0x00]), [Event(button: .footPedalLeft, pressed: false)])
		XCTAssertEqual(decoder.process(report: [0x02, 0x00]), [Event(button: .footPedalMiddle, pressed: true)])
		XCTAssertEqual(decoder.process(report: [0x00, 0x00]), [Event(button: .footPedalMiddle, pressed: false)])
		XCTAssertEqual(decoder.process(report: [0x04, 0x00]), [Event(button: .footPedalRight, pressed: true)])
		XCTAssertEqual(decoder.process(report: [0x00, 0x00]), [Event(button: .footPedalRight, pressed: false)])
	}

	func testOverlappingPedalsEmitIndependentEdges() {
		var decoder = FootPedalReportDecoder()
		XCTAssertEqual(decoder.process(report: [0x02, 0x00]), [Event(button: .footPedalMiddle, pressed: true)])
		// Left joins while middle is still held: only left changes.
		XCTAssertEqual(decoder.process(report: [0x03, 0x00]), [Event(button: .footPedalLeft, pressed: true)])
		// Middle lifts, left stays down.
		XCTAssertEqual(decoder.process(report: [0x01, 0x00]), [Event(button: .footPedalMiddle, pressed: false)])
		XCTAssertEqual(decoder.pressedMask, 0x01)
	}

	func testRepeatedReportsAndPaddingBitsProduceNoEvents() {
		var decoder = FootPedalReportDecoder()
		_ = decoder.process(report: [0x04, 0x00])
		XCTAssertEqual(decoder.process(report: [0x04, 0x00]), [])
		XCTAssertEqual(decoder.process(report: [0xFC, 0xFF]), [], "constant padding bits are ignored")
		XCTAssertEqual(decoder.process(report: []), [])
	}

	func testResetReleasesEveryHeldPedal() {
		var decoder = FootPedalReportDecoder()
		_ = decoder.process(report: [0x07, 0x00])
		XCTAssertEqual(
			decoder.reset(),
			[
				Event(button: .footPedalLeft, pressed: false),
				Event(button: .footPedalMiddle, pressed: false),
				Event(button: .footPedalRight, pressed: false),
			]
		)
		XCTAssertEqual(decoder.reset(), [])
	}
}

final class FootPedalButtonInventoryTests: XCTestCase {
	func testPedalButtonsStayOffGamepadLayouts() {
		for button in ControllerButton.footPedalButtons {
			XCTAssertTrue(button.isFootPedalOnly)
			XCTAssertFalse(ControllerButton.xboxButtons.contains(button))
			XCTAssertFalse(ControllerButton.dualSenseButtons.contains(button))
			XCTAssertFalse(ControllerButton.dualShockButtons.contains(button))
			XCTAssertFalse(ControllerButton.nintendoButtons.contains(button))
		}
	}

	func testFootPedalLayoutExposesExactlyThreePedals() {
		let descriptor = ControllerVisualDescriptor.concrete(for: .footPedal)!
		XCTAssertEqual(descriptor.supportedButtons, Set(ControllerButton.footPedalButtons))
		XCTAssertFalse(descriptor.hasSticks)
		XCTAssertFalse(descriptor.hasTriggers)
		XCTAssertNil(descriptor.minimapStyle)
		XCTAssertEqual(descriptor.displayName, "VEC Infinity Pedal")
	}

	@MainActor
	func testActivePedalWinsOnlyWhenNoOtherAuxiliaryInputIsActive() {
		let storage = ControllerStorage()
		let state = storage.lock.withLock { storage.controllerPresentationStateLocked }
		XCTAssertEqual(
			ControllerVisualDescriptor.active(from: state, ouraRingIsActive: false, beamdeskHandsAreActive: false, footPedalIsActive: true).family,
			.footPedal
		)
		XCTAssertEqual(
			ControllerVisualDescriptor.active(from: state, ouraRingIsActive: false, beamdeskHandsAreActive: false, s29RingIsActive: true, footPedalIsActive: true).family,
			.s29Ring
		)
	}
}
