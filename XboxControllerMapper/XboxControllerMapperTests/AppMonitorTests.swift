import XCTest
import AppKit
@testable import ControllerKeys

@MainActor
final class AppMonitorTests: XCTestCase {
    func testAppInfo_HashAndEqualityUseBundleIdentifier() {
        let icon = NSImage(size: NSSize(width: 16, height: 16))
        let first = AppInfo(bundleIdentifier: "com.example.app", name: "One", icon: icon)
        let second = AppInfo(bundleIdentifier: "com.example.app", name: "Two", icon: nil)
        let third = AppInfo(bundleIdentifier: "com.example.other", name: "One", icon: icon)

        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, third)

        var set = Set<AppInfo>()
        set.insert(first)
        set.insert(second)
        set.insert(third)
        XCTAssertEqual(set.count, 2)
    }
}
