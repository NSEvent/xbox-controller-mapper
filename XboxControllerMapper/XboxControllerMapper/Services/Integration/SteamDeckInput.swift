import Foundation

/// ScreenShell authenticates the network peer; this existing-user IPC carries
/// only bounded controller state. Mapping stays in the destination's engine.
@MainActor
final class SteamDeckInput: NSObject {
	private let controller: ControllerService
	private var lease = BeamdeskGamepadLease()
	private var pressed: Set<ControllerButton> = []
	private var pads = SteamDeckFrame.released.pads
	private var taps = [SteamControllerTouchpadTapTracker(), SteamControllerTouchpadTapTracker()]
	private var expiry: Task<Void, Never>?
	private var stopped = false
	private var needsNeutral = true
	private let center: DistributedNotificationCenter

	init(controller: ControllerService, observe: Bool = true,
		 center: DistributedNotificationCenter = .default()) {
		self.controller = controller
		self.center = center
		super.init()
		if observe {
			center.addObserver(self, selector: #selector(notification(_:)),
				name: Notification.Name(SteamDeckFrame.notification), object: nil,
				suspensionBehavior: .deliverImmediately)
		}
	}

	@objc private func notification(_ value: Notification) {
		receive(value.userInfo?["state"] as? String)
	}

	func receive(_ text: String?) {
		guard !stopped, let frame = SteamDeckFrame.parse(text),
			let session = frame.session, let sequence = frame.sequence, sequence > 0 else { return }
		if frame.active && !controller.canAcceptSteamDeckInput {
			needsNeutral = true
			releaseInputs(); controller.setSteamDeckConnected(false)
			expiry?.cancel()
			return
		}
		if frame.active && needsNeutral && !frame.isNeutral { return }
		if frame.active && (!lease.active || lease.session != session) && !frame.isNeutral { return }
		let bridge = BeamdeskGamepadSnapshot(version: 1, session: session, sequence: sequence,
			active: frame.active, buttons: Set(frame.buttons.compactMap(ControllerButton.init(rawValue:))),
			axes: frame.axes)
		let oldSession = lease.session
		guard lease.accept(bridge, now: ProcessInfo.processInfo.systemUptime) else { return }
		if oldSession != session { releaseInputs() }
		expiry?.cancel()
		guard frame.active, controller.canAcceptSteamDeckInput else {
			releaseInputs(); controller.setSteamDeckConnected(false)
			return
		}
		controller.setSteamDeckConnected(true)
		needsNeutral = false
		var next = bridge.effectiveButtons
		// Digital trigger thresholds match the ordinary controller path.
		if frame.axes[4] > 0.25 { next.insert(.leftTrigger) }
		if frame.axes[5] > 0.25 { next.insert(.rightTrigger) }
		for button in pressed.subtracting(next) { controller.handleButton(button, pressed: false) }
		for button in next.subtracting(pressed) { controller.handleButton(button, pressed: true) }
		pressed = next
		controller.updateLeftStick(x: frame.axes[0], y: frame.axes[1])
		controller.updateRightStick(x: frame.axes[2], y: frame.axes[3])
		controller.updateBeamdeskTriggerValues(left: frame.axes[4], right: frame.axes[5])
		for index in 0..<2 { updatePad(index, frame.pads[index]) }
		if let m = frame.motion {
			controller.processSteamMotion(.init(timestamp: UInt32(truncatingIfNeeded: sequence),
				accelX: m[0], accelY: m[1], accelZ: m[2], gyroX: m[3], gyroY: m[4], gyroZ: m[5]))
		}
		expiry = Task { [weak self] in
			try? await Task.sleep(for: .seconds(BeamdeskGamepadLease.timeout))
			guard !Task.isCancelled, let self else { return }
			if self.lease.expire(now: ProcessInfo.processInfo.systemUptime) {
				self.needsNeutral = true
				self.releaseInputs(); self.controller.setSteamDeckConnected(false)
			}
		}
	}

	private func updatePad(_ index: Int, _ pad: SteamDeckFrame.Pad) {
		let side: SteamTouchpadSide = index == 0 ? .left : .right
		let state = SteamControllerTouchpadState(x: pad.x, y: pad.y,
			isTouching: pad.touching, isPressed: pad.pressed)
		controller.updateSteamTouchpad(side: side, x: pad.x, y: pad.y, isTouching: pad.touching)
		if pad.pressed != pads[index].pressed {
			controller.handleSteamTouchpadClick(side: side, state: state, pressed: pad.pressed)
		}
		taps[index].update(state: state, now: CFAbsoluteTimeGetCurrent()) { [controller] region in
			let button = controller.touchpadInputMode == .wholePad ? side.wholeTapButton :
				ControllerButton.from(steamTouchpadSide: side, region: region, trigger: .touch)
			if let button { controller.emitInputEvent(.controllerButtonTap(button)) }
		}
		pads[index] = pad
	}

	func stop() {
		stopped = true
		needsNeutral = true
		center.removeObserver(self)
		expiry?.cancel(); expiry = nil
		lease.retire(); releaseInputs(); controller.setSteamDeckConnected(false)
	}

	private func releaseInputs() {
		// A hardware takeover already cleaned the old state; never release its new buttons.
		if controller.isSteamDeckActiveInputSource {
			for button in pressed { controller.handleButton(button, pressed: false) }
			for index in 0..<2 {
				let side: SteamTouchpadSide = index == 0 ? .left : .right
				if pads[index].pressed {
					controller.handleSteamTouchpadClick(side: side,
						state: .init(x: pads[index].x, y: pads[index].y,
							isTouching: false, isPressed: false), pressed: false)
				}
				controller.updateSteamTouchpad(side: side, x: 0, y: 0, isTouching: false)
			}
			controller.updateLeftStick(x: 0, y: 0)
			controller.updateRightStick(x: 0, y: 0)
			controller.updateBeamdeskTriggerValues(left: 0, right: 0)
		}
		pressed.removeAll()
		pads = SteamDeckFrame.released.pads
		taps = [SteamControllerTouchpadTapTracker(), SteamControllerTouchpadTapTracker()]
	}
}
