import XCTest
@testable import ControllerKeys

final class ConfigurationOverviewIntroductionPolicyTests: XCTestCase {
	func testIntroducesOnlyAfterFirstRunSheetsFinish() {
		XCTAssertTrue(shouldIntroduce())
		XCTAssertFalse(shouldIntroduce(hasCompletedOnboarding: false))
		XCTAssertFalse(shouldIntroduce(hasSeenControllerIntro: false))
		XCTAssertFalse(shouldIntroduce(hasShownTrialWelcome: false))
		XCTAssertFalse(shouldIntroduce(isShowingOnboarding: true))
		XCTAssertFalse(shouldIntroduce(isShowingWelcome: true))
		XCTAssertFalse(shouldIntroduce(hasOtherBlockingPresentation: true))
	}

	func testNeverMutatesOneShotStateDuringTestsScreenshotsOrLaterLaunches() {
		XCTAssertFalse(shouldIntroduce(isRunningTests: true))
		XCTAssertFalse(shouldIntroduce(isScreenshotCapture: true))
		XCTAssertFalse(shouldIntroduce(hasSeenOverview: true))
	}

	private func shouldIntroduce(
		isRunningTests: Bool = false,
		isScreenshotCapture: Bool = false,
		hasSeenOverview: Bool = false,
		hasCompletedOnboarding: Bool = true,
		hasSeenControllerIntro: Bool = true,
		hasShownTrialWelcome: Bool = true,
		isShowingOnboarding: Bool = false,
		isShowingWelcome: Bool = false,
		hasOtherBlockingPresentation: Bool = false
	) -> Bool {
		ConfigurationOverviewIntroductionPolicy.shouldIntroduce(
			isRunningTests: isRunningTests,
			isScreenshotCapture: isScreenshotCapture,
			hasSeenOverview: hasSeenOverview,
			hasCompletedOnboarding: hasCompletedOnboarding,
			hasSeenControllerIntro: hasSeenControllerIntro,
			hasShownTrialWelcome: hasShownTrialWelcome,
			isShowingOnboarding: isShowingOnboarding,
			isShowingWelcome: isShowingWelcome,
			hasOtherBlockingPresentation: hasOtherBlockingPresentation
		)
	}
}
