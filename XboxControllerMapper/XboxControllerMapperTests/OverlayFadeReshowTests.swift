import XCTest
@testable import ControllerKeys

/// Showing an overlay again while its fade-out is still running must leave it
/// on screen: the old fade's completion must not order the panel out.
@MainActor
final class OverlayFadeReshowTests: XCTestCase {
	override func tearDown() async throws {
		LaserPointerOverlay.shared.hide()
		CommandWheelManager.shared.hide()
		try await super.tearDown()
	}

	private func settle() async {
		// Longer than every overlay fade (≤ 0.18 s).
		try? await Task.sleep(nanoseconds: 400_000_000)
	}

	func testFadePanelReshownMidFadeStaysVisible() async {
		let fader = PanelFader()
		let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 4, height: 4), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
		defer { panel.orderOut(nil) }
		panel.orderFrontRegardless()

		fader.fadeOut(panel, duration: 0.15)
		fader.fadeIn(panel, duration: 0.15)
		await settle()
		XCTAssertTrue(panel.isVisible)

		fader.fadeOut(panel, duration: 0.15)
		await settle()
		XCTAssertFalse(panel.isVisible, "an uninterrupted fade-out still orders the panel out")
	}

	func testLaserPointerReshownMidFadeStaysVisible() async {
		let laser = LaserPointerOverlay.shared
		laser.show()
		laser.hide()
		laser.show()
		await settle()
		XCTAssertTrue(laser.isShowing)
		XCTAssertTrue(laser.isPanelOnScreenForTesting, "panel must match isShowing after a quick re-show")
	}

	func testCommandWheelReshownMidFadeStaysVisible() async {
		let wheel = CommandWheelManager.shared
		wheel.prepare(apps: [AppBarItem(bundleIdentifier: "com.apple.finder", displayName: "Finder")], websites: [], showWebsitesFirst: false)
		wheel.show()
		wheel.hide()
		wheel.prepare(apps: [AppBarItem(bundleIdentifier: "com.apple.finder", displayName: "Finder")], websites: [], showWebsitesFirst: false)
		wheel.show()
		await settle()
		XCTAssertTrue(wheel.isVisible)
		XCTAssertTrue(wheel.isPanelOnScreenForTesting, "panel must match isVisible after a quick re-show")
	}
}
