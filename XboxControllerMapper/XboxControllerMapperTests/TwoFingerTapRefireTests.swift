import XCTest
@testable import ControllerKeys

/// Apple TV remote reports keep arriving with no primary finger after a lift.
/// A two-finger tap must fire once for the lift, not again on each empty report.
@MainActor
final class TwoFingerTapRefireTests: XCTestCase {
	private var controllerService: ControllerService!
	private final class EventLog: @unchecked Sendable {
		private let lock = NSLock()
		private var events: [ControllerInputEvent] = []
		func append(_ event: ControllerInputEvent) { lock.withLock { events.append(event) } }
		var twoFingerTapCount: Int {
			lock.withLock { events.filter { if case .touchpadTwoFingerTap = $0 { return true }; return false }.count }
		}
	}
	private let events = EventLog()

	override func setUp() async throws {
		try await super.setUp()
		controllerService = ControllerService(enableHardwareMonitoring: false)
		controllerService.storage.lock.withLock { controllerService.storage.isAppleTVRemote = true }
		let events = events
		controllerService.onInputEvent = { event in events.append(event) }
	}

	override func tearDown() async throws {
		controllerService?.onInputEvent = nil
		controllerService?.cleanup()
		controllerService = nil
		try await super.tearDown()
	}

	private var twoFingerTapCount: Int { events.twoFingerTapCount }

	private func report(primary: CGPoint?, secondary: CGPoint?) {
		if let primary {
			controllerService.updateTouchpad(x: Float(primary.x), y: Float(primary.y), isTouching: true)
		} else {
			controllerService.updateTouchpad(x: 0, y: 0, isTouching: false)
		}
		if let secondary {
			controllerService.updateTouchpadSecondary(x: Float(secondary.x), y: Float(secondary.y), isTouching: true)
		} else {
			controllerService.updateTouchpadSecondary(x: 0, y: 0, isTouching: false)
		}
	}

	func testTwoFingerTapFiresOnceAcrossEmptyReports() {
		report(primary: CGPoint(x: 0.1, y: 0.1), secondary: CGPoint(x: 0.3, y: 0.3))
		report(primary: CGPoint(x: 0.1, y: 0.1), secondary: CGPoint(x: 0.3, y: 0.3))
		report(primary: nil, secondary: nil)
		XCTAssertEqual(twoFingerTapCount, 1)

		report(primary: nil, secondary: nil)
		report(primary: nil, secondary: nil)
		XCTAssertEqual(twoFingerTapCount, 1, "empty reports after the lift must not re-fire the tap")
	}
}
