import Foundation

enum ConfigurationOverviewIntroductionPolicy {
	static func shouldIntroduce(
		isRunningTests: Bool,
		isScreenshotCapture: Bool,
		hasSeenOverview: Bool,
		hasCompletedOnboarding: Bool,
		hasSeenControllerIntro: Bool,
		hasShownTrialWelcome: Bool,
		isShowingOnboarding: Bool,
		isShowingWelcome: Bool,
		hasOtherBlockingPresentation: Bool
	) -> Bool {
		!isRunningTests
			&& !isScreenshotCapture
			&& !hasSeenOverview
			&& hasCompletedOnboarding
			&& hasSeenControllerIntro
			&& hasShownTrialWelcome
			&& !isShowingOnboarding
			&& !isShowingWelcome
			&& !hasOtherBlockingPresentation
	}
}
