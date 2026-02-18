import XCTest
@testable import ControllerKeys

@MainActor
final class CommandWheelManagerTests: XCTestCase {
    private var manager: CommandWheelManager!

    override func setUp() {
        super.setUp()
        manager = CommandWheelManager.shared
        resetManager()
    }

    override func tearDown() {
        resetManager()
        manager = nil
        super.tearDown()
    }

    func testPrepare_PrefersWebsiteItemsWhenConfigured() {
        let apps = [AppBarItem(bundleIdentifier: "com.apple.finder", displayName: "Finder")]
        let websites = [
            WebsiteLink(url: "https://example.com", displayName: "Example"),
            WebsiteLink(url: "https://apple.com", displayName: "Apple")
        ]

        manager.prepare(apps: apps, websites: websites, showWebsitesFirst: true)

        XCTAssertEqual(manager.items.count, 2)
        XCTAssertFalse(manager.isShowingAlternate)
        XCTAssertNil(manager.selectedIndex)
    }

    func testSetShowingAlternate_SwapsImmediatelyAndSwapsBackAfterTolerance() {
        let apps = [AppBarItem(bundleIdentifier: "com.apple.finder", displayName: "Finder")]
        let websites = [WebsiteLink(url: "https://example.com", displayName: "Example")]
        var itemSetChanges: [Bool] = []
        manager.onItemSetChanged = { isAlternate in
            itemSetChanges.append(isAlternate)
        }
        manager.prepare(apps: apps, websites: websites, showWebsitesFirst: false)

        manager.setShowingAlternate(true)
        XCTAssertTrue(manager.isShowingAlternate)
        XCTAssertEqual(manager.items.count, 1)

        manager.setShowingAlternate(false)
        manager.updateSelection(stickX: 0.6, stickY: 0) // checkAlternateRelease runs here
        XCTAssertTrue(manager.isShowingAlternate)

        Thread.sleep(forTimeInterval: 0.35)
        manager.updateSelection(stickX: 0.6, stickY: 0)

        XCTAssertFalse(manager.isShowingAlternate)
        XCTAssertEqual(itemSetChanges, [true, false])
    }

    func testUpdateSelection_DeadzoneAndReleaseReset() {
        manager.prepare(
            apps: [],
            websites: [WebsiteLink(url: "https://example.com", displayName: "Example")],
            showWebsitesFirst: true
        )

        manager.updateSelection(stickX: 0.1, stickY: 0.1)
        XCTAssertFalse(manager.isVisible)
        XCTAssertNil(manager.selectedIndex)

        manager.updateSelection(stickX: 0.6, stickY: 0)
        XCTAssertTrue(manager.isVisible)
        XCTAssertNotNil(manager.selectedIndex)

        manager.updateSelection(stickX: 0.1, stickY: 0)
        XCTAssertNil(manager.selectedIndex)
        XCTAssertEqual(manager.forceQuitProgress, 0)
    }

    func testUpdateSelection_SegmentAndPerimeterCallbacksFire() {
        manager.prepare(
            apps: [],
            websites: [
                WebsiteLink(url: "https://one.example", displayName: "One"),
                WebsiteLink(url: "https://two.example", displayName: "Two"),
                WebsiteLink(url: "https://three.example", displayName: "Three"),
                WebsiteLink(url: "https://four.example", displayName: "Four")
            ],
            showWebsitesFirst: true
        )

        var segmentChanges = 0
        var perimeterCrosses = 0
        manager.onSegmentChanged = { segmentChanges += 1 }
        manager.onPerimeterCrossed = { perimeterCrosses += 1 }

        manager.updateSelection(stickX: 0.6, stickY: 0)
        Thread.sleep(forTimeInterval: 0.06)
        manager.updateSelection(stickX: -0.6, stickY: 0)
        Thread.sleep(forTimeInterval: 0.06)
        manager.updateSelection(stickX: 1.0, stickY: 0)
        Thread.sleep(forTimeInterval: 0.06)
        manager.updateSelection(stickX: 0.6, stickY: 0)

        XCTAssertGreaterThanOrEqual(segmentChanges, 2)
        XCTAssertGreaterThanOrEqual(perimeterCrosses, 1)
    }

    func testUpdateSelection_ReachingFullRangeBuildsProgressAndFiresReadyCallback() {
        manager.prepare(
            apps: [],
            websites: [WebsiteLink(url: "https://example.com", displayName: "Example")],
            showWebsitesFirst: true
        )

        var readyFired = 0
        manager.onForceQuitReady = { readyFired += 1 }

        manager.updateSelection(stickX: 1.0, stickY: 0)
        Thread.sleep(forTimeInterval: 1.1)
        manager.updateSelection(stickX: 1.0, stickY: 0)

        XCTAssertGreaterThanOrEqual(manager.forceQuitProgress, 1.0)
        XCTAssertEqual(readyFired, 1)
    }

    func testActivateSelection_UsesLastValidSelectionWithinTolerance() {
        manager.prepare(
            apps: [],
            websites: [WebsiteLink(url: "not a valid url", displayName: "Broken URL")],
            showWebsitesFirst: true
        )

        var activationFlags: [Bool] = []
        manager.onSelectionActivated = { isSecondary in
            activationFlags.append(isSecondary)
        }

        manager.updateSelection(stickX: 0.6, stickY: 0)
        manager.updateSelection(stickX: 0.1, stickY: 0) // clears selectedIndex but keeps lastValidSelection
        manager.activateSelection()

        XCTAssertEqual(activationFlags, [false])
    }

    func testActivateSelection_FullRangeReportsSecondaryAction() {
        manager.prepare(
            apps: [],
            websites: [WebsiteLink(url: "not a valid url", displayName: "Broken URL")],
            showWebsitesFirst: true
        )

        var activationFlags: [Bool] = []
        manager.onSelectionActivated = { isSecondary in
            activationFlags.append(isSecondary)
        }

        manager.updateSelection(stickX: 1.0, stickY: 0)
        manager.activateSelection()

        XCTAssertEqual(activationFlags, [true])
    }

    func testHide_ResetsTransientState() {
        manager.prepare(
            apps: [],
            websites: [WebsiteLink(url: "https://example.com", displayName: "Example")],
            showWebsitesFirst: true
        )
        manager.updateSelection(stickX: 1.0, stickY: 0)

        manager.hide()

        XCTAssertFalse(manager.isVisible)
        XCTAssertNil(manager.selectedIndex)
        XCTAssertFalse(manager.isFullRange)
        XCTAssertEqual(manager.forceQuitProgress, 0)
    }

    private func resetManager() {
        manager.onSegmentChanged = nil
        manager.onPerimeterCrossed = nil
        manager.onForceQuitReady = nil
        manager.onSelectionActivated = nil
        manager.onItemSetChanged = nil
        manager.hide()
        manager.prepare(apps: [], websites: [], showWebsitesFirst: false)
    }
}
