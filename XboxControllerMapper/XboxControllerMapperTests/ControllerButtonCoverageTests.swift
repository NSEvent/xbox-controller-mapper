import XCTest
@testable import ControllerKeys

final class ControllerButtonCoverageTests: XCTestCase {

    func testAllCases_ExposeStableMetadata() {
        for button in ControllerButton.allCases {
            XCTAssertFalse(button.displayName.isEmpty)
            XCTAssertFalse(button.shortLabel.isEmpty)
            XCTAssertFalse(button.displayName(forDualSense: false).isEmpty)
            XCTAssertFalse(button.displayName(forDualSense: true).isEmpty)
            XCTAssertFalse(button.shortLabel(forDualSense: false).isEmpty)
            XCTAssertFalse(button.shortLabel(forDualSense: true).isEmpty)

            _ = button.systemImageName
            _ = button.systemImageName(forDualSense: false)
            _ = button.systemImageName(forDualSense: true)
            _ = button.category
            _ = button.isDualSenseOnly
            _ = button.isDualSenseEdgeOnly
        }
    }

    func testDualSenseOnlyAndEdgeOnlyClassification() {
        let expectedDualSenseOnly: Set<ControllerButton> = [
            .touchpadButton,
            .touchpadTwoFingerButton,
            .touchpadTap,
            .touchpadTwoFingerTap,
            .micMute,
            .leftPaddle,
            .rightPaddle,
            .leftFunction,
            .rightFunction
        ]

        let expectedEdgeOnly: Set<ControllerButton> = [
            .leftPaddle,
            .rightPaddle,
            .leftFunction,
            .rightFunction
        ]

        let dualSenseOnly = Set(ControllerButton.allCases.filter { $0.isDualSenseOnly })
        let edgeOnly = Set(ControllerButton.allCases.filter { $0.isDualSenseEdgeOnly })

        XCTAssertEqual(dualSenseOnly, expectedDualSenseOnly)
        XCTAssertEqual(edgeOnly, expectedEdgeOnly)
        XCTAssertTrue(edgeOnly.isSubset(of: dualSenseOnly))
    }

    func testXboxAndDualSenseButtonLists() {
        XCTAssertFalse(ControllerButton.xboxButtons.contains(.touchpadTap))
        XCTAssertFalse(ControllerButton.xboxButtons.contains(.leftPaddle))
        XCTAssertTrue(ControllerButton.xboxButtons.contains(.a))

        XCTAssertFalse(ControllerButton.dualSenseButtons.contains(.share), "Standard DualSense does not expose Share")
        XCTAssertTrue(ControllerButton.dualSenseButtons.contains(.touchpadButton))
        XCTAssertTrue(ControllerButton.dualSenseButtons.contains(.a))
    }

    func testDualSenseLabelOverrides() {
        XCTAssertEqual(ControllerButton.a.displayName(forDualSense: true), "Cross")
        XCTAssertEqual(ControllerButton.b.displayName(forDualSense: true), "Circle")
        XCTAssertEqual(ControllerButton.x.displayName(forDualSense: true), "Square")
        XCTAssertEqual(ControllerButton.y.displayName(forDualSense: true), "Triangle")
        XCTAssertEqual(ControllerButton.menu.displayName(forDualSense: true), "Options")
        XCTAssertEqual(ControllerButton.view.displayName(forDualSense: true), "Create")
        XCTAssertEqual(ControllerButton.xbox.displayName(forDualSense: true), "PS")

        XCTAssertEqual(ControllerButton.a.shortLabel(forDualSense: true), "✕")
        XCTAssertEqual(ControllerButton.b.shortLabel(forDualSense: true), "○")
        XCTAssertEqual(ControllerButton.x.shortLabel(forDualSense: true), "□")
        XCTAssertEqual(ControllerButton.y.shortLabel(forDualSense: true), "△")
    }

    func testSystemImageNameMappings() {
        XCTAssertEqual(ControllerButton.xbox.systemImageName(forDualSense: false), "xbox.logo")
        XCTAssertEqual(ControllerButton.xbox.systemImageName(forDualSense: true), "playstation.logo")
        XCTAssertEqual(ControllerButton.view.systemImageName(forDualSense: false), "rectangle.on.rectangle")
        XCTAssertEqual(ControllerButton.view.systemImageName(forDualSense: true), "square.and.arrow.up")
        XCTAssertNil(ControllerButton.a.systemImageName(forDualSense: true), "DualSense face buttons use text symbols")
    }

    func testCategoryCoverageAndOrdering() {
        let categories = Set(ControllerButton.allCases.map(\.category))
        XCTAssertEqual(categories, Set(ButtonCategory.allCases))

        for category in ButtonCategory.allCases {
            XCTAssertFalse(category.displayName.isEmpty)
            XCTAssertGreaterThanOrEqual(category.chordDisplayOrder, 0)
        }

        let uniqueOrderValues = Set(ButtonCategory.allCases.map(\.chordDisplayOrder))
        XCTAssertEqual(uniqueOrderValues.count, ButtonCategory.allCases.count)
    }
}
