import SwiftUI

/// Wii Remote settings: in-app pairing plus tuning for the tilt/IR pointer
/// (the mappable "Pointer (Hold)" action). Values persist globally in
/// UserDefaults; the Wiimote backend reads them live per report.
struct WiimoteSettingsView: View {
	@StateObject private var pairingService = WiimotePairingService()

	@AppStorage(Config.wiimoteTiltRollSpeedKey) private var tiltRollSpeed: Double = 30
	@AppStorage(Config.wiimoteTiltPitchSpeedKey) private var tiltPitchSpeed: Double = 44
	@AppStorage(Config.wiimoteTiltDeadzoneKey) private var tiltDeadzone: Double = 0.12
	@AppStorage(Config.wiimoteIRSpeedKey) private var irSpeed: Double = 1.0
	@AppStorage(Config.wiimoteIRSmoothingKey) private var irSmoothing: Double = 0.25
	@AppStorage(Config.wiimoteTiltEnabledKey) private var tiltEnabled: Bool = true
	@AppStorage(Config.wiimoteIREnabledKey) private var irEnabled: Bool = true

	var body: some View {
		Form {
			Section("Pairing") {
				VStack(alignment: .leading, spacing: 8) {
					Text("System Settings can't pair a Wii Remote — modern macOS rejects its old-style PIN. Pair here instead: open the battery cover and tap the red SYNC button every few seconds while scanning.")
						.font(.system(size: 12))
						.foregroundStyle(.secondary)
						.fixedSize(horizontal: false, vertical: true)

					HStack(spacing: 12) {
						Button(pairingService.isBusy ? "Scanning…" : "Pair Wii Remote") {
							pairingService.startPairing()
						}
						.disabled(pairingService.isBusy)

						if pairingService.isBusy {
							ProgressView()
								.controlSize(.small)
							Button("Cancel") { pairingService.stop() }
						}
					}

					if !pairingService.statusText.isEmpty {
						Text(pairingService.statusText)
							.font(.system(size: 12))
							.foregroundStyle(pairingService.phase == .paired ? Color.green : .secondary)
							.fixedSize(horizontal: false, vertical: true)
					}

					Text("Press any button to wake a paired remote. If it does not reconnect, use Pair Wii Remote again. Fresh AA batteries matter — a weak remote answers scans but drops connections.")
						.font(.system(size: 11))
						.foregroundStyle(.tertiary)
						.fixedSize(horizontal: false, vertical: true)
				}
				.padding(.vertical, 2)
			}

			Section("Pointer — Tilt") {
				Toggle("Tilt steering (accelerometer)", isOn: $tiltEnabled)
					.help("Move the pointer by tilting the remote. Turn off for sensor-bar-only aiming. Losing sight of the bar then stops the pointer.")
				SliderRow(
					label: "Side-to-side speed",
					value: $tiltRollSpeed,
					range: 5...80,
					description: "Pointer speed when rolling the remote left/right (px per report at full tilt).",
					specifier: "%.0f"
				)
				SliderRow(
					label: "Up-down speed",
					value: $tiltPitchSpeed,
					range: 5...80,
					description: "Pointer speed when pitching the remote up/down.",
					specifier: "%.0f"
				)
				SliderRow(
					label: "Deadzone",
					value: $tiltDeadzone,
					range: 0.02...0.30,
					description: "Tilt below this holds the cursor still, so a steady hand parks it.",
					specifier: "%.2f g"
				)
			}

			Section("Pointer — IR (sensor bar)") {
				Toggle("IR aiming", isOn: $irEnabled)
					.help("Point directly at the screen using IR sources.")
				SliderRow(
					label: "Speed",
					value: $irSpeed,
					range: 0.25...3.0,
					description: "Multiplier on IR aiming movement.",
					specifier: "%.2f×"
				)
				SliderRow(
					label: "Smoothing",
					value: $irSmoothing,
					range: 0.10...0.90,
					description: "Base smoothing — lower = steadier aim (smoothing auto-lightens during fast sweeps). Raise only if aiming feels laggy."
				)
				Text("Map B to Pointer (Toggle), then press B once to aim and again to stop. Power the sensor bar and place it above or below your display. Turn Tilt steering off for sensor-bar-only aiming. Movement is relative: toggle pointing off to recenter your hand.")
					.font(.system(size: 11))
					.foregroundStyle(.tertiary)
					.fixedSize(horizontal: false, vertical: true)
			}

			Section {
				Button("Reset pointer tuning to defaults") {
					tiltRollSpeed = 30
					tiltPitchSpeed = 44
					tiltDeadzone = 0.12
					irSpeed = 1.0
					irSmoothing = 0.25
				}
			}
		}
		.formStyle(.grouped)
	}

}
