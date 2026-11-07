import XCTest
@testable import ControllerKeys

final class ButtonSwapSelectionTests: XCTestCase {
	func testFirstPickWaitsForSecond() {
		var first: ControllerButton?
		var armed = true
		XCTAssertNil(ButtonSwapSelection.pick(.a, first: &first, isSwapMode: &armed))
		XCTAssertEqual(first, .a)
		XCTAssertTrue(armed)
	}

	func testSecondPickReturnsPairAndDisarms() {
		var first: ControllerButton? = .a
		var armed = true
		let pair = ButtonSwapSelection.pick(.b, first: &first, isSwapMode: &armed)
		XCTAssertEqual(pair?.0, .a)
		XCTAssertEqual(pair?.1, .b)
		XCTAssertNil(first)
		XCTAssertFalse(armed)
	}
}
