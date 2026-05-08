import XCTest
import AppKit
@testable import ControllerKeys

/// Pins the window-classification filter that DockVisibilityController uses to
/// decide which `NSApp.windows` represent "the user is actively using the app's
/// UI" (and therefore the dock icon should be visible while the Hide Dock Icon
/// preference is on). The filter is the policy core; the rest of the controller
/// (notification observers, NSApp policy mutation) is integration glue and is
/// covered by manual testing.
@MainActor
final class DockVisibilityControllerTests: XCTestCase {

    // MARK: - Included: titled NSWindow (user-facing main window)

    func testTitledNSWindowIsUserFacing() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        XCTAssertTrue(
            DockVisibilityController.isUserFacingAppWindow(window),
            "A titled NSWindow is the canonical 'user-facing' app window"
        )
    }

    // MARK: - Excluded: NSPanel

    func testNSPanelIsNotUserFacing() {
        // The MenuBarExtra popover and system panels (color picker, alerts) are
        // NSPanels. They must not promote the dock icon — otherwise opening the
        // menu bar popover would unexpectedly bring back the dock icon while
        // Hide Dock is enabled.
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        XCTAssertFalse(
            DockVisibilityController.isUserFacingAppWindow(panel),
            "NSPanel must be excluded so menu bar popover doesn't toggle dock icon"
        )
    }

    // MARK: - Excluded: untitled helper windows

    func testUntitledNSWindowIsNotUserFacing() {
        // SwiftUI and AppKit create various untitled helper NSWindows
        // (tooltips, hidden hosting windows). Filter them out.
        let helper = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        XCTAssertFalse(
            DockVisibilityController.isUserFacingAppWindow(helper),
            "Borderless/untitled helper windows must not affect dock visibility"
        )
    }
}
