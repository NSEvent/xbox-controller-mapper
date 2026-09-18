import Foundation

extension Notification.Name {
	/// Posted by UI outside the main window to present the trial/license sheet.
	static let openLicensePrompt = Notification.Name("openLicensePrompt")
}

/// Bridges license-prompt requests from surfaces outside the main window
/// (menu bar, trial notifications), mirroring `SettingsUIRequest`.
///
/// The notification handles an already-open window. The pending surface handles
/// a newly-created window whose `ContentView` subscribes after the notification.
/// The surface string flows into paywall/checkout telemetry so each entry
/// point's conversion is separately measurable.
@MainActor
enum LicenseUIRequest {
	private(set) static var pendingSurface: String?

	static func request(
		surface: String,
		notificationCenter: NotificationCenter = .default,
		openWindow: () -> Void
	) {
		pendingSurface = surface
		openWindow()
		notificationCenter.post(name: .openLicensePrompt, object: nil)
	}

	static func consumePending() -> String? {
		defer { pendingSurface = nil }
		return pendingSurface
	}
}
