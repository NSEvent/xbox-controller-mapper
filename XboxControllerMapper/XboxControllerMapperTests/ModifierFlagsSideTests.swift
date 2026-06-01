import XCTest
import CoreGraphics
import Carbon.HIToolbox
@testable import ControllerKeys

final class ModifierFlagsSideTests: XCTestCase {

    func testVirtualKey_DefaultsToLeftWhenNoSideSet() {
        let flags = ModifierFlags(command: true, option: true, shift: true, control: true)
        XCTAssertEqual(flags.virtualKey(forMask: .maskCommand), CGKeyCode(kVK_Command))
        XCTAssertEqual(flags.virtualKey(forMask: .maskAlternate), CGKeyCode(kVK_Option))
        XCTAssertEqual(flags.virtualKey(forMask: .maskShift), CGKeyCode(kVK_Shift))
        XCTAssertEqual(flags.virtualKey(forMask: .maskControl), CGKeyCode(kVK_Control))
    }

    func testVirtualKey_HonorsRightSide() {
        let flags = ModifierFlags(
            command: true, option: true, shift: true, control: true,
            commandSide: .right, optionSide: .right, shiftSide: .right, controlSide: .right
        )
        XCTAssertEqual(flags.virtualKey(forMask: .maskCommand), CGKeyCode(kVK_RightCommand))
        XCTAssertEqual(flags.virtualKey(forMask: .maskAlternate), CGKeyCode(kVK_RightOption))
        XCTAssertEqual(flags.virtualKey(forMask: .maskShift), CGKeyCode(kVK_RightShift))
        XCTAssertEqual(flags.virtualKey(forMask: .maskControl), CGKeyCode(kVK_RightControl))
    }

    func testVirtualKey_HonorsExplicitLeftSide() {
        let flags = ModifierFlags(command: true, commandSide: .left)
        XCTAssertEqual(flags.virtualKey(forMask: .maskCommand), CGKeyCode(kVK_Command))
    }

    func testCgEventFlags_IgnoresSide() {
        // OS-level mask is the same regardless of side
        let leftFlags = ModifierFlags(command: true, commandSide: .left)
        let rightFlags = ModifierFlags(command: true, commandSide: .right)
        let unspecifiedFlags = ModifierFlags(command: true)
        XCTAssertEqual(leftFlags.cgEventFlags, .maskCommand)
        XCTAssertEqual(rightFlags.cgEventFlags, .maskCommand)
        XCTAssertEqual(unspecifiedFlags.cgEventFlags, .maskCommand)
    }

    func testLabel_FormatsSidePrefix() {
        XCTAssertEqual(ModifierFlags.label(for: nil), "")
        XCTAssertEqual(ModifierFlags.label(for: .left), "L")
        XCTAssertEqual(ModifierFlags.label(for: .right), "R")
    }

    // MARK: - Codable backward compatibility

    func testDecode_LegacyJsonWithoutSideFields() throws {
        // JSON shape from before this feature — no *Side keys
        let legacy = """
        {"command": true, "option": false, "shift": true, "control": false}
        """.data(using: .utf8)!

        let flags = try JSONDecoder().decode(ModifierFlags.self, from: legacy)
        XCTAssertTrue(flags.command)
        XCTAssertFalse(flags.option)
        XCTAssertTrue(flags.shift)
        XCTAssertFalse(flags.control)
        XCTAssertNil(flags.commandSide)
        XCTAssertNil(flags.optionSide)
        XCTAssertNil(flags.shiftSide)
        XCTAssertNil(flags.controlSide)
    }

    func testDecode_NewJsonWithSideFields() throws {
        let json = """
        {
            "command": true, "option": false, "shift": true, "control": false,
            "commandSide": "right", "shiftSide": "left"
        }
        """.data(using: .utf8)!

        let flags = try JSONDecoder().decode(ModifierFlags.self, from: json)
        XCTAssertEqual(flags.commandSide, .right)
        XCTAssertEqual(flags.shiftSide, .left)
        XCTAssertNil(flags.optionSide)
        XCTAssertNil(flags.controlSide)
    }

    func testRoundTrip_SidesPreserved() throws {
        let original = ModifierFlags(
            command: true, option: true, shift: false, control: false,
            commandSide: .right, optionSide: .left
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ModifierFlags.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}
