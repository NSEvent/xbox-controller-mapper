import XCTest
import CoreGraphics
import Carbon.HIToolbox
@testable import ControllerKeys

final class KeyboardNavigationMapTests: XCTestCase {

    func testAllRowsWithoutExtendedFunctions_HasExpectedStructure() {
        let rows = KeyboardNavigationMap.allRows(includeExtendedFunctions: false)

        XCTAssertEqual(rows.count, 7)
        XCTAssertEqual(rows[0].count, 8, "Media row should contain 8 keys")
        XCTAssertEqual(rows[1].count, 13, "Function row should contain Esc + F1-F12")
        XCTAssertEqual(rows[2].count, 14, "Number row should contain 14 keys")
        XCTAssertEqual(rows[3].count, 14, "QWERTY row should contain 14 keys")
        XCTAssertEqual(rows[4].count, 13, "ASDF row should contain 13 keys")
        XCTAssertEqual(rows[5].count, 12, "ZXCV row should contain 12 keys")
        XCTAssertEqual(rows[6].count, 10, "Bottom row should contain 10 keys")
    }

    func testAllRowsWithExtendedFunctions_InsertsExtendedRow() {
        let rows = KeyboardNavigationMap.allRows(includeExtendedFunctions: true)

        XCTAssertEqual(rows.count, 8)
        XCTAssertEqual(rows[1].count, 8, "Extended function row should contain F13-F20")

        let extCodes = rows[1].map(\.keyCode)
        XCTAssertEqual(extCodes.first, CGKeyCode(kVK_F13))
        XCTAssertEqual(extCodes.last, CGKeyCode(kVK_F20))
    }

    func testDefaultKey_IsSpace() {
        XCTAssertEqual(KeyboardNavigationMap.defaultKey, CGKeyCode(kVK_Space))
    }

    func testFindPosition_FindsRegularAndNavigationKeys() {
        let space = KeyboardNavigationMap.findPosition(for: CGKeyCode(kVK_Space), includeExtendedFunctions: false)
        XCTAssertEqual(space?.rowIndex, 6)

        let navWithoutExtended = KeyboardNavigationMap.findPosition(for: CGKeyCode(kVK_ForwardDelete), includeExtendedFunctions: false)
        XCTAssertEqual(navWithoutExtended?.rowIndex, 2)

        let navWithExtended = KeyboardNavigationMap.findPosition(for: CGKeyCode(kVK_ForwardDelete), includeExtendedFunctions: true)
        XCTAssertEqual(navWithExtended?.rowIndex, 3)
    }

    func testNavigate_NilCurrentKeyStartsAtSpace() {
        let next = KeyboardNavigationMap.navigate(from: nil, direction: .right, includeExtendedFunctions: false)
        XCTAssertEqual(next, CGKeyCode(kVK_Space))
    }

    func testNavigate_LeftAndRightInsideRow() {
        let leftOfW = KeyboardNavigationMap.navigate(from: CGKeyCode(kVK_ANSI_W), direction: .left, includeExtendedFunctions: false)
        XCTAssertEqual(leftOfW, CGKeyCode(kVK_ANSI_Q))

        let rightOfW = KeyboardNavigationMap.navigate(from: CGKeyCode(kVK_ANSI_W), direction: .right, includeExtendedFunctions: false)
        XCTAssertEqual(rightOfW, CGKeyCode(kVK_ANSI_E))
    }

    func testNavigate_UpAndDownUseClosestXPosition() {
        let downFromF6 = KeyboardNavigationMap.navigate(from: CGKeyCode(kVK_F6), direction: .down, includeExtendedFunctions: false)
        XCTAssertNotNil(downFromF6)

        let backUp = KeyboardNavigationMap.navigate(from: downFromF6, direction: .up, includeExtendedFunctions: false)
        XCTAssertEqual(backUp, CGKeyCode(kVK_F6))
    }

    func testNavigate_RightEdgeMovesToNavigationColumn() {
        let next = KeyboardNavigationMap.navigate(from: CGKeyCode(kVK_Delete), direction: .right, includeExtendedFunctions: false)
        XCTAssertEqual(next, CGKeyCode(kVK_ForwardDelete))
    }

    func testNavigate_WithinNavigationColumn() {
        let up = KeyboardNavigationMap.navigate(from: CGKeyCode(kVK_End), direction: .up, includeExtendedFunctions: false)
        XCTAssertEqual(up, CGKeyCode(kVK_Home))

        let down = KeyboardNavigationMap.navigate(from: CGKeyCode(kVK_End), direction: .down, includeExtendedFunctions: false)
        XCTAssertEqual(down, CGKeyCode(kVK_PageUp))

        let right = KeyboardNavigationMap.navigate(from: CGKeyCode(kVK_End), direction: .right, includeExtendedFunctions: false)
        XCTAssertEqual(right, CGKeyCode(kVK_End), "Navigation column cannot move further right")

        let left = KeyboardNavigationMap.navigate(from: CGKeyCode(kVK_Home), direction: .left, includeExtendedFunctions: false)
        XCTAssertEqual(left, CGKeyCode(kVK_ANSI_Backslash), "Left from Home should land on last key of QWERTY row")
    }

    func testNavigate_UnknownCurrentKeyFallsBackToSpace() {
        let unknown: CGKeyCode = 0xFFFF
        let next = KeyboardNavigationMap.navigate(from: unknown, direction: .left, includeExtendedFunctions: false)
        XCTAssertEqual(next, CGKeyCode(kVK_Space))
    }
}
