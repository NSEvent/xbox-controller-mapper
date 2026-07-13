import XCTest
@testable import ControllerKeys

/// Pure-logic tests for the first-run permissions wizard. These cover the
/// advance-gating and resume behavior that decide what the user sees, without
/// touching real TCC state (which isn't deterministic in CI).
final class OnboardingFlowTests: XCTestCase {

    // MARK: - Step metadata

    func testRequiredSteps() {
        XCTAssertTrue(OnboardingStep.accessibility.isRequired)
        XCTAssertTrue(OnboardingStep.inputMonitoring.isRequired)
        XCTAssertFalse(OnboardingStep.bluetooth.isRequired, "Bluetooth is optional/skippable")
        XCTAssertFalse(OnboardingStep.welcome.isRequired)
        XCTAssertFalse(OnboardingStep.done.isRequired)
    }

    func testStepOrdering() {
        XCTAssertEqual(OnboardingStep.welcome.next, .accessibility)
        XCTAssertEqual(OnboardingStep.accessibility.next, .inputMonitoring)
        XCTAssertEqual(OnboardingStep.inputMonitoring.next, .bluetooth)
        XCTAssertEqual(OnboardingStep.bluetooth.next, .done)
        XCTAssertNil(OnboardingStep.done.next)

        XCTAssertNil(OnboardingStep.welcome.previous)
        XCTAssertEqual(OnboardingStep.accessibility.previous, .welcome)
        XCTAssertEqual(OnboardingStep.done.previous, .bluetooth)
    }

    func testPermissionStepsExcludeWelcomeAndDone() {
        XCTAssertEqual(OnboardingStep.permissionSteps, [.accessibility, .inputMonitoring, .bluetooth])
    }

    // MARK: - canAdvance gating

    func testRequiredStepBlocksAdvanceUntilGranted() {
        let notGranted = OnboardingStepState(accessibility: .notDetermined, inputMonitoring: .notDetermined, bluetooth: .notDetermined)
        XCTAssertFalse(notGranted.canAdvance(from: .accessibility))
        XCTAssertFalse(notGranted.canAdvance(from: .inputMonitoring))

        let denied = OnboardingStepState(accessibility: .denied, inputMonitoring: .denied, bluetooth: .denied)
        XCTAssertFalse(denied.canAdvance(from: .accessibility), "denied should still block the primary CTA")
        XCTAssertFalse(denied.canAdvance(from: .inputMonitoring))
    }

    func testRequiredStepAllowsAdvanceWhenGranted() {
        let granted = OnboardingStepState(accessibility: .granted, inputMonitoring: .granted, bluetooth: .notDetermined)
        XCTAssertTrue(granted.canAdvance(from: .accessibility))
        XCTAssertTrue(granted.canAdvance(from: .inputMonitoring))
    }

    func testOptionalAndNonPermissionStepsAlwaysAdvance() {
        let nothing = OnboardingStepState(accessibility: .notDetermined, inputMonitoring: .notDetermined, bluetooth: .notDetermined)
        XCTAssertTrue(nothing.canAdvance(from: .welcome))
        XCTAssertTrue(nothing.canAdvance(from: .bluetooth), "Bluetooth is skippable regardless of grant")
        XCTAssertTrue(nothing.canAdvance(from: .done))
    }

    // MARK: - firstIncompleteStep (resume position)

    func testFirstIncompleteStepWalksRequiredPermissionsInOrder() {
        XCTAssertEqual(
            OnboardingStepState(accessibility: .notDetermined, inputMonitoring: .notDetermined, bluetooth: .notDetermined).firstIncompleteStep,
            .accessibility
        )
        XCTAssertEqual(
            OnboardingStepState(accessibility: .granted, inputMonitoring: .notDetermined, bluetooth: .notDetermined).firstIncompleteStep,
            .inputMonitoring
        )
    }

    func testFirstIncompleteStepIgnoresOptionalBluetooth() {
        // Both required permissions granted, Bluetooth skipped → wizard can jump
        // straight to the summary rather than re-walking the user.
        let state = OnboardingStepState(accessibility: .granted, inputMonitoring: .granted, bluetooth: .notDetermined)
        XCTAssertEqual(state.firstIncompleteStep, .done)
    }

    // MARK: - state(for:)

    func testStateForStepMapsToTheRightPermission() {
        let state = OnboardingStepState(accessibility: .granted, inputMonitoring: .denied, bluetooth: .notDetermined)
        XCTAssertEqual(state.state(for: .accessibility), .granted)
        XCTAssertEqual(state.state(for: .inputMonitoring), .denied)
        XCTAssertEqual(state.state(for: .bluetooth), .notDetermined)
        XCTAssertNil(state.state(for: .welcome))
        XCTAssertNil(state.state(for: .done))
    }
}
