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

					Text("Pairing is one-time: afterwards the remote reconnects on any button press. Fresh AA batteries matter — a weak remote answers scans but drops connections.")
						.font(.system(size: 11))
						.foregroundStyle(.tertiary)
						.fixedSize(horizontal: false, vertical: true)
				}
				.padding(.vertical, 2)
			}

			Section("Pointer — Tilt") {
				sliderRow(
					"Side-to-side speed",
					value: $tiltRollSpeed,
					range: 5...80,
					help: "Pointer speed when rolling the remote left/right (px per report at full tilt)."
				)
				sliderRow(
					"Up-down speed",
					value: $tiltPitchSpeed,
					range: 5...80,
					help: "Pointer speed when pitching the remote up/down."
				)
				sliderRow(
					"Deadzone",
					value: $tiltDeadzone,
					range: 0.02...0.30,
					format: "%.2f g",
					help: "Tilt below this holds the cursor still, so a steady hand parks it."
				)
			}

			Section("Pointer — IR (sensor bar / candles)") {
				sliderRow(
					"Speed",
					value: $irSpeed,
					range: 0.25...3.0,
					format: "%.2f×",
					help: "Multiplier on IR aiming movement."
				)
				sliderRow(
					"Smoothing",
					value: $irSmoothing,
					range: 0.10...0.90,
					format: "%.2f",
					help: "Base smoothing — lower = steadier aim (smoothing auto-lightens during fast sweeps). Raise only if aiming feels laggy."
				)
				Text("Hold the mapped 🎯 Pointer button and aim at the screen. With two IR sources visible (a sensor bar, or two candles ~20 cm apart under the display), aiming is direct; otherwise the pointer falls back to tilt.")
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

	@ViewBuilder
	private func sliderRow(
		_ title: String,
		value: Binding<Double>,
		range: ClosedRange<Double>,
		format: String = "%.0f",
		help: String
	) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack {
				Text(title)
				Spacer()
				Text(String(format: format, value.wrappedValue))
					.font(.system(size: 12, weight: .medium, design: .monospaced))
					.foregroundStyle(.secondary)
			}
			Slider(value: value, in: range)
			Text(help)
				.font(.system(size: 11))
				.foregroundStyle(.tertiary)
				.fixedSize(horizontal: false, vertical: true)
		}
		.padding(.vertical, 2)
	}
}
