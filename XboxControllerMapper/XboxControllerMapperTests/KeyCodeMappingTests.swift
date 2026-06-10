import XCTest
import Combine
import CoreGraphics
import Carbon.HIToolbox
import SwiftUI
import AppKit
@testable import ControllerKeys

// MARK: - KeyCodeMapping Tests

final class KeyCodeMappingTests: XCTestCase {

    // MARK: - Function Key Fn Flag Tests

    /// Tests that F1-F12 require the Fn flag
    func testF1ThroughF12RequireFnFlag() {
        let fKeyCodes: [CGKeyCode] = [
            CGKeyCode(kVK_F1), CGKeyCode(kVK_F2), CGKeyCode(kVK_F3), CGKeyCode(kVK_F4),
            CGKeyCode(kVK_F5), CGKeyCode(kVK_F6), CGKeyCode(kVK_F7), CGKeyCode(kVK_F8),
            CGKeyCode(kVK_F9), CGKeyCode(kVK_F10), CGKeyCode(kVK_F11), CGKeyCode(kVK_F12)
        ]

        for (index, keyCode) in fKeyCodes.enumerated() {
            XCTAssertTrue(
                KeyCodeMapping.requiresFnFlag(keyCode),
                "F\(index + 1) (keyCode \(keyCode)) should require Fn flag"
            )
            let flags = KeyCodeMapping.specialKeyFlags(for: keyCode)
            XCTAssertTrue(
                flags.contains(.maskSecondaryFn),
                "F\(index + 1) should have maskSecondaryFn in specialKeyFlags"
            )
        }
    }

    /// Tests that F13-F20 require the Fn flag (regression test for CSI u escape sequence bug)
    /// Without this flag, terminals using Kitty keyboard protocol output escape sequences
    /// like [57376u instead of triggering hotkeys.
    func testF13ThroughF20RequireFnFlag() {
        let extendedFKeyCodes: [CGKeyCode] = [
            CGKeyCode(kVK_F13), CGKeyCode(kVK_F14), CGKeyCode(kVK_F15), CGKeyCode(kVK_F16),
            CGKeyCode(kVK_F17), CGKeyCode(kVK_F18), CGKeyCode(kVK_F19), CGKeyCode(kVK_F20)
        ]

        for (index, keyCode) in extendedFKeyCodes.enumerated() {
            XCTAssertTrue(
                KeyCodeMapping.requiresFnFlag(keyCode),
                "F\(index + 13) (keyCode \(keyCode)) should require Fn flag"
            )
            let flags = KeyCodeMapping.specialKeyFlags(for: keyCode)
            XCTAssertTrue(
                flags.contains(.maskSecondaryFn),
                "F\(index + 13) should have maskSecondaryFn in specialKeyFlags"
            )
        }
    }

    // MARK: - Navigation Key Flag Tests

    /// Tests that arrow keys require both Fn and NumPad flags
    func testArrowKeysRequireFnAndNumPadFlags() {
        let arrowKeys: [(name: String, code: CGKeyCode)] = [
            ("Left", CGKeyCode(kVK_LeftArrow)),
            ("Right", CGKeyCode(kVK_RightArrow)),
            ("Up", CGKeyCode(kVK_UpArrow)),
            ("Down", CGKeyCode(kVK_DownArrow))
        ]

        for (name, keyCode) in arrowKeys {
            XCTAssertTrue(
                KeyCodeMapping.requiresFnFlag(keyCode),
                "\(name) arrow should require Fn flag"
            )
            XCTAssertTrue(
                KeyCodeMapping.requiresNumPadFlag(keyCode),
                "\(name) arrow should require NumPad flag"
            )

            let flags = KeyCodeMapping.specialKeyFlags(for: keyCode)
            XCTAssertTrue(flags.contains(.maskSecondaryFn), "\(name) arrow should have Fn flag")
            XCTAssertTrue(flags.contains(.maskNumericPad), "\(name) arrow should have NumPad flag")
        }
    }

    /// Tests that navigation keys (Home, End, Page Up/Down, Forward Delete) require proper flags
    func testNavigationKeysRequireProperFlags() {
        let navKeys: [(name: String, code: CGKeyCode)] = [
            ("Home", CGKeyCode(kVK_Home)),
            ("End", CGKeyCode(kVK_End)),
            ("Page Up", CGKeyCode(kVK_PageUp)),
            ("Page Down", CGKeyCode(kVK_PageDown)),
            ("Forward Delete", CGKeyCode(kVK_ForwardDelete))
        ]

        for (name, keyCode) in navKeys {
            XCTAssertTrue(
                KeyCodeMapping.requiresFnFlag(keyCode),
                "\(name) should require Fn flag"
            )
            XCTAssertTrue(
                KeyCodeMapping.requiresNumPadFlag(keyCode),
                "\(name) should require NumPad flag"
            )

            let flags = KeyCodeMapping.specialKeyFlags(for: keyCode)
            XCTAssertTrue(flags.contains(.maskSecondaryFn), "\(name) should have Fn flag")
            XCTAssertTrue(flags.contains(.maskNumericPad), "\(name) should have NumPad flag")
        }
    }

    // MARK: - Regular Key Tests

    /// Tests that regular letter keys don't require special flags
    func testRegularKeysDoNotRequireSpecialFlags() {
        let regularKeys: [CGKeyCode] = [
            CGKeyCode(kVK_ANSI_A), CGKeyCode(kVK_ANSI_Z),
            CGKeyCode(kVK_ANSI_0), CGKeyCode(kVK_ANSI_9),
            CGKeyCode(kVK_Space), CGKeyCode(kVK_Return),
            CGKeyCode(kVK_Tab), CGKeyCode(kVK_Escape)
        ]

        for keyCode in regularKeys {
            let flags = KeyCodeMapping.specialKeyFlags(for: keyCode)
            XCTAssertTrue(
                flags.isEmpty,
                "Regular key \(keyCode) should not require special flags, got \(flags.rawValue)"
            )
            XCTAssertFalse(KeyCodeMapping.requiresFnFlag(keyCode))
            XCTAssertFalse(KeyCodeMapping.requiresNumPadFlag(keyCode))
        }
    }
}
