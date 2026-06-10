import Foundation
import GameController

struct ControllerBatteryReading {
	let level: Float
	let state: GCDeviceBattery.State
}

enum ControllerBatteryDisplayPolicy {
	static func isKnown(level: Float, state: GCDeviceBattery.State) -> Bool {
		guard level >= 0, level <= 1.0 else { return false }
		return !(level == 0 && state == .unknown)
	}

	static func percentage(level: Float, state: GCDeviceBattery.State) -> Int? {
		guard isKnown(level: level, state: state) else { return nil }
		return Int((level * 100).rounded())
	}
}

enum ControllerBatteryReadingResolver {
	static func resolve(
		prefersBluetoothBattery: Bool,
		bluetoothLevel: Int?,
		bluetoothIsCharging: Bool,
		controllerBatteryLevel: Float?,
		controllerBatteryState: GCDeviceBattery.State?
	) -> ControllerBatteryReading? {
		if prefersBluetoothBattery {
			guard let bluetoothLevel else { return nil }
			let clampedLevel = min(100, max(0, bluetoothLevel))
			return ControllerBatteryReading(
				level: Float(clampedLevel) / 100.0,
				state: bluetoothIsCharging ? .charging : .discharging
			)
		}

		guard let controllerBatteryLevel,
			  let controllerBatteryState,
			  ControllerBatteryDisplayPolicy.isKnown(
				  level: controllerBatteryLevel,
				  state: controllerBatteryState
			  ) else {
			return nil
		}

		return ControllerBatteryReading(
			level: controllerBatteryLevel,
			state: controllerBatteryState
		)
	}
}
