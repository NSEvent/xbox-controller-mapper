import Foundation

/// A few writes after a lifecycle transition, not a permanent polling loop.
/// Successful IOHID delivery cannot tell us whether macOS subsequently overwrote
/// the light, so all three attempts run. Timings are a hardware-test hypothesis.
@MainActor
final class DS4LEDRecovery {
	typealias Schedule = (TimeInterval, @escaping @MainActor () -> Void) -> Void
	private let schedule: Schedule
	private var generation: UInt64 = 0

	init(schedule: @escaping Schedule = { delay, action in
		DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
	}) {
		self.schedule = schedule
	}

	func cancel() {
		generation &+= 1
	}

	func start(
		settings: @escaping @MainActor () -> DualSenseLEDSettings?,
		write: @escaping @MainActor (DualSenseLEDSettings, Int) -> Void
	) {
		cancel()
		let currentGeneration = generation
		for (index, delay) in [0.1, 0.5, 1.5].enumerated() {
			schedule(delay) { [weak self] in
				guard let self, self.generation == currentGeneration else { return }
				guard let currentSettings = settings() else { return }
				write(currentSettings, index + 1)
			}
		}
	}
}

@MainActor
extension ControllerService {
	/// Called after HID setup on every connection, and after backgrounding.
	/// Delays allow profile/layer setup and the OS focus transition to settle.
	/// Intentionally raw-only: don't reclaim framework light ownership here.
	func scheduleDS4LEDRecovery(reason: String) {
		guard Self.rawBluetoothLEDReportsNeeded,
			  threadSafeIsDualShock, threadSafeIsBluetoothConnection else { return }
		NSLog("[LED] DS4 recovery scheduled: %@", reason)
		ds4LEDRecovery.start(settings: { [weak self] in
			guard let self, self.connectedController != nil,
				  self.threadSafeIsDualShock, self.threadSafeIsBluetoothConnection else { return nil }
			guard self.hidDevice != nil,
				  let settings = self.storage.lock.withLock({ self.storage.currentLEDSettings }) else {
				NSLog("[LED] DS4 recovery %@ skipped: HID/settings not ready", reason)
				return nil
			}
			// Read on execution, not when scheduled: layers, brightness, light-off,
			// battery animations and profile switches may change during the delay.
			return settings
		}, write: { [weak self] settings, attempt in
			guard let self, let device = self.hidDevice else { return }
			let result = self.sendDualShock4BluetoothLEDReport(device: device, settings: settings)
			NSLog("[LED] DS4 recovery %@ attempt=%d result=0x%08X enabled=%d RGB=%d,%d,%d",
				  reason, attempt, result, settings.lightBarEnabled ? 1 : 0,
				  settings.lightBarColor.redByte, settings.lightBarColor.greenByte,
				  settings.lightBarColor.blueByte)
		})
	}
}
