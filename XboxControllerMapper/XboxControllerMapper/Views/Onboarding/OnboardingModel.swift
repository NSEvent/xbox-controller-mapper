import Foundation

extension Notification.Name {
    /// Posted (e.g. from Settings ▸ Permissions) to re-present the onboarding
    /// wizard so the user can re-walk a permission that stopped working.
    static let reopenPermissionsOnboarding = Notification.Name("reopenPermissionsOnboarding")
}

/// The ordered steps of the first-run permissions wizard.
///
/// Accessibility and Input Monitoring are *required* for the app to do anything
/// useful and are requested first. Bluetooth is *optional* (wireless battery %)
/// and is skippable. Local Network is deliberately **absent** — it's requested
/// lazily when the user sets up the cross-Mac relay via the sync button, so a
/// user who never touches that feature never sees the prompt.
enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case accessibility
    case inputMonitoring
    case bluetooth
    case done

    var id: Int { rawValue }

    /// Steps that gate the primary "Continue" button on an actual grant.
    var isRequired: Bool {
        switch self {
        case .accessibility, .inputMonitoring: return true
        case .welcome, .bluetooth, .done: return false
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
    static var permissionSteps: [OnboardingStep] { [.accessibility, .inputMonitoring, .bluetooth] }
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
        case .inputMonitoring: return inputMonitoring == .granted
        case .welcome, .bluetooth, .done: return true
        }
    }

    func state(for step: OnboardingStep) -> PermissionState? {
        switch step {
        case .accessibility: return accessibility
        case .inputMonitoring: return inputMonitoring
        case .bluetooth: return bluetooth
        case .welcome, .done: return nil
        }
    }

    /// First step the user still has to act on, scanning from the top. Returns
    /// `.done` when every required permission is granted — used to resume the
    /// wizard at the right place rather than always starting at `.welcome`.
    var firstIncompleteStep: OnboardingStep {
        if accessibility != .granted { return .accessibility }
        if inputMonitoring != .granted { return .inputMonitoring }
        return .done
    }
}
