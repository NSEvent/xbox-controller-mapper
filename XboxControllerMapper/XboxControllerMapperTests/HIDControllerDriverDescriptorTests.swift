import XCTest
@testable import ControllerKeys

final class HIDControllerDriverDescriptorTests: XCTestCase {
	func testNintendoDescriptorMatchesOnlyNintendoProController() {
		let descriptor = NintendoHIDDriverDescriptor()
		XCTAssertEqual(
			descriptor.matchingCriteria,
			[.vendorProduct(vendorID: 0x057E, productID: 0x2009)]
		)
		XCTAssertEqual(CFArrayGetCount(descriptor.matchingCFArray), 1)
	}

	func testEightBitDoDescriptorCoversDInputPadsWithMissingHomeButton() {
		let descriptor = EightBitDoDInputHIDDriverDescriptor()
		XCTAssertEqual(
			Set(descriptor.matchingCriteria),
			Set([
				.vendorProduct(vendorID: 0x2DC8, productID: 0x9020),
				.vendorProduct(vendorID: 0x2DC8, productID: 0x3230),
				.vendorProduct(vendorID: 0x2DC8, productID: 0x5112),
			])
		)
		XCTAssertEqual(CFArrayGetCount(descriptor.matchingCFArray), 3)
	}

	func testGenericDescriptorKeepsKnownPairsBeforeBroadFallbacks() {
		let descriptor = GenericHIDDriverDescriptor(
			knownVendorProductPairs: [
				(vendorID: 0x1234, productID: 0x0001),
				(vendorID: 0x5678, productID: 0x0002),
			]
		)

		XCTAssertEqual(
			Array(descriptor.matchingCriteria.prefix(2)),
			[
				.vendorProduct(vendorID: 0x1234, productID: 0x0001),
				.vendorProduct(vendorID: 0x5678, productID: 0x0002),
			]
		)
		XCTAssertTrue(descriptor.matchingCriteria.contains(.transport("BluetoothLowEnergy")))
		XCTAssertTrue(descriptor.matchingCriteria.contains(.transport("Bluetooth Low Energy")))
		XCTAssertEqual(CFArrayGetCount(descriptor.matchingCFArray), descriptor.matchingCriteria.count)
	}

	func testGenericDescriptorExcludesSpecializedRawBackendsFromKnownPairs() {
		XCTAssertTrue(GenericHIDDriverDescriptor.excludedVendorIDs.contains(0x045E))
		XCTAssertTrue(GenericHIDDriverDescriptor.excludedVendorIDs.contains(0x054C))
		XCTAssertTrue(GenericHIDDriverDescriptor.excludedVendorIDs.contains(0x057E))
		XCTAssertTrue(GenericHIDDriverDescriptor.excludedVendorIDs.contains(SteamControllerHIDParser.valveVendorID))
	}
}
