import XCTest
import CoreGraphics
import Carbon.HIToolbox
@testable import ControllerKeys

final class ModifierKeyEmissionPolicyTests: XCTestCase {
	func testDefaultsUseLeftModifierKeys() {
		XCTAssertEqual(ModifierKeyEmissionPolicy.defaultKeyCode(for: .maskCommand), CGKeyCode(kVK_Command))
		XCTAssertEqual(ModifierKeyEmissionPolicy.defaultKeyCode(for: .maskAlternate), CGKeyCode(kVK_Option))
		XCTAssertEqual(ModifierKeyEmissionPolicy.defaultKeyCode(for: .maskShift), CGKeyCode(kVK_Shift))
		XCTAssertEqual(ModifierKeyEmissionPolicy.defaultKeyCode(for: .maskControl), CGKeyCode(kVK_Control))
	}

	func testSideAwarePolicyHonorsRightModifierKeys() {
		let sides = ModifierFlags(
			command: true,
			option: true,
			shift: true,
			control: true,
			commandSide: .right,
			optionSide: .right,
			shiftSide: .right,
			controlSide: .right
		)

		XCTAssertEqual(ModifierKeyEmissionPolicy.keyCode(for: .maskCommand, sides: sides), CGKeyCode(kVK_RightCommand))
		XCTAssertEqual(ModifierKeyEmissionPolicy.keyCode(for: .maskAlternate, sides: sides), CGKeyCode(kVK_RightOption))
		XCTAssertEqual(ModifierKeyEmissionPolicy.keyCode(for: .maskShift, sides: sides), CGKeyCode(kVK_RightShift))
		XCTAssertEqual(ModifierKeyEmissionPolicy.keyCode(for: .maskControl, sides: sides), CGKeyCode(kVK_RightControl))
	}

	func testUnsetSidesFallBackToDefaults() {
		let sides = ModifierFlags(command: true, option: true, shift: true, control: true)
		XCTAssertEqual(ModifierKeyEmissionPolicy.keyCode(for: .maskCommand, sides: sides), CGKeyCode(kVK_Command))
		XCTAssertEqual(ModifierKeyEmissionPolicy.keyCode(for: .maskAlternate, sides: sides), CGKeyCode(kVK_Option))
		XCTAssertEqual(ModifierKeyEmissionPolicy.keyCode(for: .maskShift, sides: sides), CGKeyCode(kVK_Shift))
		XCTAssertEqual(ModifierKeyEmissionPolicy.keyCode(for: .maskControl, sides: sides), CGKeyCode(kVK_Control))
	}

	func testPressAndReleaseOrdersStayStable() {
		XCTAssertEqual(
			ModifierKeyEmissionPolicy.modifierPressOrder,
			[.maskCommand, .maskShift, .maskAlternate, .maskControl]
		)
		XCTAssertEqual(
			ModifierKeyEmissionPolicy.modifierReleaseOrder,
			[.maskControl, .maskAlternate, .maskShift, .maskCommand]
		)
	}

	func testShiftHoldEventsUseFlagsChangedAndExpectedFlags() throws {
		let source = CGEventSource(stateID: .hidSystemState)
		let down = try XCTUnwrap(
			ModifierKeyEmissionPolicy.makeEvent(
				source: source,
				keyCode: CGKeyCode(kVK_Shift),
				keyDown: true,
				flags: [.maskShift]
			)
		)
		let up = try XCTUnwrap(
			ModifierKeyEmissionPolicy.makeEvent(
				source: source,
				keyCode: CGKeyCode(kVK_Shift),
				keyDown: false,
				flags: []
			)
		)

		XCTAssertEqual(down.type, .flagsChanged)
		XCTAssertEqual(
			down.getIntegerValueField(.keyboardEventKeycode),
			Int64(kVK_Shift)
		)
		XCTAssertTrue(down.flags.contains(.maskShift))

		XCTAssertEqual(up.type, .flagsChanged)
		XCTAssertEqual(
			up.getIntegerValueField(.keyboardEventKeycode),
			Int64(kVK_Shift)
		)
		XCTAssertFalse(up.flags.contains(.maskShift))
	}
}
