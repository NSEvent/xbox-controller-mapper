import Foundation
import UserNotifications
import Combine
import GameController

/// Monitors controller battery level and sends macOS notifications at low thresholds
@MainActor
class BatteryNotificationManager {
	private var cancellables = Set<AnyCancellable>()
	private var policy = BatteryNotificationPolicy()

	func startMonitoring(controllerService: ControllerService) {
		controllerService.$batteryLevel
			.combineLatest(
				controllerService.$batteryState,
				controllerService.$isConnected,
				controllerService.$currentControllerIdentity
			)
			.receive(on: DispatchQueue.main)
			.sink { [weak self] update in
				let (level, state, isConnected, identity) = update
				self?.handleBatteryUpdate(
					level: level,
					state: state,
					isConnected: isConnected,
					identity: identity
				)
			}
			.store(in: &cancellables)
	}

	private func handleBatteryUpdate(
		level: Float,
		state: GCDeviceBattery.State,
		isConnected: Bool,
		identity: ControllerIdentity?
	) {
		guard let threshold = policy.thresholdToNotify(
			level: level,
			state: state,
			isConnected: isConnected,
			identity: identity
		), let percentage = ControllerBatteryDisplayPolicy.percentage(level: level, state: state) else {
			return
		}

		let isCritical = threshold <= 10
		sendNotification(
			title: isCritical ? "Controller Battery Critical" : "Controller Battery Low",
			body: isCritical
				? "Battery at \(percentage)%. Connect charger soon."
				: "Battery at \(percentage)%.",
			identifier: "controllerkeys-battery-\(threshold)"
		)
	}

    private func sendNotification(title: String, body: String, identifier: String) {
        UserNotificationHub.shared.post(identifier: identifier, title: title, body: body)
    }

	/// Explicitly clears the discharge-cycle state. Ordinary disconnects retain it
	/// so a controller reconnect at the same battery level cannot alert again.
	func reset() {
		policy.reset()
	}
}

/// Tracks the lowest low-battery threshold announced in the current discharge
/// cycle. Connection churn from the same physical controller deliberately does
/// not reset this state.
struct BatteryNotificationPolicy {
	static let thresholds = [20, 15, 10, 5]
	static let rechargeResetPercentage = 25

	private var activeControllerIdentity: ControllerIdentity?
	private var lowestNotifiedThreshold: Int?

	mutating func thresholdToNotify(
		level: Float,
		state: GCDeviceBattery.State,
		isConnected: Bool,
		identity: ControllerIdentity?
	) -> Int? {
		guard isConnected else { return nil }

		if let identity {
			if let activeControllerIdentity,
			   !activeControllerIdentity.matches(identity) {
				lowestNotifiedThreshold = nil
			}
			activeControllerIdentity = identity
		}

		guard let percentage = ControllerBatteryDisplayPolicy.percentage(
			level: level,
			state: state
		) else {
			return nil
		}

		if percentage > Self.rechargeResetPercentage {
			lowestNotifiedThreshold = nil
			return nil
		}

		guard let threshold = Self.thresholds.last(where: { percentage <= $0 }) else {
			return nil
		}
		guard lowestNotifiedThreshold.map({ threshold < $0 }) ?? true else {
			return nil
		}

		lowestNotifiedThreshold = threshold
		return threshold
	}

	mutating func reset() {
		activeControllerIdentity = nil
		lowestNotifiedThreshold = nil
	}
}
