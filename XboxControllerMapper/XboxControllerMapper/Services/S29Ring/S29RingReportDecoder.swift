import Foundation

/// The six logical controls the S29 ring exposes once its firmware quirks are
/// undone. Directions map onto the app's d-pad buttons; Camera and Home are
/// ring-only buttons.
nonisolated enum S29RingControl: String, CaseIterable, Sendable {
	case up
	case down
	case left
	case right
	case camera
	case home

	var button: ControllerButton {
		switch self {
		case .up: return .dpadUp
		case .down: return .dpadDown
		case .left: return .dpadLeft
		case .right: return .dpadRight
		case .camera: return .s29Camera
		case .home: return .s29Home
		}
	}
}

/// One logical press or release produced by the decoder.
nonisolated struct S29RingEvent: Equatable, Sendable, CustomStringConvertible {
	let control: S29RingControl
	let pressed: Bool

	static func press(_ control: S29RingControl) -> S29RingEvent {
		S29RingEvent(control: control, pressed: true)
	}

	static func release(_ control: S29RingControl) -> S29RingEvent {
		S29RingEvent(control: control, pressed: false)
	}

	var description: String {
		"\(control.rawValue) \(pressed ? "down" : "up")"
	}
}

/// Thresholds and timings for decoding the ring. Defaults come from observed
/// firmware behavior; tests inject their own values where useful.
nonisolated struct S29RingDecoderTuning: Equatable, Sendable {
	/// Horizontal swipe: |dx| at least this far and more than
	/// `swipeDominanceRatio` × |dy|.
	var horizontalSwipeDistance = 400
	/// Vertical swipe: |dy| at least this far and more than
	/// `swipeDominanceRatio` × |dx|.
	var verticalSwipeDistance = 500
	var swipeDominanceRatio = 2

	/// A held control is released this long after its last firmware pulse.
	var holdReleaseDelay: TimeInterval = 0.75
	/// How long a momentary tap stays pressed so the mapping engine sees a
	/// normal press/release pair.
	var tapDuration: TimeInterval = 0.04

	/// Volume-down disambiguation: a second code within this window of the
	/// first is a Camera double-tap…
	var volumeDownDoubleTapWindow: TimeInterval = 0.42
	/// …a second code after the double-tap window but within this one starts a
	/// Down hold, and no follow-up at all within it means one Camera tap.
	var volumeDownResolveWindow: TimeInterval = 0.75

	/// Left/Right hold bursts: synthetic short vertical strokes.
	var strokeMaxHorizontalDrift = 20
	var strokeMinVerticalDistance = 70
	var strokeMaxVerticalDistance = 350
	/// The first stroke of a burst must travel at least this far (positive dy).
	var burstStartMinVerticalDistance = 250
	var burstStrokeCount = 3
	/// All strokes of a burst must land within this window of the first.
	var burstWindow: TimeInterval = 0.5

	static let standard = S29RingDecoderTuning()
}

/// Pure decoder for the S29 ring's raw HID input reports.
///
/// Feed it full input reports (byte 0 = report ID) with a monotonic timestamp,
/// and call `advance(to:)` when `nextDeadline` passes; it returns logical
/// press/release events. It owns no timers, threads, or IOKit state, so tests
/// drive time explicitly.
///
/// Firmware behavior being undone:
/// - Swipes arrive as touch coordinates (report 1). They fire once per touch as
///   soon as the displacement crosses the threshold; the ring's X axis is
///   mirrored (dx > 0 means Left).
/// - Holding a control produces a stream of repeated codes with no release, so
///   a control is held while pulses keep arriving and released once they stop.
/// - Consumer bit 16 ("volume down") is shared by Camera tap, Camera
///   double-tap, and Down hold; the follow-up timing tells them apart.
/// - Left/Right holds arrive as bursts of short synthetic vertical strokes on
///   the touch report.
nonisolated struct S29RingReportDecoder: Sendable {
	static let touchReportID: UInt8 = 0x01
	static let consumerReportID: UInt8 = 0x03
	static let touchReportMinimumLength = 5
	static let consumerReportMinimumLength = 4

	/// Consumer-control bits (report 3, 24-bit little-endian mask).
	enum ConsumerBit {
		static let cameraHold = 1
		static let homeTap = 3
		static let upHold = 15
		static let volumeDown = 16
		static let homeHold = 19
	}

	struct TouchPoint: Equatable, Sendable {
		let x: Int
		let y: Int
	}

	struct TouchSample: Equatable, Sendable {
		let isTouching: Bool
		let point: TouchPoint
	}

	private struct Stroke {
		let time: TimeInterval
		let dy: Int
	}

	private struct ScheduledEvent {
		let time: TimeInterval
		let event: S29RingEvent
		let sequence: Int
	}

	let tuning: S29RingDecoderTuning

	// Touch surface
	private var touchStart: TouchPoint?
	private var touchLast: TouchPoint?
	private var swipeFiredThisTouch = false
	private var burst: [Stroke] = []

	// Consumer control
	private var previousConsumerMask: UInt32 = 0
	private var pendingVolumeDownTime: TimeInterval?

	// Output state
	private var heldLastPulse: [S29RingControl: TimeInterval] = [:]
	private var scheduled: [ScheduledEvent] = []
	private var scheduleSequence = 0
	private(set) var pressedControls: Set<S29RingControl> = []

	init(tuning: S29RingDecoderTuning = .standard) {
		self.tuning = tuning
	}

	// MARK: - Pure report parsing

	/// Parses report 1 (touch surface): byte 1 bit 0 = finger down, 12-bit X
	/// and Y packed into bytes 2…4.
	static func parseTouchReport(_ report: [UInt8]) -> TouchSample? {
		guard report.count >= touchReportMinimumLength, report[0] == touchReportID else { return nil }
		let isTouching = (report[1] & 0x01) != 0
		let x = Int(report[2]) | (Int(report[3] & 0x0F) << 8)
		let y = Int(report[3] >> 4) | (Int(report[4]) << 4)
		return TouchSample(isTouching: isTouching, point: TouchPoint(x: x, y: y))
	}

	/// Parses report 3 (consumer control): 24-bit little-endian bitmask in
	/// bytes 1…3.
	static func parseConsumerReport(_ report: [UInt8]) -> UInt32? {
		guard report.count >= consumerReportMinimumLength, report[0] == consumerReportID else { return nil }
		return UInt32(report[1]) | (UInt32(report[2]) << 8) | (UInt32(report[3]) << 16)
	}

	/// Swipe direction for a displacement measured from touch start, or nil
	/// when it hasn't crossed a threshold. X is mirrored: dx > 0 is Left.
	static func swipeDirection(dx: Int, dy: Int, tuning: S29RingDecoderTuning = .standard) -> S29RingControl? {
		let absDX = abs(dx)
		let absDY = abs(dy)
		if absDX >= tuning.horizontalSwipeDistance && absDX > tuning.swipeDominanceRatio * absDY {
			return dx > 0 ? .left : .right
		}
		if absDY >= tuning.verticalSwipeDistance && absDY > tuning.swipeDominanceRatio * absDX {
			return dy > 0 ? .up : .down
		}
		return nil
	}

	// MARK: - Decoding

	/// Earliest time at which `advance(to:)` has work to do, if any.
	var nextDeadline: TimeInterval? {
		var deadlines: [TimeInterval] = scheduled.map(\.time)
		deadlines.append(contentsOf: heldLastPulse.values.map { $0 + tuning.holdReleaseDelay })
		if let pendingVolumeDownTime {
			deadlines.append(pendingVolumeDownTime + tuning.volumeDownResolveWindow)
		}
		return deadlines.min()
	}

	/// Decodes one full input report (byte 0 = report ID) received at `time`.
	/// Deadlines up to `time` are resolved first so events stay ordered.
	mutating func process(report: [UInt8], at time: TimeInterval) -> [S29RingEvent] {
		var events = advance(to: time)
		if let sample = Self.parseTouchReport(report) {
			handleTouch(sample, at: time, events: &events)
		} else if let mask = Self.parseConsumerReport(report) {
			handleConsumer(mask: mask, at: time, events: &events)
		}
		// Taps scheduled for "now" (e.g. a tap's press) are emitted immediately.
		events.append(contentsOf: advance(to: time))
		return events
	}

	/// Resolves every deadline at or before `time`: momentary tap releases,
	/// hold releases after pulses stop, and a lone volume-down → Camera tap.
	mutating func advance(to time: TimeInterval) -> [S29RingEvent] {
		var events: [S29RingEvent] = []
		while let deadline = nextDeadline, deadline <= time {
			resolveDeadline(deadline, events: &events)
		}
		return events
	}

	/// Drops all pending decoding state and releases every control that is
	/// still pressed (disconnect, mapping disabled, app quit).
	mutating func reset() -> [S29RingEvent] {
		let releases = S29RingControl.allCases
			.filter { pressedControls.contains($0) }
			.map(S29RingEvent.release)
		touchStart = nil
		touchLast = nil
		swipeFiredThisTouch = false
		burst.removeAll()
		previousConsumerMask = 0
		pendingVolumeDownTime = nil
		heldLastPulse.removeAll()
		scheduled.removeAll()
		pressedControls.removeAll()
		return releases
	}

	// MARK: - Touch surface

	private mutating func handleTouch(_ sample: TouchSample, at time: TimeInterval, events: inout [S29RingEvent]) {
		if sample.isTouching {
			guard let start = touchStart else {
				touchStart = sample.point
				touchLast = sample.point
				swipeFiredThisTouch = false
				return
			}
			touchLast = sample.point
			guard !swipeFiredThisTouch else { return }
			// Fire as soon as the threshold is crossed — waiting for lift
			// felt laggy.
			if let direction = Self.swipeDirection(
				dx: sample.point.x - start.x,
				dy: sample.point.y - start.y,
				tuning: tuning
			) {
				swipeFiredThisTouch = true
				burst.removeAll()
				tap(direction, at: time)
			}
			return
		}

		// Finger lifted.
		guard let start = touchStart else { return }
		// Lift reports may carry the final position; an all-zero lift is
		// treated as "no coordinates" and falls back to the last down sample.
		let end = sample.point == TouchPoint(x: 0, y: 0) ? (touchLast ?? start) : sample.point
		let fired = swipeFiredThisTouch
		touchStart = nil
		touchLast = nil
		swipeFiredThisTouch = false
		guard !fired else { return }

		let dx = end.x - start.x
		let dy = end.y - start.y
		if let direction = Self.swipeDirection(dx: dx, dy: dy, tuning: tuning) {
			burst.removeAll()
			tap(direction, at: time)
			return
		}
		registerStroke(dx: dx, dy: dy, at: time)
	}

	/// Left/Right holds: bursts of `burstStrokeCount` short vertical strokes
	/// starting with a long positive one. One positive stroke → Left pulse,
	/// all positive → Right pulse. Anything else resets detection.
	private mutating func registerStroke(dx: Int, dy: Int, at time: TimeInterval) {
		let absDY = abs(dy)
		let isStroke = abs(dx) <= tuning.strokeMaxHorizontalDrift
			&& absDY >= tuning.strokeMinVerticalDistance
			&& absDY <= tuning.strokeMaxVerticalDistance
		guard isStroke else {
			burst.removeAll()
			return
		}

		if let first = burst.first, time - first.time > tuning.burstWindow {
			burst.removeAll()
		}
		if burst.isEmpty {
			guard dy >= tuning.burstStartMinVerticalDistance else { return }
		}
		burst.append(Stroke(time: time, dy: dy))
		guard burst.count >= tuning.burstStrokeCount else { return }

		let positiveStrokes = burst.filter { $0.dy > 0 }.count
		burst.removeAll()
		if positiveStrokes == 1 {
			pulse(.left, at: time)
		} else if positiveStrokes == tuning.burstStrokeCount {
			pulse(.right, at: time)
		}
	}

	// MARK: - Consumer control

	private mutating func handleConsumer(mask: UInt32, at time: TimeInterval, events: inout [S29RingEvent]) {
		// Only newly-set bits are events; the firmware re-sends the mask and
		// clears it between pulses.
		let newBits = mask & ~previousConsumerMask
		previousConsumerMask = mask
		guard newBits != 0 else { return }

		func isNew(_ bit: Int) -> Bool { newBits & (UInt32(1) << UInt32(bit)) != 0 }

		if isNew(ConsumerBit.homeTap) { tap(.home, at: time) }
		if isNew(ConsumerBit.homeHold) { pulse(.home, at: time) }
		if isNew(ConsumerBit.cameraHold) { pulse(.camera, at: time) }
		if isNew(ConsumerBit.upHold) { pulse(.up, at: time) }
		if isNew(ConsumerBit.volumeDown) { handleVolumeDown(at: time) }
	}

	private mutating func handleVolumeDown(at time: TimeInterval) {
		if heldLastPulse[.down] != nil {
			pulse(.down, at: time)
			return
		}
		guard let first = pendingVolumeDownTime else {
			pendingVolumeDownTime = time
			return
		}
		pendingVolumeDownTime = nil
		if time - first <= tuning.volumeDownDoubleTapWindow {
			// Camera double-tap: two distinct taps so double-tap mappings fire.
			tap(.camera, at: time)
			tap(.camera, at: time + 2 * tuning.tapDuration)
		} else {
			pulse(.down, at: time)
		}
	}

	// MARK: - Output primitives

	/// Momentary press followed by a release `tapDuration` later.
	private mutating func tap(_ control: S29RingControl, at time: TimeInterval) {
		if heldLastPulse[control] != nil {
			// Already held by pulses; a tap just keeps it alive.
			heldLastPulse[control] = max(heldLastPulse[control] ?? time, time)
			return
		}
		schedule(.press(control), at: time)
		schedule(.release(control), at: time + tuning.tapDuration)
	}

	/// Firmware hold pulse: press on the first, then keep the control held
	/// until pulses stop for `holdReleaseDelay`.
	private mutating func pulse(_ control: S29RingControl, at time: TimeInterval) {
		// A pending tap release for this control becomes a hold instead.
		scheduled.removeAll { $0.event == .release(control) }
		if heldLastPulse[control] == nil && !pressedControls.contains(control)
			&& !scheduled.contains(where: { $0.event == .press(control) }) {
			schedule(.press(control), at: time)
		}
		heldLastPulse[control] = time
	}

	private mutating func schedule(_ event: S29RingEvent, at time: TimeInterval) {
		scheduleSequence += 1
		scheduled.append(ScheduledEvent(time: time, event: event, sequence: scheduleSequence))
	}

	private mutating func resolveDeadline(_ deadline: TimeInterval, events: inout [S29RingEvent]) {
		// Scheduled events first (in insertion order), then hold releases,
		// then volume-down resolution — all at the same instant.
		if let next = scheduled
			.filter({ $0.time <= deadline })
			.min(by: { ($0.time, $0.sequence) < ($1.time, $1.sequence) }) {
			scheduled.removeAll { $0.sequence == next.sequence }
			emit(next.event, events: &events)
			return
		}

		if let (control, _) = heldLastPulse.first(where: { $0.value + tuning.holdReleaseDelay <= deadline }) {
			heldLastPulse[control] = nil
			emit(.release(control), events: &events)
			return
		}

		if let first = pendingVolumeDownTime, first + tuning.volumeDownResolveWindow <= deadline {
			// No follow-up: it was a single Camera tap.
			pendingVolumeDownTime = nil
			tap(.camera, at: first + tuning.volumeDownResolveWindow)
		}
	}

	private mutating func emit(_ event: S29RingEvent, events: inout [S29RingEvent]) {
		if event.pressed {
			guard pressedControls.insert(event.control).inserted else { return }
		} else {
			guard pressedControls.remove(event.control) != nil else { return }
		}
		events.append(event)
	}
}
