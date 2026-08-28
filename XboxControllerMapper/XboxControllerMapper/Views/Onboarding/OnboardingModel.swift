import Foundation

extension Notification.Name {
    /// Posted (e.g. from Settings ▸ Permissions) to re-present the onboarding
    /// wizard so the user can re-walk a permission that stopped working.
    static let reopenPermissionsOnboarding = Notification.Name("reopenPermissionsOnboarding")
}

/// The ordered steps of the first-run permissions wizard.
///
/// Accessibility is *required* for the app to do anything useful. Input
/// Monitoring is *optional for most controllers* — plain `GCController` pads
/// (Xbox, PlayStation, Switch) work without it; only Steam controllers, generic
/// HID gamepads, the Apple TV remote, and the Xbox guide button need it — so it
/// no longer gates Continue, sparing the majority a second System Settings
/// round-trip. It still intentionally comes before Accessibility for users who
/// do grant it: once Accessibility is granted, macOS can report listen access
/// as granted without having separately registered the app in the Input
/// Monitoring list. Bluetooth is *optional* (wireless battery %) and is
/// skippable. Local Network is deliberately **absent** — it's requested lazily
/// when the user sets up the cross-Mac relay via the sync button, so a user who
/// never touches that feature never sees the prompt.
enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case inputMonitoring
    case accessibility
    case bluetooth
    case controllerTest
    case done

    var id: Int { rawValue }

    /// Steps that gate the primary "Continue" button on an actual grant.
    var isRequired: Bool {
        switch self {
        case .accessibility: return true
        case .welcome, .inputMonitoring, .bluetooth, .controllerTest, .done: return false
        }
    }

    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

    var previous: OnboardingStep? {
        guard rawValue > 0 else { return nil }
        return OnboardingStep(rawValue: rawValue - 1)
    }

    /// Index (1-based) and total of the *permission* steps, for the "Step 2 of 3"
    /// progress label. Welcome and Done aren't counted.
    static var permissionSteps: [OnboardingStep] { [.inputMonitoring, .accessibility, .bluetooth] }
}

/// Pure snapshot of the permission states the wizard reacts to. Kept free of any
/// UI / singleton dependency so the advance/gating logic is unit-testable.
struct OnboardingStepState: Equatable {
    var accessibility: PermissionState
    var inputMonitoring: PermissionState
    var bluetooth: PermissionState

    /// Whether the primary "Continue" CTA is enabled for `step`. Required steps
    /// gate on a grant; optional/non-permission steps are always advanceable.
    /// (A separate, always-available "Skip for now" link can bypass this so a
    /// user on a managed Mac is never trapped.)
    func canAdvance(from step: OnboardingStep) -> Bool {
        switch step {
        case .accessibility: return accessibility == .granted
        // Optional: GCController pads work without it (see OnboardingStep docs).
        case .welcome, .inputMonitoring, .bluetooth, .controllerTest, .done: return true
        }
    }

    func state(for step: OnboardingStep) -> PermissionState? {
        switch step {
        case .accessibility: return accessibility
        case .inputMonitoring: return inputMonitoring
        case .bluetooth: return bluetooth
        case .welcome, .controllerTest, .done: return nil
        }
    }

    /// First permission step the user hasn't granted, scanning in wizard order.
    /// Used to resume a re-walk (Settings ▸ "Set Up Permissions…") at the right
    /// place rather than always starting at `.welcome`. Input Monitoring is
    /// optional, but a user re-walking the wizard is usually here to fix a
    /// missing grant — so it still counts as a resume target.
    var firstIncompleteStep: OnboardingStep {
        if inputMonitoring != .granted { return .inputMonitoring }
	if accessibility != .granted { return .accessibility }
        return .done
    }
}
