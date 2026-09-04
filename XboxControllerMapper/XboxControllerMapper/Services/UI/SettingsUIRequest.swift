import Foundation

extension Notification.Name {
	/// Posted by UI outside the main window to present ControllerKeys settings.
	static let openSettingsSheet = Notification.Name("openSettingsSheet")
}

/// Bridges settings requests from surfaces outside the main window.
///
/// The notification handles an already-open window. The pending flag handles
/// a newly-created window whose `ContentView` subscribes after the notification.
@MainActor
enum SettingsUIRequest {
	private(set) static var pending = false

	static func request(
		notificationCenter: NotificationCenter = .default,
		openWindow: () -> Void
	) {
		pending = true
		openWindow()
		notificationCenter.post(name: .openSettingsSheet, object: nil)
	}

	@discardableResult
	static func consumePending() -> Bool {
		let wasPending = pending
		pending = false
		return wasPending
	}
}
