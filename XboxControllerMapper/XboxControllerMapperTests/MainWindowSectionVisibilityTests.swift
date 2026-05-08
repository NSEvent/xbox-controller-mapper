import XCTest
@testable import ControllerKeys

final class MainWindowSectionVisibilityTests: XCTestCase {
    func testDefaultVisibleSectionsPreserveDisplayOrder() {
        let sections = MainWindowSection.visibleSections(
            hiddenSections: [],
            isPlayStation: true,
            isDualSense: true
        )

        XCTAssertEqual(sections, MainWindowSection.displayOrder)
    }

    func testVisibleSectionsRespectControllerCapabilities() {
        let sections = MainWindowSection.visibleSections(
            hiddenSections: [],
            isPlayStation: false,
            isDualSense: false
        )

        XCTAssertFalse(sections.contains(.gestures))
        XCTAssertFalse(sections.contains(.touchpad))
        XCTAssertFalse(sections.contains(.leds))
        XCTAssertFalse(sections.contains(.microphone))
        XCTAssertTrue(sections.contains(.buttons))
        XCTAssertTrue(sections.contains(.joysticks))
    }

    func testVisibleSectionsFilterHiddenSections() {
        let sections = MainWindowSection.visibleSections(
            hiddenSections: [.chords, .sequences, .macros],
            isPlayStation: true,
            isDualSense: true
        )

        XCTAssertFalse(sections.contains(.chords))
        XCTAssertFalse(sections.contains(.sequences))
        XCTAssertFalse(sections.contains(.macros))
        XCTAssertTrue(sections.contains(.buttons))
        XCTAssertTrue(sections.contains(.touchpad))
    }

    func testHiddenSectionEncodingRoundTripsAndIgnoresInvalidTags() {
        let encoded = MainWindowSection.encodedHiddenSections([.macros, .buttons, .touchpad])
        XCTAssertEqual(encoded, "0,4,7")

        let decoded = MainWindowSection.hiddenSections(from: "0,4,7,999,bad")
        XCTAssertEqual(decoded, [.buttons, .touchpad, .macros])
    }
}
