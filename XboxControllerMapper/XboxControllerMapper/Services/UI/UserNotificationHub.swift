import Foundation
import UserNotifications

/// Single owner of the app's UNUserNotificationCenter surface.
///
/// Three features post notifications (trial lifecycle, controller battery,
/// webhook feedback), but the center has exactly one delegate and one
/// authorization state — so both live here, not in any feature:
/// - `post(...)` is the shared authorization-aware posting flow. Callers with
///   one-shot semantics get a `PostOutcome` so they only mark an event
///   delivered when it actually posted.
/// - `willPresent` matches the system's no-delegate default (banner + sound +
///   list) for every notification, so claiming the delegate for click routing
///   doesn't silently mute other features' foreground delivery.
/// - Click handlers register per identifier prefix; `didReceive` dispatches to
///   the first matching handler.
@MainActor
final class UserNotificationHub: NSObject {
	static let shared = UserNotificationHub()

	private var clickHandlers: [(prefix: String, handler: (String) -> Void)] = []

	/// Must run before the app finishes launching so a notification click that
	/// cold-launches the app is still delivered to the delegate.
	func attach() {
		UNUserNotificationCenter.current().delegate = self
	}

	/// Routes clicks on notifications whose identifier starts with `prefix`.
	func onClick(identifierPrefix: String, handler: @escaping (String) -> Void) {
		clickHandlers.append((identifierPrefix, handler))
	}

	enum PostOutcome {
		case posted
		/// Authorization is denied or the consent prompt hasn't been answered;
		/// nothing was delivered. One-shot callers must NOT mark the event
		/// delivered — retrying after the user grants permission is the point.
		case notAuthorized
		case failed(Error)
	}

	/// Posts a notification, resolving authorization first:
	/// - authorized/provisional → posts immediately
	/// - notDetermined + `promptIfNeeded` → system consent dialog, post if granted
	/// - notDetermined without prompting, or denied → `.notAuthorized`
	///
	/// Pass `promptIfNeeded: false` when the call site can't attribute a
	/// consent dialog to a user action (e.g. a background timer at login);
	/// request consent from an attributed surface via
	/// `requestAuthorizationIfNeeded()` instead.
	func post(
		identifier: String,
		title: String,
		body: String,
		sound: UNNotificationSound? = .default,
		promptIfNeeded: Bool = true,
		completion: @escaping @MainActor (PostOutcome) -> Void = { _ in }
	) {
		UNUserNotificationCenter.current().getNotificationSettings { settings in
			Task { @MainActor in
				switch settings.authorizationStatus {
				case .authorized, .provisional:
					self.deliver(identifier: identifier, title: title, body: body, sound: sound, completion: completion)
				case .notDetermined where promptIfNeeded:
					self.requestAuthorization { granted in
						if granted {
							self.deliver(identifier: identifier, title: title, body: body, sound: sound, completion: completion)
						} else {
							completion(.notAuthorized)
						}
					}
				default:
					completion(.notAuthorized)
				}
			}
		}
	}

	/// Requests notification authorization at a user-attributable moment (the
	/// trial welcome sheet). Safe to call repeatedly — the system only shows
	/// the consent dialog while the status is `.notDetermined`.
	func requestAuthorizationIfNeeded() {
		UNUserNotificationCenter.current().getNotificationSettings { settings in
			guard settings.authorizationStatus == .notDetermined else { return }
			Task { @MainActor in
				self.requestAuthorization { _ in }
			}
		}
	}

	func removeDelivered(identifiers: [String]) {
		UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
	}

	private func requestAuthorization(completion: @escaping @MainActor (Bool) -> Void) {
		UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
			Task { @MainActor in completion(granted) }
		}
	}

	private func deliver(
		identifier: String,
		title: String,
		body: String,
		sound: UNNotificationSound?,
		completion: @escaping @MainActor (PostOutcome) -> Void
	) {
		let content = UNMutableNotificationContent()
		content.title = title
		content.body = body
		if let sound {
			content.sound = sound
		}
		let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
		UNUserNotificationCenter.current().add(request) { error in
			Task { @MainActor in
				if let error {
					NSLog("[UserNotificationHub] Failed to post \(identifier): \(error.localizedDescription)")
					completion(.failed(error))
				} else {
					completion(.posted)
				}
			}
		}
	}
}

extension UserNotificationHub: UNUserNotificationCenterDelegate {
	nonisolated func userNotificationCenter(
		_ center: UNUserNotificationCenter,
		willPresent notification: UNNotification,
		withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
	) {
		// The system's no-delegate default presents a foreground notification
		// with its original options; mirror that for everything so no feature
		// loses foreground banners or its Notification Center entry.
		completionHandler([.banner, .sound, .list])
	}

	nonisolated func userNotificationCenter(
		_ center: UNUserNotificationCenter,
		didReceive response: UNNotificationResponse,
		withCompletionHandler completionHandler: @escaping () -> Void
	) {
		let identifier = response.notification.request.identifier
		// Main-actor task: handler registration tasks are enqueued during app
		// init, before any post-launch click response can enqueue this one.
		Task { @MainActor in
			let hub = UserNotificationHub.shared
			if let entry = hub.clickHandlers.first(where: { identifier.hasPrefix($0.prefix) }) {
				entry.handler(identifier)
			}
		}
		completionHandler()
	}
}
