import CoreGraphics
import XCTest
@testable import ControllerKeys

final class LayoutMeasurementPolicyTests: XCTestCase {
	func testNormalizesDimensionsToWholePoints() {
		XCTAssertEqual(LayoutMeasurementPolicy.normalizedDimension(42.49), 42)
		XCTAssertEqual(LayoutMeasurementPolicy.normalizedDimension(42.5), 43)
	}

	func testInvalidDimensionsNormalizeToZero() {
		XCTAssertEqual(LayoutMeasurementPolicy.normalizedDimension(-10), 0)
		XCTAssertEqual(LayoutMeasurementPolicy.normalizedDimension(.infinity), 0)
		XCTAssertEqual(LayoutMeasurementPolicy.normalizedDimension(.nan), 0)
	}

	func testIgnoresSubPointJitter() {
		XCTAssertFalse(LayoutMeasurementPolicy.shouldUpdate(current: 200, proposed: 200.4))
		XCTAssertTrue(LayoutMeasurementPolicy.shouldUpdate(current: 200, proposed: 201))
	}

	func testSizeUpdateChecksEitherAxis() {
		XCTAssertFalse(LayoutMeasurementPolicy.shouldUpdate(
			current: CGSize(width: 100, height: 200),
			proposed: CGSize(width: 100.25, height: 200.25)
		))
		XCTAssertTrue(LayoutMeasurementPolicy.shouldUpdate(
			current: CGSize(width: 100, height: 200),
			proposed: CGSize(width: 100, height: 201)
		))
	}
}
