import Combine
import Foundation
import CoreGraphics

@MainActor
final class StickCalibrationSession: ObservableObject {
	@Published var draft: StickCalibrationDraft?
	@Published private(set) var measurement = StickCalibrationMeasurement()
	@Published private(set) var current = CGPoint.zero
	@Published private(set) var trail: [CGPoint] = []
	@Published private(set) var measuringRest = false
	@Published private(set) var measuringRange = false
	@Published private(set) var invalidationReason = ""
	private var profileId: UUID?
	private var side = JoystickSide.left
	private var previewId: UUID?
	private weak var engine: MappingEngine?
	private weak var profiles: ProfileManager?
	private weak var controller: ControllerService?
	private var restStarted: Date?
	private var subscriptions = Set<AnyCancellable>()

	var canSave: Bool { invalidationReason.isEmpty && !measuringRest && !measuringRange && (draft.map { !$0.hasChanges || $0.isValid } ?? false) && controller?.isConnected == true }

	func start(side: JoystickSide, controller: ControllerService, profiles: ProfileManager, engine: MappingEngine) {
		stop()
		self.side = side; self.controller = controller; self.profiles = profiles; self.engine = engine
		guard controller.isConnected, let profile = profiles.activeProfile else {
			invalidationReason = "Connect a controller and choose a profile, then restart calibration."
			return
		}
		profileId = profile.id
		draft = StickCalibrationDraft(tuning: tuning(in: profile), side: side)
		measurement = StickCalibrationMeasurement(); trail = []; current = .zero
		invalidationReason = ""
		previewId = engine.beginInputPreview()
		// Duplicate `true` publishes mark active-controller replacement, too.
		controller.$isConnected.dropFirst().sink { [weak self] _ in
			self?.invalidate("Controller changed or disconnected. Previous measurements were discarded. Restart with the current controller.")
		}.store(in: &subscriptions)
		profiles.$activeProfile.dropFirst().sink { [weak self] profile in
			guard let self else { return }
			if profile?.id != self.profileId || profile.map({ self.tuning(in: $0) }) != self.draft?.original {
				self.invalidate("Profile or stick settings changed. Restart calibration to avoid replacing newer settings.")
			}
		}.store(in: &subscriptions)
	}

	func measureRest(now: Date = Date()) {
		guard invalidationReason.isEmpty, previewId != nil else { return }
		measurement = StickCalibrationMeasurement(); trail = []
		measuringRange = false; measuringRest = true; restStarted = now
	}
	func measureRange() {
		guard measurement.suggestedInner != nil, !measuringRest, invalidationReason.isEmpty else { return }
		measuringRange = true
	}
	func stopRange() { measuringRange = false }
	func sample(now: Date = Date()) {
		guard invalidationReason.isEmpty, let controller, previewId != nil else { return }
		let snapshot = controller.snapshot()
		current = side == .left ? snapshot.leftStick : snapshot.rightStick
		trail.append(current)
		if trail.count > 300 { trail.removeFirst() }
		if measuringRest {
			measurement.recordRest(current)
			if now.timeIntervalSince(restStarted ?? now) >= 2 { measuringRest = false }
		} else if measuringRange {
			measurement.recordRange(current)
			if measurement.directionsMeasured == 8 { measuringRange = false }
		}
	}
	@discardableResult func save() -> Bool {
		guard canSave, let draft, let profile = profiles?.activeProfile, profile.id == profileId,
			  tuning(in: profile) == draft.original else { return false }
		// Opening and saving without an edit is exactly a no-op.
		if draft.hasChanges {
			var settings = profile.joystickSettings
			if side == .left { settings.leftStick = draft.proposed } else { settings.rightStick = draft.proposed }
			stop()
			profiles?.updateJoystickSettings(settings, in: profile)
		}
		return true
	}
	func stop() {
		subscriptions.removeAll(); measuringRest = false; measuringRange = false
		if let previewId { engine?.endInputPreview(previewId) }
		previewId = nil
	}
	private func invalidate(_ reason: String) {
		stop(); measurement = StickCalibrationMeasurement(); trail = []
		invalidationReason = reason
	}
	private func tuning(in profile: Profile) -> StickTuning {
		side == .left ? profile.joystickSettings.leftStick : profile.joystickSettings.rightStick
	}
}
