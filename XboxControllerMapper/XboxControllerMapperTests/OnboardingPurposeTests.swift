import XCTest
@testable import ControllerKeys

final class OnboardingPurposeTests: XCTestCase {
	func testConnectedControllerCannotDispatchMappingsDuringPurposeOrPermissions() {
		let firstStep = OnboardingEntryPolicy.initialStep(requested: .welcome, isFirstRun: true, permissionsReady: true)
		XCTAssertTrue(OnboardingInputPreviewPolicy.shouldMute(step: firstStep))
		for step in [OnboardingStep.inputMonitoring, .accessibility, .bluetooth] {
			XCTAssertTrue(OnboardingInputPreviewPolicy.shouldMute(step: step))
		}
		XCTAssertFalse(OnboardingInputPreviewPolicy.shouldMute(step: .controllerTest), "The controller test owns its preview gate")
		XCTAssertFalse(OnboardingInputPreviewPolicy.shouldMute(step: .done), "A guided real-action test must be able to resume output")
	}

	func testFreshRunStillOffersPurposeWithExistingPermissions() {
		XCTAssertEqual(OnboardingEntryPolicy.initialStep(requested: .welcome, isFirstRun: true, permissionsReady: true), .welcome)
		XCTAssertEqual(OnboardingEntryPolicy.initialStep(requested: .welcome, isFirstRun: false, permissionsReady: true), .controllerTest)
		XCTAssertEqual(OnboardingEntryPolicy.initialStep(requested: .accessibility, isFirstRun: true, permissionsReady: true), .accessibility)
		XCTAssertEqual(OnboardingEntryPolicy.initialStep(requested: .controllerTest, isFirstRun: true, permissionsReady: false), .controllerTest)
	}

	func testPurposeSurvivesInterruptedSetupAndSkipClearsOnlyPurpose() throws {
		let suite = "ControllerKeys.PurposeTest.\(UUID().uuidString)"
		let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
		defer { defaults.removePersistentDomain(forName: suite) }
		defaults.set("keep existing mappings", forKey: "profiles")
		XCTAssertNil(OnboardingPurposePreference.load(from: defaults))
		OnboardingPurposePreference.save(.photoVideo, to: defaults)
		XCTAssertEqual(OnboardingPurposePreference.load(from: try XCTUnwrap(UserDefaults(suiteName: suite))), .photoVideo)
		OnboardingPurposePreference.save(nil, to: defaults)
		XCTAssertNil(OnboardingPurposePreference.load(from: defaults))
		XCTAssertEqual(defaults.string(forKey: "profiles"), "keep existing mappings")
		defaults.set("future-value", forKey: OnboardingPurposePreference.key)
		XCTAssertNil(OnboardingPurposePreference.load(from: defaults))
	}

	func testSpecificCreativeIntentsRemainDistinctAndLegacyValuesStillDecode() throws {
		for raw in ["creative_tools", "accessibility", "couch_control", "presentations"] {
			XCTAssertNotNil(TelemetryService.ProductUseCase(rawValue: raw))
		}
		let choices = TelemetryService.ProductUseCase.startingChoices
		XCTAssertEqual(Set(choices.map(\.rawValue)).count, 7)
		XCTAssertTrue(choices.contains(.photoVideo))
		XCTAssertTrue(choices.contains(.music))
		XCTAssertTrue(choices.contains(.coding))
		XCTAssertTrue(choices.contains(.macControl))
		XCTAssertFalse(choices.contains(.creativeTools))
		for choice in choices {
			XCTAssertEqual(try JSONDecoder().decode(TelemetryService.ProductUseCase.self, from: JSONEncoder().encode(choice)), choice)
		}
	}

	func testRecommendationsOfferTaskSpecificSetupWithoutInventingGameBindings() {
		XCTAssertEqual(TelemetryService.ProductUseCase.study.setupSuggestions.first, .guided(.anki))
		XCTAssertEqual(TelemetryService.ProductUseCase.photoVideo.setupSuggestions, [.guided(.photoCulling), .guided(.finalCut), .profiles])
		XCTAssertEqual(TelemetryService.ProductUseCase.macControl.setupSuggestions.first, .guided(.oneHand))
		for purpose in [TelemetryService.ProductUseCase.gaming, .music, .coding, .other] {
			XCTAssertEqual(purpose.setupSuggestions, [.profiles])
		}
	}

	func testNavigationSkipsGrantedPermissionsButStillShowsControllerTest() {
		let granted = OnboardingStepState(accessibility: .granted, inputMonitoring: .granted, bluetooth: .granted)
		XCTAssertEqual(granted.nextStep(after: .welcome), .controllerTest)
		let partial = OnboardingStepState(accessibility: .denied, inputMonitoring: .granted, bluetooth: .notDetermined)
		XCTAssertEqual(partial.nextStep(after: .welcome), .accessibility)
		XCTAssertEqual(partial.nextStep(after: .accessibility), .bluetooth)
		XCTAssertNil(partial.nextStep(after: .done))
	}
}
