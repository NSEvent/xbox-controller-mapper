import XCTest
import CoreGraphics
import Carbon.HIToolbox
@testable import ControllerKeys

final class KeyCodeMappingDisplayTests: XCTestCase {

    func testDisplayName_ForKnownRepresentativeKeys() {
        XCTAssertEqual(KeyCodeMapping.displayName(for: CGKeyCode(kVK_Return)), "Return")
        XCTAssertEqual(KeyCodeMapping.displayName(for: CGKeyCode(kVK_LeftArrow)), "←")
        XCTAssertEqual(KeyCodeMapping.displayName(for: CGKeyCode(kVK_F13)), "F13")
        XCTAssertEqual(KeyCodeMapping.displayName(for: CGKeyCode(kVK_ANSI_A)), "A")
        XCTAssertEqual(KeyCodeMapping.displayName(for: CGKeyCode(kVK_ANSI_7)), "7")
        XCTAssertEqual(KeyCodeMapping.displayName(for: KeyCodeMapping.mouseLeftClick), "Left Click")
        XCTAssertEqual(KeyCodeMapping.displayName(for: KeyCodeMapping.mediaPlayPause), "Play/Pause")
        XCTAssertEqual(KeyCodeMapping.displayName(for: KeyCodeMapping.brightnessDown), "Brightness Down")
    }

    func testDisplayName_ForUnknownKeyFallsBackToGenericLabel() {
        let unknown: CGKeyCode = 0xEEEF
        XCTAssertEqual(KeyCodeMapping.displayName(for: unknown), "Key \(unknown)")
    }

    func testAllKeyOptions_HaveUniqueCodesAndNonEmptyNames() {
        let options = KeyCodeMapping.allKeyOptions

        XCTAssertFalse(options.isEmpty)
        XCTAssertTrue(options.contains(where: { $0.name == "On-Screen Keyboard" }))

        for option in options {
            XCTAssertFalse(option.name.isEmpty)
            XCTAssertFalse(KeyCodeMapping.displayName(for: option.code).isEmpty)
        }

        let uniqueCodes = Set(options.map(\.code))
        XCTAssertEqual(uniqueCodes.count, options.count, "Picker options should not duplicate key codes")
    }

    func testKeyInfo_LettersRespectShiftState() {
        let lower = KeyCodeMapping.keyInfo(for: "a")
        XCTAssertEqual(lower?.keyCode, KeyCodeMapping.keyA)
        XCTAssertEqual(lower?.needsShift, false)

        let upper = KeyCodeMapping.keyInfo(for: "A")
        XCTAssertEqual(upper?.keyCode, KeyCodeMapping.keyA)
        XCTAssertEqual(upper?.needsShift, true)
    }

    func testKeyInfo_NumericAndSymbolVariants() {
        let one = KeyCodeMapping.keyInfo(for: "1")
        XCTAssertEqual(one?.keyCode, KeyCodeMapping.key1)
        XCTAssertEqual(one?.needsShift, false)

        let exclamation = KeyCodeMapping.keyInfo(for: "!")
        XCTAssertEqual(exclamation?.keyCode, KeyCodeMapping.key1)
        XCTAssertEqual(exclamation?.needsShift, true)

        let slash = KeyCodeMapping.keyInfo(for: "/")
        XCTAssertEqual(slash?.keyCode, KeyCodeMapping.slash)
        XCTAssertEqual(slash?.needsShift, false)

        let question = KeyCodeMapping.keyInfo(for: "?")
        XCTAssertEqual(question?.keyCode, KeyCodeMapping.slash)
        XCTAssertEqual(question?.needsShift, true)

        let newline = KeyCodeMapping.keyInfo(for: "\n")
        XCTAssertEqual(newline?.keyCode, KeyCodeMapping.return)
        XCTAssertEqual(newline?.needsShift, false)

        let tab = KeyCodeMapping.keyInfo(for: "\t")
        XCTAssertEqual(tab?.keyCode, KeyCodeMapping.tab)
        XCTAssertEqual(tab?.needsShift, false)
    }

    func testKeyInfo_UnsupportedCharacterReturnsNil() {
        XCTAssertNil(KeyCodeMapping.keyInfo(for: "😀"))
    }

    func testSpecialMarkerClassifiers() {
        XCTAssertTrue(KeyCodeMapping.isMouseButton(KeyCodeMapping.mouseLeftClick))
        XCTAssertTrue(KeyCodeMapping.isMouseButton(KeyCodeMapping.mouseRightClick))
        XCTAssertTrue(KeyCodeMapping.isMouseButton(KeyCodeMapping.mouseMiddleClick))
        XCTAssertFalse(KeyCodeMapping.isMouseButton(KeyCodeMapping.keyA))

        XCTAssertTrue(KeyCodeMapping.isSpecialAction(KeyCodeMapping.showOnScreenKeyboard))
        XCTAssertFalse(KeyCodeMapping.isSpecialAction(KeyCodeMapping.keyA))

        XCTAssertTrue(KeyCodeMapping.isMediaKey(KeyCodeMapping.mediaPlayPause))
        XCTAssertTrue(KeyCodeMapping.isMediaKey(KeyCodeMapping.volumeUp))
        XCTAssertTrue(KeyCodeMapping.isMediaKey(KeyCodeMapping.brightnessUp))
        XCTAssertFalse(KeyCodeMapping.isMediaKey(KeyCodeMapping.keyA))

        XCTAssertTrue(KeyCodeMapping.isSpecialMarker(KeyCodeMapping.mouseLeftClick))
        XCTAssertTrue(KeyCodeMapping.isSpecialMarker(KeyCodeMapping.showOnScreenKeyboard))
        XCTAssertTrue(KeyCodeMapping.isSpecialMarker(KeyCodeMapping.mediaNext))
        XCTAssertFalse(KeyCodeMapping.isSpecialMarker(KeyCodeMapping.keyA))
    }
}
