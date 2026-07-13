import XCTest
@testable import ControllerKeys

final class PointerLockMousePolicyTests: XCTestCase {

    private func decide(
        mode: PointerLockMouseMode,
        cursorVisible: Bool?,
        zoomActive: Bool = false,
        relayActive: Bool = false,
        appHide: Bool = false
    ) -> Bool {
        PointerLockMousePolicy.shouldUseRelativeMovement(
            mode: mode,
            cursorVisible: cursorVisible,
            zoomActive: zoomActive,
            universalControlRelayActive: relayActive,
            appInitiatedCursorHide: appHide
        )
    }

    // MARK: - Off mode

    func testOff_neverRelative_evenWhenCursorHidden() {
        XCTAssertFalse(decide(mode: .off, cursorVisible: false),
                       "Off mode must preserve legacy absolute behavior")
    }

    // MARK: - Always mode

    func testAlways_relative_regardlessOfCursorVisibility() {
        XCTAssertTrue(decide(mode: .always, cursorVisible: true))
        XCTAssertTrue(decide(mode: .always, cursorVisible: false))
        XCTAssertTrue(decide(mode: .always, cursorVisible: nil),
                      "Always must work even when visibility detection is unavailable")
    }

    func testAlways_notSuppressedByAppCursorHide() {
        XCTAssertTrue(decide(mode: .always, cursorVisible: false, appHide: true),
                      "The OSK guard is a heuristic guard for auto, not a semantic override for always")
    }

    // MARK: - Auto mode

    func testAuto_relative_whenCursorHidden() {
        XCTAssertTrue(decide(mode: .auto, cursorVisible: false),
                      "Pointer lock hides the cursor; auto must switch to relative")
    }

    func testAuto_absolute_whenCursorVisible() {
        XCTAssertFalse(decide(mode: .auto, cursorVisible: true))
    }

    func testAuto_absolute_whenDetectionUnavailable() {
        XCTAssertFalse(decide(mode: .auto, cursorVisible: nil),
                       "If CGCursorIsVisible stops resolving, auto degrades to absolute")
    }

    func testAuto_absolute_whenAppInitiatedCursorHide() {
        XCTAssertFalse(decide(mode: .auto, cursorVisible: false, appHide: true),
                       "OSK navigation mode hides the cursor; that must not read as pointer lock")
    }

    // MARK: - Zoom and Universal Control relay always win

    func testZoomActive_suppressesRelative_inAllModes() {
        for mode in PointerLockMouseMode.allCases {
            XCTAssertFalse(decide(mode: mode, cursorVisible: false, zoomActive: true),
                           "Accessibility Zoom needs the absolute path (mode: \(mode))")
        }
    }

    func testRelayActive_suppressesRelative_inAllModes() {
        for mode in PointerLockMouseMode.allCases {
            XCTAssertFalse(decide(mode: mode, cursorVisible: false, relayActive: true),
                           "Universal Control handoff needs the absolute path (mode: \(mode))")
        }
    }

    // MARK: - Visibility poll throttle

    func testVisibilityPoll_firstPollAlwaysRuns() {
        XCTAssertTrue(PointerLockMousePolicy.shouldRefreshCursorVisibility(now: 100, lastPoll: nil))
    }

    func testVisibilityPoll_throttledWithinInterval() {
        let interval = PointerLockMousePolicy.cursorVisibilityPollInterval
        XCTAssertFalse(PointerLockMousePolicy.shouldRefreshCursorVisibility(
            now: 100 + interval * 0.5, lastPoll: 100))
    }

    func testVisibilityPoll_runsAfterInterval() {
        let interval = PointerLockMousePolicy.cursorVisibilityPollInterval
        XCTAssertTrue(PointerLockMousePolicy.shouldRefreshCursorVisibility(
            now: 100 + interval, lastPoll: 100))
    }

    // MARK: - Cursor visibility detection (runtime dlsym contract)

    func testCursorVisibilityDetection_resolvesOnThisOS() {
        // CGCursorIsVisible is SDK-unavailable but runtime-exported (SkyLight
        // SLCursorIsVisible re-export). If this fails on a new macOS, auto-detection
        // is silently off and the release notes / UI copy need updating.
        XCTAssertTrue(CursorVisibility.isDetectionSupported)
        XCTAssertNotNil(CursorVisibility.isCursorVisible())
    }
}
