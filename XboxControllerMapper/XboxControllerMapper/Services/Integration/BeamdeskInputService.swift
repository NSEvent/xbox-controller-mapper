import Foundation

enum BeamdeskInputPhase: String, Equatable {
    case pressed
    case released
}

enum BeamdeskInputHand: Hashable {
	case left
	case right
}

enum BeamdeskHandInput: String, CaseIterable {
    case leftSwipeLeft = "controllerkeys.beamdesk-hand.left.swipe-left"
    case leftSwipeRight = "controllerkeys.beamdesk-hand.left.swipe-right"
    case leftSwipeForward = "controllerkeys.beamdesk-hand.left.swipe-forward"
    case leftSwipeBack = "controllerkeys.beamdesk-hand.left.swipe-back"
    case leftThumbTap = "controllerkeys.beamdesk-hand.left.thumb-tap"
    case rightSwipeLeft = "controllerkeys.beamdesk-hand.right.swipe-left"
    case rightSwipeRight = "controllerkeys.beamdesk-hand.right.swipe-right"
    case rightSwipeForward = "controllerkeys.beamdesk-hand.right.swipe-forward"
    case rightSwipeBack = "controllerkeys.beamdesk-hand.right.swipe-back"
    case rightThumbTap = "controllerkeys.beamdesk-hand.right.thumb-tap"

    var button: ControllerButton {
        switch self {
        case .leftSwipeLeft: return .beamdeskLeftSwipeLeft
        case .leftSwipeRight: return .beamdeskLeftSwipeRight
        case .leftSwipeForward: return .beamdeskLeftSwipeForward
        case .leftSwipeBack: return .beamdeskLeftSwipeBack
        case .leftThumbTap: return .beamdeskLeftThumbTap
        case .rightSwipeLeft: return .beamdeskRightSwipeLeft
        case .rightSwipeRight: return .beamdeskRightSwipeRight
        case .rightSwipeForward: return .beamdeskRightSwipeForward
        case .rightSwipeBack: return .beamdeskRightSwipeBack
        case .rightThumbTap: return .beamdeskRightThumbTap
        }
    }

	var hand: BeamdeskInputHand {
		switch self {
		case .leftSwipeLeft, .leftSwipeRight, .leftSwipeForward, .leftSwipeBack, .leftThumbTap:
			return .left
		case .rightSwipeLeft, .rightSwipeRight, .rightSwipeForward, .rightSwipeBack, .rightThumbTap:
			return .right
		}
	}
}

struct BeamdeskGestureCooldown {
	/// Matches the Oura directional-flick cooldown: long enough to absorb a
	/// second recognition emitted while the hand settles after one gesture.
	static let defaultDuration: TimeInterval = 0.65

	var duration = defaultDuration
	private var lastAcceptedPressByHand: [BeamdeskInputHand: TimeInterval] = [:]

	mutating func accepts(_ input: BeamdeskHandInput, at timestamp: TimeInterval) -> Bool {
		let hand = input.hand
		if let previous = lastAcceptedPressByHand[hand], timestamp - previous < duration {
			return false
		}
		lastAcceptedPressByHand[hand] = timestamp
		return true
	}

	mutating func reset() {
		lastAcceptedPressByHand.removeAll()
	}
}

struct BeamdeskInputEvent: Equatable {
    let input: BeamdeskHandInput
    let phase: BeamdeskInputPhase

    init?(notificationID: String, argument: String?) {
        guard let input = BeamdeskHandInput(rawValue: notificationID),
              let argument,
              let phase = BeamdeskInputPhase(rawValue: argument) else { return nil }
        self.input = input
        self.phase = phase
    }
}

/// Adapts Beamdesk's distributed notifications to ControllerKeys' normal
/// press/release pipeline. The mapping engine then supplies profiles, layers,
/// holds, chords, sequences, macros, scripts, and action feedback unchanged.
final class BeamdeskInputService: NSObject, @unchecked Sendable {
    static let notificationName = Notification.Name(
        "xyz.kevintang.beamdesk.controllerkeys-command"
    )

    private let controllerService: ControllerService
    private let notificationCenter: DistributedNotificationCenter
    private let lock = NSLock()
    private var pressedButtons: Set<ControllerButton> = []
	private var gestureCooldown = BeamdeskGestureCooldown()
    private var observing = false

    init(
        controllerService: ControllerService,
        notificationCenter: DistributedNotificationCenter = .default()
    ) {
        self.controllerService = controllerService
        self.notificationCenter = notificationCenter
        super.init()
        start()
    }

    func stop() {
        lock.lock()
        let wasObserving = observing
        observing = false
        let buttons = pressedButtons
        pressedButtons.removeAll()
		gestureCooldown.reset()
        lock.unlock()

        if wasObserving {
            notificationCenter.removeObserver(self, name: Self.notificationName, object: nil)
        }
        for button in buttons {
            controllerService.handleButton(button, pressed: false)
        }
    }

    deinit {
        notificationCenter.removeObserver(self, name: Self.notificationName, object: nil)
    }

    @objc private func receive(_ notification: Notification) {
        guard let notificationID = notification.object as? String,
              let event = BeamdeskInputEvent(
                  notificationID: notificationID,
                  argument: notification.userInfo?["argument"] as? String
              ) else { return }
        handle(event)
    }

    private func start() {
        lock.lock()
        guard !observing else { lock.unlock(); return }
        observing = true
        lock.unlock()

        notificationCenter.addObserver(
            self,
            selector: #selector(receive(_:)),
            name: Self.notificationName,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    private func handle(_ event: BeamdeskInputEvent) {
        let button = event.input.button
        lock.lock()
        let changed: Bool
        switch event.phase {
		case .pressed:
			if pressedButtons.contains(button)
				|| !gestureCooldown.accepts(
					event.input,
					at: ProcessInfo.processInfo.systemUptime
				) {
				changed = false
			} else {
				changed = pressedButtons.insert(button).inserted
			}
		case .released:
			changed = pressedButtons.remove(button) != nil
        }
        lock.unlock()

        guard changed else { return }
        controllerService.handleButton(button, pressed: event.phase == .pressed)
    }
}
