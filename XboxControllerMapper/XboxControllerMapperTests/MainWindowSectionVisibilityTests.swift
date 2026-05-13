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

    func testDisplayOrderMatchesNavigationGroups() {
        let groupedSections = Dictionary(grouping: MainWindowSection.displayOrder, by: \.navGroup)

        XCTAssertEqual(groupedSections[.map], [.buttons, .chords, .sequences, .gestures])
        XCTAssertEqual(groupedSections[.automate], [.macros, .scripts, .wheel, .keyboard])
        XCTAssertEqual(groupedSections[.hardware], [.joysticks, .touchpad, .leds, .microphone])
        XCTAssertEqual(groupedSections[.activity], [.stats, .history])
    }

    func testTabItemsExposeNavigationMetadata() {
        let buttonTab = MainWindowSection.buttons.tabItem
        XCTAssertEqual(buttonTab.group, .map)
        XCTAssertEqual(buttonTab.systemImage, "gamecontroller.fill")
        XCTAssertFalse(buttonTab.isGlobal)

        let keyboardTab = MainWindowSection.keyboard.tabItem
        XCTAssertEqual(keyboardTab.group, .automate)
        XCTAssertEqual(keyboardTab.systemImage, "keyboard")
        XCTAssertTrue(keyboardTab.isGlobal)
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
