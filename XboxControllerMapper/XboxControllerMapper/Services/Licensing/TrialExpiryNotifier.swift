import Foundation
import Combine

/// Decides which trial-lifecycle notification (if any) a license status change
/// warrants, and when a previously-latched delivery marker has gone stale.
/// Pure logic, separated for tests — mirrors `BatteryNotificationPolicy`.
struct TrialExpiryNotificationPolicy {
	enum Event: String, CaseIterable {
		case lastDay = "controllerkeys-trial-last-day"
		case expired = "controllerkeys-trial-expired"
	}

	/// All trial notification identifiers share this prefix; click routing
	/// dispatches on it.
	static let identifierPrefix = "controllerkeys-trial-"

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

	/// A delivered marker is only trustworthy while the status is at or past
	/// that marker's stage. A forward system-clock excursion can latch markers
	/// early; when the clock is corrected the status regresses, and the stale
	/// markers must clear so the real expiry still notifies.
	static func staleMarkers(
		for status: LicenseManager.Status,
		lastDayDelivered: Bool,
		expiredDelivered: Bool
	) -> Set<Event> {
		guard case .trial(let daysRemaining) = status else { return [] }
		var stale: Set<Event> = []
		if expiredDelivered { stale.insert(.expired) }
		if lastDayDelivered, daysRemaining > 1 { stale.insert(.lastDay) }
		return stale
	}
}

/// Posts the two trial-lifecycle notifications — "last day" and "trial ended" —
/// and routes clicks on them to the in-app license sheet.
///
/// This exists for the menu-bar-resident install: without it, expiry manifests
/// as the controller silently going dead (the hourly `LicenseManager` refresh
/// forces mapping off with no window open), and the license sheet stays unseen
/// until a main-window open that may never come.
///
/// Delivery rules:
/// - A marker is latched only when the hub confirms the post, so a denied or
///   not-yet-answered permission leaves the event pending and the hourly
///   refresh retries — re-enabling notifications in System Settings recovers it.
/// - This class never triggers the consent dialog itself (an hourly timer at
///   login is not an attributable moment); `TrialWelcomeSheet` requests
///   authorization when the user is actually looking at trial UI.
@MainActor
final class TrialExpiryNotifier {
	static let shared = TrialExpiryNotifier()

	private enum DefaultsKey {
		static let lastDayDelivered = "trialNotifiedLastDay"
		static let expiredDelivered = "trialNotifiedExpired"
	}

	private var cancellable: AnyCancellable?
	/// Events with a post in flight, so an hourly re-emit can't double-post
	/// while the async settings/add round-trip is pending.
	private var inFlight: Set<TrialExpiryNotificationPolicy.Event> = []
	private let defaults = UserDefaults.standard

	func start() {
		UserNotificationHub.shared.onClick(
			identifierPrefix: TrialExpiryNotificationPolicy.identifierPrefix
		) { _ in
			LicenseUIRequest.request(surface: "expiry_notification") {
				MainWindowOpener.shared.open()
			}
		}
		cancellable = LicenseManager.shared.$status.sink { [weak self] status in
			self?.handle(status: status)
		}
	}

	private func handle(status: LicenseManager.Status) {
		// `--demo-license` forces a synthetic status for demos/QA; never latch
		// or clear the real install's markers from a forced state.
		guard !LicenseManager.isDemoForced else { return }

		if case .licensed = status {
			// A stale "trial ended" notification shouldn't outlive activation.
			UserNotificationHub.shared.removeDelivered(
				identifiers: TrialExpiryNotificationPolicy.Event.allCases.map(\.rawValue)
			)
			return
		}

		for stale in TrialExpiryNotificationPolicy.staleMarkers(
			for: status,
			lastDayDelivered: defaults.bool(forKey: DefaultsKey.lastDayDelivered),
			expiredDelivered: defaults.bool(forKey: DefaultsKey.expiredDelivered)
		) {
			defaults.removeObject(forKey: markerKey(for: stale))
		}

		guard let event = TrialExpiryNotificationPolicy.event(
			for: status,
			lastDayDelivered: defaults.bool(forKey: DefaultsKey.lastDayDelivered),
			expiredDelivered: defaults.bool(forKey: DefaultsKey.expiredDelivered)
		), !inFlight.contains(event) else { return }

		inFlight.insert(event)
		let content = Self.content(for: event)
		UserNotificationHub.shared.post(
			identifier: event.rawValue,
			title: content.title,
			body: content.body,
			promptIfNeeded: false,
			completion: { [weak self] outcome in
				guard let self else { return }
				self.inFlight.remove(event)
				if case .posted = outcome {
					self.defaults.set(true, forKey: self.markerKey(for: event))
				}
			}
		)
	}

	private func markerKey(for event: TrialExpiryNotificationPolicy.Event) -> String {
		switch event {
		case .lastDay: return DefaultsKey.lastDayDelivered
		case .expired: return DefaultsKey.expiredDelivered
		}
	}

	private static func content(
		for event: TrialExpiryNotificationPolicy.Event
	) -> (title: String, body: String) {
		switch event {
		case .lastDay:
			return (
				String(localized: "Last day of your ControllerKeys free trial"),
				String(localized: "Controller mapping pauses when the trial ends. Buy or enter a license any time to keep everything working.")
			)
		case .expired:
			return (
				String(localized: "Your ControllerKeys free trial has ended"),
				String(localized: "Controller mapping is paused. Your profiles and settings are saved — enter a license to pick up where you left off.")
			)
		}
	}
}
