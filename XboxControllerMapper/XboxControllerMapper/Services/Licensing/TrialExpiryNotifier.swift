import Foundation
import UserNotifications
import Combine

/// Decides which trial-lifecycle notification (if any) a license status change
/// warrants. Pure logic, separated for tests — mirrors
/// `BatteryNotificationPolicy`.
struct TrialExpiryNotificationPolicy {
	enum Event: String, CaseIterable {
		case lastDay = "controllerkeys-trial-last-day"
		case expired = "controllerkeys-trial-expired"
	}

	/// Each event fires at most once per install: the trial clock is anchored
	/// in the keychain and only moves forward, so a delivered marker never
	/// needs to reset.
	static func event(
		for status: LicenseManager.Status,
		lastDayDelivered: Bool,
		expiredDelivered: Bool
	) -> Event? {
		switch status {
		case .licensed:
			return nil
		case .trial(let daysRemaining):
			guard daysRemaining == 1, !lastDayDelivered else { return nil }
			return .lastDay
		case .expired:
			guard !expiredDelivered else { return nil }
			return .expired
		}
	}
}

/// Posts the two trial-lifecycle notifications — "last day" and "trial ended" —
/// and routes clicks on them to the in-app license sheet.
///
/// This exists for the menu-bar-resident install: without it, expiry manifests
/// as the controller silently going dead (the hourly `LicenseManager` refresh
/// forces mapping off with no window open), and the license sheet stays unseen
/// until a main-window open that may never come.
@MainActor
final class TrialExpiryNotifier: NSObject {
	static let shared = TrialExpiryNotifier()

	private enum DefaultsKey {
		static let lastDayDelivered = "trialNotifiedLastDay"
		static let expiredDelivered = "trialNotifiedExpired"
	}

	private var cancellable: AnyCancellable?
	private var hasRequestedPermission = false
	private let defaults = UserDefaults.standard

	/// Must run before the app finishes launching (Apple's contract for
	/// receiving the notification response that cold-launched the app).
	/// Separate from `start()` because that touches `LicenseManager`, whose
	/// keychain read is deliberately deferred out of app init.
	func attachNotificationDelegate() {
		// Delegate is required for clicks to reach us and for banners to show
		// while the app is frontmost. Nothing else in the app claims it.
		UNUserNotificationCenter.current().delegate = self
	}

	func start() {
		cancellable = LicenseManager.shared.$status.sink { [weak self] status in
			self?.handle(status: status)
		}
	}

	private func handle(status: LicenseManager.Status) {
		guard let event = TrialExpiryNotificationPolicy.event(
			for: status,
			lastDayDelivered: defaults.bool(forKey: DefaultsKey.lastDayDelivered),
			expiredDelivered: defaults.bool(forKey: DefaultsKey.expiredDelivered)
		) else { return }

		switch event {
		case .lastDay:
			defaults.set(true, forKey: DefaultsKey.lastDayDelivered)
		case .expired:
			defaults.set(true, forKey: DefaultsKey.expiredDelivered)
		}
		send(event)
	}

	private func send(_ event: TrialExpiryNotificationPolicy.Event) {
		if !hasRequestedPermission {
			hasRequestedPermission = true
			// No self capture: the completion runs off-main under @Sendable
			// checking, so hop to the singleton on the main actor instead.
			UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
				guard granted else { return }
				Task { @MainActor in TrialExpiryNotifier.shared.post(event) }
			}
		} else {
			post(event)
		}
	}

	private func post(_ event: TrialExpiryNotificationPolicy.Event) {
		let center = UNUserNotificationCenter.current()
		let content = UNMutableNotificationContent()
		switch event {
		case .lastDay:
			content.title = String(localized: "Last day of your ControllerKeys free trial")
			content.body = String(localized: "Controller mapping pauses when the trial ends. Buy or enter a license any time to keep everything working.")
		case .expired:
			content.title = String(localized: "Your ControllerKeys free trial has ended")
			content.body = String(localized: "Controller mapping is paused. Your profiles and settings are saved — enter a license to pick up where you left off.")
		}
		content.sound = .default

		let request = UNNotificationRequest(
			identifier: event.rawValue,
			content: content,
			trigger: nil
		)
		center.add(request) { error in
			if let error {
				NSLog("[TrialExpiryNotifier] Failed to send: \(error.localizedDescription)")
			}
		}
	}
}

extension TrialExpiryNotifier: UNUserNotificationCenterDelegate {
	nonisolated func userNotificationCenter(
		_ center: UNUserNotificationCenter,
		willPresent notification: UNNotification,
		withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
	) {
		// Trial notifications banner even while the app is frontmost; other app
		// notifications keep the pre-delegate default (hidden in foreground).
		let isTrialEvent = TrialExpiryNotificationPolicy.Event(
			rawValue: notification.request.identifier
		) != nil
		completionHandler(isTrialEvent ? [.banner, .sound] : [])
	}

	nonisolated func userNotificationCenter(
		_ center: UNUserNotificationCenter,
		didReceive response: UNNotificationResponse,
		withCompletionHandler completionHandler: @escaping () -> Void
	) {
		let identifier = response.notification.request.identifier
		if TrialExpiryNotificationPolicy.Event(rawValue: identifier) != nil {
			Task { @MainActor in
				LicenseUIRequest.request(surface: "expiry_notification") {
					MainWindowOpener.shared.open()
				}
			}
		}
		completionHandler()
	}
}
