import XCTest
@testable import ControllerKeys

/// Pure-logic tests for the first-run permissions wizard. These cover the
/// advance-gating and resume behavior that decide what the user sees, without
/// touching real TCC state (which isn't deterministic in CI).
final class OnboardingFlowTests: XCTestCase {

    // MARK: - Step metadata

    func testRequiredSteps() {
        XCTAssertTrue(OnboardingStep.accessibility.isRequired)
        XCTAssertFalse(
            OnboardingStep.inputMonitoring.isRequired,
            "Input Monitoring is optional — GCController pads (Xbox/PS/Switch) work without it, so it must not force a second System Settings trip"
        )
        XCTAssertFalse(OnboardingStep.bluetooth.isRequired, "Bluetooth is optional/skippable")
        XCTAssertFalse(OnboardingStep.controllerTest.isRequired, "The interactive controller test is skippable")
        XCTAssertFalse(OnboardingStep.welcome.isRequired)
        XCTAssertFalse(OnboardingStep.done.isRequired)
    }

    func testStepOrdering() {
	XCTAssertEqual(OnboardingStep.welcome.next, .inputMonitoring)
	XCTAssertEqual(OnboardingStep.inputMonitoring.next, .accessibility)
	XCTAssertEqual(OnboardingStep.accessibility.next, .bluetooth)
        // The interactive controller test sits between Bluetooth and the summary.
        XCTAssertEqual(OnboardingStep.bluetooth.next, .controllerTest)
        XCTAssertEqual(OnboardingStep.controllerTest.next, .done)
        XCTAssertNil(OnboardingStep.done.next)

        XCTAssertNil(OnboardingStep.welcome.previous)
	XCTAssertEqual(OnboardingStep.inputMonitoring.previous, .welcome)
	XCTAssertEqual(OnboardingStep.accessibility.previous, .inputMonitoring)
        XCTAssertEqual(OnboardingStep.controllerTest.previous, .bluetooth)
        XCTAssertEqual(OnboardingStep.done.previous, .controllerTest)
    }

    func testPermissionStepsExcludeWelcomeAndDone() {
	XCTAssertEqual(OnboardingStep.permissionSteps, [.inputMonitoring, .accessibility, .bluetooth])
    }

    func testInputMonitoringComesBeforeAccessibility() {
	// Accessibility can make macOS report listen access as granted without
	// separately registering the app in Input Monitoring. Ask for Input
	// Monitoring first so first-run onboarding can add the app to that list.
	XCTAssertEqual(OnboardingStep.welcome.next, .inputMonitoring)
	XCTAssertLessThan(
	    OnboardingStep.permissionSteps.firstIndex(of: .inputMonitoring)!,
	    OnboardingStep.permissionSteps.firstIndex(of: .accessibility)!
	)
    }

    // MARK: - canAdvance gating

    func testRequiredStepBlocksAdvanceUntilGranted() {
        let notGranted = OnboardingStepState(accessibility: .notDetermined, inputMonitoring: .notDetermined, bluetooth: .notDetermined)
        XCTAssertFalse(notGranted.canAdvance(from: .accessibility))

        let denied = OnboardingStepState(accessibility: .denied, inputMonitoring: .denied, bluetooth: .denied)
        XCTAssertFalse(denied.canAdvance(from: .accessibility), "denied should still block the primary CTA")
    }

    func testRequiredStepAllowsAdvanceWhenGranted() {
        let granted = OnboardingStepState(accessibility: .granted, inputMonitoring: .granted, bluetooth: .notDetermined)
        XCTAssertTrue(granted.canAdvance(from: .accessibility))
    }

    func testOptionalAndNonPermissionStepsAlwaysAdvance() {
        let nothing = OnboardingStepState(accessibility: .notDetermined, inputMonitoring: .notDetermined, bluetooth: .notDetermined)
        XCTAssertTrue(nothing.canAdvance(from: .welcome))
        XCTAssertTrue(
            nothing.canAdvance(from: .inputMonitoring),
            "Input Monitoring never gates Continue — most controllers don't need it"
        )
        XCTAssertTrue(nothing.canAdvance(from: .bluetooth), "Bluetooth is skippable regardless of grant")
        XCTAssertTrue(nothing.canAdvance(from: .controllerTest), "The controller test never gates advancement")
        XCTAssertTrue(nothing.canAdvance(from: .done))
    }

    // MARK: - firstIncompleteStep (resume position)

    // Input Monitoring is optional but still a resume target: a user re-walking
    // the wizard from Settings is usually there to fix a missing grant.
    func testFirstIncompleteStepWalksRequiredPermissionsInOrder() {
        XCTAssertEqual(
            OnboardingStepState(accessibility: .notDetermined, inputMonitoring: .notDetermined, bluetooth: .notDetermined).firstIncompleteStep,
	    .inputMonitoring
        )
        XCTAssertEqual(
            OnboardingStepState(accessibility: .granted, inputMonitoring: .notDetermined, bluetooth: .notDetermined).firstIncompleteStep,
            .inputMonitoring
        )
	XCTAssertEqual(
	    OnboardingStepState(accessibility: .notDetermined, inputMonitoring: .granted, bluetooth: .notDetermined).firstIncompleteStep,
	    .accessibility
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
        XCTAssertNil(state.state(for: .controllerTest))
        XCTAssertNil(state.state(for: .done))
    }
}
