import SwiftUI

// MARK: - Ring Settings View

struct RingSettingsView: View {
	@EnvironmentObject var profileManager: ProfileManager
	@EnvironmentObject var ouraRingInputService: OuraRingInputService

	private var settings: JoystickSettings {
		profileManager.activeProfile?.joystickSettings ?? .default
	}

	private var ringSettings: OuraMotionSettings {
		settings.ouraMotion
	}

	var body: some View {
		Form {
			connectionSection

			if ringSettings.enabled {
				routingSection
				calibrationSection
				advancedSection
			}
		}
		.formStyle(.grouped)
		.padding()
	}

	private var connectionSection: some View {
		Section("Connection") {
			RingStatusHeader(
				status: ouraRingInputService.status,
				enabled: ringSettings.enabled,
				motionOutputEnabled: ringSettings.motionOutputEnabled
			)

			Toggle("Enable Oura Ring", isOn: Binding(
				get: { ringSettings.enabled },
				set: { enabled in
					updateOuraMotion { $0.enabled = enabled }
				}
			))

			RingActionButtons(
				enabled: ringSettings.enabled,
				motionOutputEnabled: ringSettings.motionOutputEnabled,
				onScan: { ouraRingInputService.startIfEnabled() },
				onForgetPairing: { ouraRingInputService.forgetRingKeyAndReconnect() },
				onCenter: { ouraRingInputService.resetMotionCenter() },
				onToggleMotion: { ouraRingInputService.toggleMotionOutputEnabled() }
			)
		}
	}

	private var routingSection: some View {
		Section("Motion Routing") {
			Picker("Motion Output", selection: Binding(
				get: { settings.ouraMotionOutputMode },
				set: { output in
					updateSettings { $0.setOuraMotionOutputMode(output) }
				}
			)) {
				ForEach(OuraMotionOutputMode.allCases) { output in
					Label(output.displayName, systemImage: output.systemImageName)
						.tag(output)
				}
			}
			.pickerStyle(.segmented)
			Text(settings.ouraMotionOutputMode.detailText)
				.font(.caption)
				.foregroundStyle(.secondary)

			Picker("Orientation", selection: Binding(
				get: { ringSettings.orientation },
				set: { orientation in
					updateOuraMotion { $0.orientation = orientation }
				}
			)) {
				ForEach(OuraMotionOrientation.allCases) { orientation in
					Text(orientation.displayName).tag(orientation)
				}
			}
			.pickerStyle(.segmented)

			Toggle("Invert X Axis", isOn: Binding(
				get: { ringSettings.invertX },
				set: { value in updateOuraMotion { $0.invertX = value } }
			))

			Toggle("Invert Y Axis", isOn: Binding(
				get: { ringSettings.invertY },
				set: { value in updateOuraMotion { $0.invertY = value } }
			))
		}
	}

	private var calibrationSection: some View {
		Section("Calibration") {
			SliderRow(
				label: "Sensitivity",
				value: Binding(
					get: { ringSettings.sensitivity },
					set: { value in updateOuraMotion { $0.sensitivity = value } }
				),
				range: 0...1,
				description: "Motion strength before it reaches the selected stick"
			)

			SliderRow(
				label: "Horizontal Boost",
				value: Binding(
					get: { ringSettings.horizontalBoost },
					set: { value in updateOuraMotion { $0.horizontalBoost = value } }
				),
				range: 1...4,
				description: "Extra ring-twist strength for wide screens"
			)

			SliderRow(
				label: "Left Boost",
				value: Binding(
					get: { ringSettings.leftTiltBoost },
					set: { value in updateOuraMotion { $0.leftTiltBoost = value } }
				),
				range: 1...4,
				description: "Extra strength for smaller left-hand travel"
			)

			SliderRow(
				label: "Deadzone",
				value: Binding(
					get: { ringSettings.deadzone },
					set: { value in updateOuraMotion { $0.deadzone = value } }
				),
				range: 0...0.5,
				description: "Ignore small hand drift"
			)

			SliderRow(
				label: "Smoothing",
				value: Binding(
					get: { ringSettings.smoothing },
					set: { value in updateOuraMotion { $0.smoothing = value } }
				),
				range: 0...1,
				description: "Higher values make motion steadier"
			)
		}
	}

	private var advancedSection: some View {
		Section("Advanced") {
			Toggle("Adopt Reset Ring", isOn: Binding(
				get: { ringSettings.adoptResetRing },
				set: { value in updateOuraMotion { $0.adoptResetRing = value } }
			))

			Toggle("Diagnostic Logging", isOn: Binding(
				get: { ringSettings.diagnosticsEnabled },
				set: { value in updateOuraMotion { $0.diagnosticsEnabled = value } }
			))

			if ringSettings.diagnosticsEnabled, !ouraRingInputService.lastDiagnosticLine.isEmpty {
				Text(ouraRingInputService.lastDiagnosticLine)
					.font(.caption2.monospaced())
					.foregroundStyle(.secondary)
					.lineLimit(2)
					.textSelection(.enabled)
			}
		}
	}

	private func updateOuraMotion(_ mutate: (inout OuraMotionSettings) -> Void) {
		updateSettings { settings in
			mutate(&settings.ouraMotion)
		}
	}

	private func updateSettings(_ mutate: (inout JoystickSettings) -> Void) {
		var newSettings = settings
		mutate(&newSettings)
		profileManager.updateJoystickSettings(newSettings)
	}
}

private struct RingStatusHeader: View {
	let status: OuraRingConnectionStatus
	let enabled: Bool
	let motionOutputEnabled: Bool

	var body: some View {
		HStack(alignment: .center, spacing: 12) {
			Image(systemName: status.systemImage)
				.font(.system(size: 22, weight: .semibold))
				.foregroundStyle(status.tint)
				.frame(width: 32)

			VStack(alignment: .leading, spacing: 3) {
				Text("Oura Ring")
					.font(.headline)

				Text(enabled ? status.displayName : "Off for this profile")
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(2)
			}

			Spacer(minLength: 12)

			if enabled {
				RingStatusPill(
					text: motionOutputEnabled ? "Motion On" : "Motion Paused",
					systemImage: motionOutputEnabled ? "cursorarrow.motionlines" : "pause.circle",
					tint: motionOutputEnabled ? .green : .orange
				)
			}
		}
		.padding(.vertical, 4)
	}
}

private struct RingActionButtons: View {
	let enabled: Bool
	let motionOutputEnabled: Bool
	let onScan: () -> Void
	let onForgetPairing: () -> Void
	let onCenter: () -> Void
	let onToggleMotion: () -> Void

	var body: some View {
		ViewThatFits(in: .horizontal) {
			HStack(spacing: 8) {
				buttons
			}

			VStack(alignment: .leading, spacing: 8) {
				buttons
			}
		}
		.controlSize(.small)
		.disabled(!enabled)
	}

	private var buttons: some View {
		Group {
			Button(action: onScan) {
				Label("Scan", systemImage: "dot.radiowaves.left.and.right")
			}

			Button(action: onCenter) {
				Label("Center", systemImage: "scope")
			}

			Button(action: onToggleMotion) {
				Label(
					motionOutputEnabled ? "Pause Motion" : "Resume Motion",
					systemImage: motionOutputEnabled ? "pause.circle" : "play.circle"
				)
			}

			Button(role: .destructive, action: onForgetPairing) {
				Label("Forget Pairing", systemImage: "key.slash")
			}
		}
	}
}

private struct RingStatusPill: View {
	let text: String
	let systemImage: String
	let tint: Color

	var body: some View {
		Label(text, systemImage: systemImage)
			.font(.caption.weight(.semibold))
			.foregroundStyle(tint)
			.lineLimit(1)
			.padding(.horizontal, 8)
			.padding(.vertical, 4)
			.background(tint.opacity(0.12), in: Capsule())
	}
}

private extension OuraRingConnectionStatus {
	var systemImage: String {
		switch self {
		case .disabled:
			return "power.circle"
		case .bluetoothUnavailable, .authFailed:
			return "exclamationmark.triangle.fill"
		case .scanning:
			return "dot.radiowaves.left.and.right"
		case .connecting, .adopting, .authenticating:
			return "arrow.triangle.2.circlepath"
		case .connected, .authenticated:
			return "checkmark.circle.fill"
		case .disconnected:
			return "circle"
		}
	}

	var tint: Color {
		switch self {
		case .disabled, .disconnected:
			return .secondary
		case .bluetoothUnavailable, .authFailed:
			return .red
		case .scanning:
			return .blue
		case .connecting, .adopting, .authenticating:
			return .orange
		case .connected, .authenticated:
			return .green
		}
	}
}
