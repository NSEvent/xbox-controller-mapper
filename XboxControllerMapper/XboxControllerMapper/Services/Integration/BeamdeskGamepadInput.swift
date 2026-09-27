import Foundation

/// Full controller state from the authenticated Beamdesk session. Axes use GameController's
/// convention: left X/Y, right X/Y (-1...1, up positive), then triggers (0...1).
struct BeamdeskGamepadSnapshot: Decodable, Equatable {
	static let notificationID = "controllerkeys.gamepad.v1"
	let version: Int
	let session: UUID
	let sequence: UInt64
	let active: Bool
	let buttons: Set<ControllerButton>
	let axes: [Float]

	static let allowedButtons: Set<ControllerButton> = [
		.a, .b, .x, .y, .leftBumper, .rightBumper, .leftTrigger, .rightTrigger,
		.leftThumbstick, .rightThumbstick, .dpadUp, .dpadDown, .dpadLeft, .dpadRight,
		.menu, .view, .xbox,
	]
	static func parse(_ argument: String?) -> Self? {
		guard let argument, argument.utf8.count <= 4096,
			let value = try? JSONDecoder().decode(Self.self, from: Data(argument.utf8)),
			value.version == 1, value.sequence > 0, value.axes.count == 6,
			value.buttons.isSubset(of: allowedButtons),
			value.axes.enumerated().allSatisfy({ index, axis in
				axis.isFinite && axis <= 1 && axis >= (index < 4 ? -1 : 0)
			}) else { return nil }
		return value
	}
	var effectiveButtons: Set<ControllerButton> {
		var result = buttons
		if axes[4] > 0.25 { result.insert(.leftTrigger) }
		if axes[5] > 0.25 { result.insert(.rightTrigger) }
		return result
	}
}

struct BeamdeskGamepadLease {
	private(set) var session: UUID?
	private var sequence: UInt64 = 0
	private var retired: [UUID] = []
	private var lastSignal: TimeInterval = 0
	private var needsNeutral = true
	private(set) var active = false
	static let timeout: TimeInterval = 1.5

	mutating func accept(_ value: BeamdeskGamepadSnapshot, now: TimeInterval) -> Bool {
		guard !retired.contains(value.session) else { return false }
		if value.session != session {
			retire()
			session = value.session
			sequence = 0
			needsNeutral = true
		}
		guard value.sequence > sequence else { return false }
		if value.active && needsNeutral {
			guard value.buttons.isEmpty, value.axes.allSatisfy({ abs($0) < 0.15 }) else { return false }
			needsNeutral = false
		}
		sequence = value.sequence
		lastSignal = now
		active = value.active
		if !active { retire() }
		return true
	}
	mutating func expire(now: TimeInterval) -> Bool {
		guard active && now - lastSignal >= Self.timeout else { return false }
		active = false
		needsNeutral = true
		return true
	}
	mutating func retire() {
		if let session { retired.append(session); if retired.count > 32 { retired.removeFirst() } }
		session = nil; active = false; sequence = 0; needsNeutral = true
	}
}

/// Uses the normal input pipeline; no profile copy, action duplication, or synthetic mappings.
@MainActor
final class BeamdeskGamepadInput {
	private let controller: ControllerService
	private var lease = BeamdeskGamepadLease()
	private var pressed: Set<ControllerButton> = []
	private var expiry: Task<Void, Never>?
	private var stopped = false

	init(controller: ControllerService) { self.controller = controller }

	func receive(_ argument: String?) {
		guard !stopped, let value = BeamdeskGamepadSnapshot.parse(argument) else { return }
		let oldSession = lease.session
		guard lease.accept(value, now: ProcessInfo.processInfo.systemUptime) else { return }
		if oldSession != value.session { releaseInputs() }
		expiry?.cancel()
		guard value.active else { releaseInputs(); controller.setBeamdeskGamepadConnected(false); return }
		controller.setBeamdeskGamepadConnected(true)
		let next = value.effectiveButtons
		for button in pressed.subtracting(next) { controller.handleButton(button, pressed: false) }
		for button in next.subtracting(pressed) { controller.handleButton(button, pressed: true) }
		pressed = next
		controller.updateLeftStick(x: value.axes[0], y: value.axes[1])
		controller.updateRightStick(x: value.axes[2], y: value.axes[3])
		controller.updateBeamdeskTriggerValues(left: value.axes[4], right: value.axes[5])
		expiry = Task { [weak self] in
			try? await Task.sleep(for: .seconds(BeamdeskGamepadLease.timeout))
			guard !Task.isCancelled, let self else { return }
			if self.lease.expire(now: ProcessInfo.processInfo.systemUptime) {
				self.releaseInputs()
				self.controller.setBeamdeskGamepadConnected(false)
			}
		}
	}
	func stop() {
		stopped = true
		expiry?.cancel(); expiry = nil; lease.retire()
		releaseInputs(); controller.setBeamdeskGamepadConnected(false)
	}
	private func releaseInputs() {
		for button in pressed { controller.handleButton(button, pressed: false) }
		pressed.removeAll()
		controller.updateLeftStick(x: 0, y: 0)
		controller.updateRightStick(x: 0, y: 0)
		controller.updateBeamdeskTriggerValues(left: 0, right: 0)
	}
}
