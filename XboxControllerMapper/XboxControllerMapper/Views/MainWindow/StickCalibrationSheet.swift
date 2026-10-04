import SwiftUI
import Combine

struct StickCalibrationSheet: View {
	let side: JoystickSide
	@EnvironmentObject private var controller: ControllerService
	@EnvironmentObject private var engine: MappingEngine
	@EnvironmentObject private var profiles: ProfileManager
	@Environment(\.dismiss) private var dismiss
	@StateObject private var session = StickCalibrationSession()
	private let timer = Timer.publish(every: 1 / 30, on: .main, in: .common).autoconnect()

	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			Text("Calibrate \(side == .left ? "Left" : "Right") Stick").font(.title2.bold())
			ScrollView {
				VStack(alignment: .leading, spacing: 14) {
					Text("Mapped actions are paused during measurement. Changes stay in this draft until you save.")
						.font(.callout).foregroundStyle(.secondary)
					if !session.invalidationReason.isEmpty {
						Text(session.invalidationReason).foregroundStyle(.orange)
						Button("Restart Calibration") { start() }.disabled(!controller.isConnected)
					}
					plot
					Text(session.measuringRest ? "Keep the stick released for two seconds…" : "1. Measure rest drift. 2. Measure the full range.").font(.headline)
					HStack {
						Button("Measure Rest Drift") { session.measureRest() }.disabled(session.measuringRest || !session.invalidationReason.isEmpty)
						Button(session.measuringRange ? "Stop Range" : "Measure Full Range") {
							if session.measuringRange { session.stopRange() } else { session.measureRange() }
						}.disabled(session.measurement.suggestedInner == nil || session.measuringRest || !session.invalidationReason.isEmpty)
					}
					HStack {
						Button("Use Rest Suggestion") { session.draft?.inner = session.measurement.suggestedInner ?? 0.15 }
							.disabled(session.measuringRest || session.measurement.suggestedInner == nil)
						Button("Use Range Suggestion") { session.draft?.outer = session.measurement.suggestedOuter ?? 1 }
							.disabled(session.measuringRange || session.measurement.suggestedOuter == nil)
					}
					Text("Full range: \(session.measurement.directionsMeasured)/8 directions. \(session.measurement.suggestedOuter == nil ? "Partial measurements do not change the range." : "All directions measured; range suggestion ready.")")
						.font(.caption).foregroundStyle(.secondary)
					if session.measurement.restSamples >= 45, session.measurement.suggestedInner == nil {
						Text("Too much movement at rest. Release the stick and measure again.").font(.caption).foregroundStyle(.orange)
					}
					if let draft = session.draft {
						HStack { Text("Inner deadzone"); Slider(value: field(\.inner), in: 0...1); Text(draft.inner, format: .percent.precision(.fractionLength(0))) }
						HStack { Text("Full-output range"); Slider(value: field(\.outer), in: 0.5...1); Text(draft.outer, format: .percent.precision(.fractionLength(0))) }
						Toggle("Apply deadzone to mouse, scroll and custom modes", isOn: field(\.applyToAllModes))
						Text("Deadzone affects \(draft.applyToAllModes ? "all three response modes" : draft.modeName). Full-output range affects this stick across modes. Layer-specific deadzones can override this profile setting.")
							.font(.caption).foregroundStyle(.secondary)
						Text("\(draft.modeName) deadzone: \(percent(StickCalibrationDraft.deadzone(in: draft.original, side: side))) → \(percent(StickCalibrationDraft.deadzone(in: draft.proposed, side: side))) · Range: \(percent(draft.original.outerRange)) → \(percent(draft.proposed.outerRange))")
							.font(.callout.monospacedDigit())
						if !draft.isValid { Text("Inner deadzone must be smaller than the full-output range.").foregroundStyle(.orange) }
						Button("Reset Draft to Current Settings") { session.draft = StickCalibrationDraft(tuning: draft.original, side: side) }
					}
				}
			}
			Divider()
			HStack {
				Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
				Spacer()
				Button("Save Calibration") { if session.save() { dismiss() } }
					.keyboardShortcut(.defaultAction).disabled(!session.canSave)
			}
		}
		.padding(24).frame(width: 600, height: 720)
		.onAppear { start() }.onReceive(timer) { session.sample(now: $0) }.onDisappear { session.stop() }
	}
	private func start() { session.start(side: side, controller: controller, profiles: profiles, engine: engine) }
	private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
	private func field<T>(_ path: WritableKeyPath<StickCalibrationDraft, T>) -> Binding<T> {
		Binding(get: { session.draft![keyPath: path] }, set: { session.draft?[keyPath: path] = $0 })
	}
	private var plot: some View {
		Canvas { context, size in
			let center = CGPoint(x: size.width / 2, y: size.height / 2)
			let scale = min(size.width, size.height) / 2 - 12
			for (radius, color) in [(1.0, Color.secondary), (session.draft?.outer ?? 1, Color.blue), (session.draft?.inner ?? 0.15, Color.orange)] {
				let rect = CGRect(x: center.x - radius * scale, y: center.y - radius * scale, width: radius * scale * 2, height: radius * scale * 2)
				context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: 1.5)
			}
			for point in session.trail {
				context.fill(Path(ellipseIn: CGRect(x: center.x + point.x * scale - 2, y: center.y - point.y * scale - 2, width: 4, height: 4)), with: .color(.blue.opacity(0.3)))
			}
			context.fill(Path(ellipseIn: CGRect(x: center.x + session.current.x * scale - 4, y: center.y - session.current.y * scale - 4, width: 8, height: 8)), with: .color(.primary))
		}.frame(height: 190).accessibilityLabel("Live stick X \(session.current.x), Y \(session.current.y)")
	}
}
