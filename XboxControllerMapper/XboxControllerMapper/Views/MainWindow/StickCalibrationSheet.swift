import SwiftUI
import Combine

struct StickCalibrationSheet: View {
	let side: JoystickSide
	@EnvironmentObject private var controller: ControllerService
	@EnvironmentObject private var engine: MappingEngine
	@EnvironmentObject private var profiles: ProfileManager
	@Environment(\.dismiss) private var dismiss
	@State private var profileId: UUID?
	@State private var previewId: UUID?
	@State private var measurement = StickCalibrationMeasurement()
	@State private var trail: [CGPoint] = []
	@State private var current = CGPoint.zero
	@State private var restStarted: Date?
	@State private var measuringRest = false
	@State private var inner = 0.15
	@State private var outer = 1.0
	private let timer = Timer.publish(every: 1 / 30, on: .main, in: .common).autoconnect()

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text("Calibrate \(side == .left ? "Left" : "Right") Stick").font(.title2.bold())
			Text("Mapped actions are paused. Settings apply to this profile; repeat for another controller or profile.").font(.callout).foregroundStyle(.secondary)
			Canvas { context, size in
				let center = CGPoint(x: size.width / 2, y: size.height / 2)
				let scale = min(size.width, size.height) / 2 - 12
				for (radius, color) in [(1.0, Color.secondary), (outer, Color.blue), (inner, Color.orange)] {
					let rect = CGRect(x: center.x - radius * scale, y: center.y - radius * scale, width: radius * scale * 2, height: radius * scale * 2)
					context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: 1.5)
				}
				for point in trail {
					let rect = CGRect(x: center.x + point.x * scale - 2, y: center.y - point.y * scale - 2, width: 4, height: 4)
					context.fill(Path(ellipseIn: rect), with: .color(.blue.opacity(0.3)))
				}
				let dot = CGRect(x: center.x + current.x * scale - 4, y: center.y - current.y * scale - 4, width: 8, height: 8)
				context.fill(Path(ellipseIn: dot), with: .color(.primary))
			}.frame(height: 230).accessibilityLabel("Live stick X \(current.x), Y \(current.y)")
			Text(measuringRest ? "Release the stick. Measuring drift for two seconds…" : "1. Measure rest drift. 2. Slowly rotate the stick around its full edge.")
			HStack {
				Button("Measure Rest Drift") {
					measurement = StickCalibrationMeasurement()
					trail = []
					measuringRest = true
					restStarted = Date()
				}.disabled(measuringRest)
				Text("Range: \(measurement.directionsMeasured)/8 directions").font(.caption)
			}
			HStack {
				Button("Use Suggestions") {
					if let value = measurement.suggestedInner { inner = value }
					if let value = measurement.suggestedOuter { outer = value }
				}.disabled(measurement.suggestedInner == nil)
				if measurement.restSamples >= 45, measurement.suggestedInner == nil {
					Text("Too much movement at rest. Release the stick and measure again.").font(.caption).foregroundStyle(.orange)
				}
			}
			HStack { Text("Inner deadzone"); Slider(value: $inner, in: 0.02...0.45); Text(inner, format: .percent.precision(.fractionLength(0))) }
			HStack { Text("Full-output range"); Slider(value: $outer, in: 0.5...1); Text(outer, format: .percent.precision(.fractionLength(0))) }
			Text("Orange excludes drift; blue reaches full output. Sensitivity and acceleration stay unchanged.").font(.caption).foregroundStyle(.secondary)
			HStack {
				Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
				Spacer()
				Button("Save Calibration") { save(); dismiss() }
					.keyboardShortcut(.defaultAction)
					.disabled(measuringRest || !controller.isConnected || profiles.activeProfileId != profileId)
			}
		}
		.padding(24).frame(width: 560)
		.onAppear {
			profileId = profiles.activeProfileId
			let tuning = side == .left ? profiles.activeProfile?.joystickSettings.leftStick : profiles.activeProfile?.joystickSettings.rightStick
			outer = tuning?.outerRange ?? 1
			inner = min(0.45, (tuning?.mouseDeadzone ?? 0.15) * outer)
			previewId = engine.beginInputPreview()
		}
		.onReceive(timer) { now in
			let snapshot = controller.snapshot()
			current = side == .left ? snapshot.leftStick : snapshot.rightStick
			trail.append(current)
			if trail.count > 300 { trail.removeFirst() }
			if measuringRest {
				measurement.recordRest(current)
				if now.timeIntervalSince(restStarted ?? now) >= 2 { measuringRest = false }
			} else { measurement.recordRange(current) }
		}
		.onChange(of: profiles.activeProfileId) { _, id in if id != profileId { dismiss() } }
		.onChange(of: controller.isConnected) { _, _ in dismiss() }
		.onDisappear { if let previewId { engine.endInputPreview(previewId) } }
	}

	private func save() {
		guard let profile = profiles.activeProfile, profile.id == profileId else { return }
		var settings = profile.joystickSettings
		var tuning = side == .left ? settings.leftStick : settings.rightStick
		// The response strategies apply deadzones after travel normalization.
		let normalizedInner = min(0.9, inner / outer)
		tuning.mouseDeadzone = normalizedInner
		tuning.scrollDeadzone = normalizedInner
		tuning.customDeadzone = normalizedInner
		tuning.outerRange = outer
		if side == .left { settings.leftStick = tuning } else { settings.rightStick = tuning }
		profiles.updateJoystickSettings(settings, in: profile)
	}
}
