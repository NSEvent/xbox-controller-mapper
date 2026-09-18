import AppKit

/// Lets AppKit-side code (notification clicks) open the SwiftUI main window.
///
/// SwiftUI's `openWindow` action only exists inside a view's environment, and
/// pure-AppKit reopening is unreliable once the window has left `NSApp.windows`
/// (see `MenuBarView.openMainWindow`). The menu-bar label is the one view alive
/// for the app's entire lifetime, so it donates the real action here at launch;
/// an `open()` arriving before registration (e.g. a notification click that
/// launches the app) is queued and replayed on registration.
@MainActor
final class MainWindowOpener {
	static let shared = MainWindowOpener()

	private var performer: (() -> Void)?
	private var pendingOpen = false

	func register(_ performer: @escaping () -> Void) {
		self.performer = performer
		if pendingOpen {
			pendingOpen = false
			performer()
		}
	}

	func open() {
		// Mirrors MenuBarView.openMainWindow: promote first so the dock-less
		// accessory app doesn't immediately demote the new window away.
		DockVisibilityController.shared.promoteForOpeningMainWindow()
		if let performer {
			performer()
		} else {
			pendingOpen = true
		}
		NSApp.activate(ignoringOtherApps: true)
	}
}
