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
}
