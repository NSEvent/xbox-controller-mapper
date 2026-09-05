import SwiftUI

/// Readiness is separate from closing the wizard: setup may be deferred.
enum OnboardingReadiness: Equatable {
	case accessibilityMissing, controllerMissing, ready

	init(accessibilityGranted: Bool, controllerConnected: Bool) {
		self = !accessibilityGranted ? .accessibilityMissing :
			(controllerConnected ? .ready : .controllerMissing)
	}

	var repairStep: OnboardingStep? {
		switch self {
		case .accessibilityMissing: return .accessibility
		case .controllerMissing: return .controllerTest
		case .ready: return nil
		}
	}

	var title: String {
		switch self {
		case .accessibilityMissing: return String(localized: "Allow control of your Mac")
		case .controllerMissing: return String(localized: "Connect your controller")
		case .ready: return String(localized: "Ready to try your mappings")
		}
	}

	var explanation: String {
		switch self {
		case .accessibilityMissing:
			return String(localized: "Accessibility is still off. Enable it so your controller can move the mouse and press keys.")
		case .controllerMissing:
			return String(localized: "No controller is connected yet. Pair one over Bluetooth or connect a supported controller with a USB cable.")
		case .ready:
			return String(localized: "Your controller is connected and Accessibility is enabled. Start with the existing mappings, or change a button to suit your workflow.")
		}
	}

	var buttonTitle: String {
		switch self {
		case .accessibilityMissing: return String(localized: "Enable Accessibility")
		case .controllerMissing: return String(localized: "Connect a Controller")
		case .ready: return String(localized: "Start Using ControllerKeys")
		}
	}
}

struct OnboardingCompletionView: View {
	let readiness: OnboardingReadiness
	let permissions: OnboardingStepState

	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			Label {
				Text(readiness.explanation)
			} icon: {
				Image(systemName: readiness == .ready ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
					.foregroundStyle(readiness == .ready ? Color.green : Color.orange)
			}
				.font(.callout)
				.fixedSize(horizontal: false, vertical: true)

			summaryRow("Accessibility", state: permissions.accessibility)
			summaryRow("Input Monitoring", state: permissions.inputMonitoring, optional: true)
			summaryRow("Bluetooth battery readouts", state: permissions.bluetooth, optional: true)

			Text("You can revisit permissions from **Settings › Permissions**.")
				.font(.caption)
				.foregroundStyle(.secondary)
		}
	}

	private func summaryRow(_ title: LocalizedStringKey, state: PermissionState, optional: Bool = false) -> some View {
		HStack(spacing: 8) {
			Image(systemName: state == .granted ? "checkmark.circle.fill" : (optional ? "minus.circle" : "exclamationmark.triangle.fill"))
				.foregroundStyle(state == .granted ? .green : (optional ? .secondary : .orange))
			Text(title)
			Spacer()
			Text(state == .granted ? String(localized: "Granted") : (optional ? String(localized: "Optional") : String(localized: "Not granted")))
				.font(.caption)
				.foregroundStyle(.secondary)
		}
		.font(.callout)
	}
}
