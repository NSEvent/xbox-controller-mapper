import XCTest
@testable import ControllerKeys

/// Pure-logic tests for the Cursor Hints (action feedback) settings: duration
/// clamping, resolution from `UserDefaults` (suite-scoped, so nothing leaks
/// into the real domain), and the quick-tap minimum-display rule.
final class ActionFeedbackDefaultsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ActionFeedbackDefaultsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: Clamping

    func testDefaultDurationIsWithinRange() {
        XCTAssertTrue(ActionFeedbackDefaults.durationRange.contains(ActionFeedbackDefaults.defaultDuration))
    }

    func testClampedDurationPassesThroughMidRangeValues() {
        XCTAssertEqual(ActionFeedbackDefaults.clampedDuration(1.2), 1.2)
        XCTAssertEqual(ActionFeedbackDefaults.clampedDuration(0.5), 0.5)
    }

    func testClampedDurationClampsBelowRange() {
        XCTAssertEqual(ActionFeedbackDefaults.clampedDuration(0), ActionFeedbackDefaults.durationRange.lowerBound)
        XCTAssertEqual(ActionFeedbackDefaults.clampedDuration(-5), ActionFeedbackDefaults.durationRange.lowerBound)
    }

    func testClampedDurationClampsAboveRange() {
        XCTAssertEqual(ActionFeedbackDefaults.clampedDuration(60), ActionFeedbackDefaults.durationRange.upperBound)
    }

    // MARK: Resolution from UserDefaults

    func testResolvedDurationFallsBackToDefaultWhenUnset() {
        XCTAssertEqual(ActionFeedbackDefaults.resolvedDuration(from: defaults), ActionFeedbackDefaults.defaultDuration)
    }

    func testResolvedDurationReadsStoredValue() {
        defaults.set(2.0, forKey: ActionFeedbackDefaults.durationKey)
        XCTAssertEqual(ActionFeedbackDefaults.resolvedDuration(from: defaults), 2.0)
    }

    func testResolvedDurationClampsStoredOutOfRangeValues() {
        defaults.set(99.0, forKey: ActionFeedbackDefaults.durationKey)
        XCTAssertEqual(ActionFeedbackDefaults.resolvedDuration(from: defaults), ActionFeedbackDefaults.durationRange.upperBound)

        defaults.set(-1.0, forKey: ActionFeedbackDefaults.durationKey)
        XCTAssertEqual(ActionFeedbackDefaults.resolvedDuration(from: defaults), ActionFeedbackDefaults.durationRange.lowerBound)
    }

    // MARK: Quick-tap minimum

    func testMinimumDisplayDurationUsesFloorForLongDurations() {
        XCTAssertEqual(ActionFeedbackDefaults.minimumDisplayDuration(for: 2.0), ActionFeedbackDefaults.quickTapFloor)
    }

    func testMinimumDisplayDurationNeverExceedsConfiguredDuration() {
        XCTAssertEqual(ActionFeedbackDefaults.minimumDisplayDuration(for: 0.3), 0.3)
    }
}
