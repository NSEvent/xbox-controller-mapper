import XCTest
@testable import ControllerKeys

@MainActor
final class DS4LEDRecoveryTests: XCTestCase {
	private var pending: [(TimeInterval, @MainActor () -> Void)] = []

	private func recovery() -> DS4LEDRecovery {
		DS4LEDRecovery { [weak self] delay, action in
			self?.pending.append((delay, action))
		}
	}

	func testTransitionWritesAreDelayedAndBoundedEvenAfterSuccess() {
		let recovery = recovery()
		var attempts: [Int] = []
		recovery.start(settings: { DualSenseLEDSettings() }) { _, attempt in
			attempts.append(attempt)
		}
		XCTAssertTrue(attempts.isEmpty, "Do not race the immediate OS focus reset")
		XCTAssertEqual(pending.map(\.0), [0.1, 0.5, 1.5])
		for (_, fire) in pending { fire() }
		XCTAssertEqual(attempts, [1, 2, 3])
		XCTAssertEqual(pending.count, 3, "No perpetual retry/polling chain")
	}

	func testRetriesReadLatestLayerBrightnessAndLightOff() {
		let recovery = recovery()
		var current = DualSenseLEDSettings()
		current.lightBarColor = CodableColor(red: 1, green: 0, blue: 0)
		current.lightBarBrightness = .bright
		current.lightBarEnabled = true
		var colors: [[UInt8]] = []
		recovery.start(settings: { current }) { settings, _ in
			colors.append(Array(PlayStationLEDReports.dualShock4Bluetooth(settings: settings)[8...10]))
		}
		pending[0].1()
		current.lightBarColor = CodableColor(red: 0, green: 1, blue: 0)
		current.lightBarBrightness = .mid
		pending[1].1()
		current.lightBarEnabled = false
		pending[2].1()
		XCTAssertEqual(colors, [[255, 0, 0], [0, 128, 0], [0, 0, 0]])
	}

	func testLaterAttemptCanRecoverWhenSettingsBecomeReady() {
		let recovery = recovery()
		var current: DualSenseLEDSettings?
		var writes = 0
		recovery.start(settings: { current }) { _, _ in writes += 1 }
		pending[0].1()
		XCTAssertEqual(writes, 0)
		current = DualSenseLEDSettings()
		pending[1].1()
		XCTAssertEqual(writes, 1)
	}

	func testDisconnectOrForegroundCancellationStopsQueuedWrites() {
		let recovery = recovery()
		var reads = 0
		var writes = 0
		recovery.start(settings: { reads += 1; return DualSenseLEDSettings() }) { _, _ in writes += 1 }
		pending[0].1()
		recovery.cancel()
		pending[1].1()
		pending[2].1()
		XCTAssertEqual(reads, 1)
		XCTAssertEqual(writes, 1)
	}

	func testReconnectSupersedesOldConnectionAttempts() {
		let recovery = recovery()
		var oldWrites = 0
		var newWrites = 0
		recovery.start(settings: { DualSenseLEDSettings() }) { _, _ in oldWrites += 1 }
		recovery.start(settings: { DualSenseLEDSettings() }) { _, _ in newWrites += 1 }
		for (_, fire) in pending { fire() }
		XCTAssertEqual(oldWrites, 0)
		XCTAssertEqual(newWrites, 3)
	}

	func testTeardownDoesNotRetainRecoveryOrWrite() {
		var recovery: DS4LEDRecovery? = recovery()
		weak var weakRecovery = recovery
		var writes = 0
		recovery?.start(settings: { DualSenseLEDSettings() }) { _, _ in writes += 1 }
		recovery = nil
		for (_, fire) in pending { fire() }
		XCTAssertNil(weakRecovery)
		XCTAssertEqual(writes, 0)
	}
}
