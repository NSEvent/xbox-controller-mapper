import XCTest
@testable import ControllerKeys

/// Pure-logic tests for the one-time review-request state machine. The date
/// source and the `UserDefaults` store are injected so the trigger / defer /
/// complete transitions are exercised deterministically without touching the
/// wall clock or the app's real defaults.
@MainActor
final class ReviewRequestManagerTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    /// Movable "now" — tests advance this to simulate elapsed days.
    private var clock = Date(timeIntervalSinceReferenceDate: 1_000_000)

    override func setUp() {
        super.setUp()
        suiteName = "ReviewRequestManagerTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        clock = Date(timeIntervalSinceReferenceDate: 1_000_000)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeManager(disabled: Bool = false) -> ReviewRequestManager {
        ReviewRequestManager(defaults: defaults, now: { [unowned self] in clock }, isDisabled: disabled)
    }

    private func advance(days: Double) {
        clock = clock.addingTimeInterval(days * 86_400)
    }

    // MARK: - The 7-day gate

    func testNoPromptOnFirstLicensedLaunch() {
        let manager = makeManager()
        XCTAssertFalse(manager.evaluateForLicensedLaunch(), "The clock only just started — nothing to ask yet")
    }

    func testNoPromptBeforeSevenLicensedDays() {
        let manager = makeManager()
        manager.recordLicensedSightingIfNeeded()
        advance(days: 6)
        XCTAssertFalse(manager.shouldRequestReview())
    }

    func testPromptAfterSevenLicensedDays() {
        let manager = makeManager()
        manager.recordLicensedSightingIfNeeded()
        advance(days: 7)
        XCTAssertTrue(manager.shouldRequestReview())
    }

    func testFirstSightingIsRecordedOnceAndNotPushedForward() {
        let manager = makeManager()
        manager.recordLicensedSightingIfNeeded()   // anchors the clock at day 0
        advance(days: 3)
        manager.recordLicensedSightingIfNeeded()   // must NOT re-anchor to day 3
        advance(days: 4)                            // now day 7 relative to the first sighting
        XCTAssertTrue(manager.shouldRequestReview(), "The 7-day clock stays anchored to the earliest licensed sighting")
    }

    // MARK: - Not Now → defer → re-ask → stop

    func testNotNowDefersThirtyDays() {
        let manager = makeManager()
        manager.recordLicensedSightingIfNeeded()
        advance(days: 7)
        XCTAssertTrue(manager.shouldRequestReview())

        manager.markShown()
        manager.apply(.notNow)

        // Deferred: not due the next day, nor 29 days later.
        advance(days: 1)
        XCTAssertFalse(manager.shouldRequestReview())
        advance(days: 28)   // day 36 total, 29 days since the defer
        XCTAssertFalse(manager.shouldRequestReview())

        // Due again once the 30-day defer elapses.
        advance(days: 2)    // day 38 total, 31 days since the defer
        XCTAssertTrue(manager.shouldRequestReview())
    }

    func testSecondNotNowStopsForever() {
        let manager = makeManager()
        manager.recordLicensedSightingIfNeeded()
        advance(days: 7)

        // First prompt → Not Now → defer.
        manager.markShown()
        manager.apply(.notNow)

        // Re-ask after the defer window → Not Now again → done for good.
        advance(days: 31)
        XCTAssertTrue(manager.shouldRequestReview())
        manager.markShown()
        manager.apply(.notNow)

        advance(days: 365)
        XCTAssertFalse(manager.shouldRequestReview(), "A second Not Now ends the sequence permanently")
    }

    func testNeverExceedsMaxPrompts() {
        let manager = makeManager()
        manager.recordLicensedSightingIfNeeded()
        advance(days: 7)
        manager.markShown()
        manager.apply(.notNow)
        advance(days: 31)
        manager.markShown()   // second show
        // Two shows have now happened; even without applying an outcome the
        // prompt must not be due a third time.
        advance(days: 31)
        XCTAssertFalse(manager.shouldRequestReview())
    }

    // MARK: - Terminal outcomes

    func testLeaveReviewCompletesForever() {
        let manager = makeManager()
        manager.recordLicensedSightingIfNeeded()
        advance(days: 7)
        manager.markShown()
        manager.apply(.leaveReview)

        advance(days: 365)
        XCTAssertFalse(manager.shouldRequestReview())
    }

    func testDontAskAgainCompletesForever() {
        let manager = makeManager()
        manager.recordLicensedSightingIfNeeded()
        advance(days: 7)
        manager.markShown()
        manager.apply(.dontAskAgain)

        advance(days: 365)
        XCTAssertFalse(manager.shouldRequestReview())
    }

    func testCompletedStateStopsRecordingNewSightings() {
        let manager = makeManager()
        manager.recordLicensedSightingIfNeeded()
        advance(days: 7)
        manager.markShown()
        manager.apply(.dontAskAgain)
        // A later evaluation must stay inert, not restart the clock.
        advance(days: 400)
        XCTAssertFalse(manager.evaluateForLicensedLaunch())
    }

    // MARK: - Persistence across instances

    func testStatePersistsAcrossManagerInstances() {
        let first = makeManager()
        first.recordLicensedSightingIfNeeded()
        advance(days: 7)

        // A fresh manager over the same defaults sees the same sighting.
        let second = makeManager()
        XCTAssertTrue(second.shouldRequestReview())
        second.markShown()
        second.apply(.notNow)

        let third = makeManager()
        advance(days: 1)
        XCTAssertFalse(third.shouldRequestReview(), "The 30-day defer survives a new manager instance")
    }

    // MARK: - Disabled (tests / screenshot) guard

    func testDisabledManagerNeverPromptsOrRecords() {
        let manager = makeManager(disabled: true)
        manager.recordLicensedSightingIfNeeded()
        advance(days: 365)
        XCTAssertFalse(manager.evaluateForLicensedLaunch())
        XCTAssertFalse(manager.shouldRequestReview())
        // Nothing should have been written to the store.
        XCTAssertNil(defaults.object(forKey: ReviewRequestManager.Keys.firstLicensedSeen))
    }
}
