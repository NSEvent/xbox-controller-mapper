import XCTest
@testable import ControllerKeys

// =============================================================================
// Letter Area Cache Benchmark & Correctness Tests
//
// threadSafeLetterAreaScreenRect is called at least twice per 120Hz joystick
// tick from JoystickHandler.  The underlying computeLetterAreaInOverlay()
// involves scaling math and coordinate transforms that only need to be redone
// when the overlay frame or panel frame changes (user moves/resizes keyboard).
//
// These tests verify that caching eliminates redundant computation and that
// the cache is correctly invalidated when the inputs change.
// =============================================================================

// MARK: - Benchmark: Cached vs Uncached Letter Area Computation

final class LetterAreaCacheBenchmarkTests: XCTestCase {

    // Realistic overlay and panel frames (simulating a centered keyboard on a 1920x1080 screen)
    static let overlayFrame = CGRect(x: 20, y: 10, width: 1100, height: 380)
    static let panelFrame = CGRect(x: 410, y: 120, width: 1100, height: 400)

    /// OLD pattern: every read forces recomputation (dirty flag always set)
    /// Simulates pre-cache behavior where each threadSafeLetterAreaScreenRect call recomputed.
    @MainActor
    func testBenchmark_letterAreaScreenRect_OLD_uncached() {
        let manager = OnScreenKeyboardManager.shared
        manager.testSetFrames(
            overlayFrame: Self.overlayFrame,
            panelFrame: Self.panelFrame
        )

        measure {
            for _ in 0..<100_000 {
                // Force dirty on every iteration to simulate uncached behavior
                manager.testSetFrames(
                    overlayFrame: Self.overlayFrame,
                    panelFrame: Self.panelFrame
                )
                let result = manager.threadSafeLetterAreaScreenRect
                _ = result
            }
        }
    }

    /// NEW pattern: cached reads — first read computes, subsequent reads return cached value
    @MainActor
    func testBenchmark_letterAreaScreenRect_NEW_cached() {
        let manager = OnScreenKeyboardManager.shared
        manager.testSetFrames(
            overlayFrame: Self.overlayFrame,
            panelFrame: Self.panelFrame
        )
        // Warm the cache with first read
        _ = manager.threadSafeLetterAreaScreenRect

        measure {
            for _ in 0..<100_000 {
                let result = manager.threadSafeLetterAreaScreenRect
                _ = result
            }
        }
    }
}

// MARK: - Correctness: Letter Area Cache Invalidation

final class LetterAreaCacheCorrectnessTests: XCTestCase {

    static let overlayFrame = CGRect(x: 20, y: 10, width: 1100, height: 380)
    static let panelFrame = CGRect(x: 410, y: 120, width: 1100, height: 400)

    /// Initial read computes a correct (non-zero) value
    @MainActor
    func testInitialReadComputesCorrectValue() {
        let manager = OnScreenKeyboardManager.shared
        manager.testSetFrames(
            overlayFrame: Self.overlayFrame,
            panelFrame: Self.panelFrame
        )

        let rect = manager.threadSafeLetterAreaScreenRect
        XCTAssertFalse(rect.isEmpty, "Letter area should be non-empty after setting valid frames")
        XCTAssertGreaterThan(rect.width, 0)
        XCTAssertGreaterThan(rect.height, 0)
    }

    /// Subsequent reads return the same value without recomputation (cache is clean)
    @MainActor
    func testSubsequentReadsReturnCachedValue() {
        let manager = OnScreenKeyboardManager.shared
        manager.testSetFrames(
            overlayFrame: Self.overlayFrame,
            panelFrame: Self.panelFrame
        )

        let first = manager.threadSafeLetterAreaScreenRect
        XCTAssertFalse(manager.testLetterAreaCacheDirty, "Cache should be clean after first read")

        let second = manager.threadSafeLetterAreaScreenRect
        XCTAssertEqual(first, second, "Subsequent reads should return the same cached value")
    }

    /// After invalidation via updateKeyboardOverlayFrame, next read recomputes
    @MainActor
    func testCacheInvalidatedOnFrameChange() {
        let manager = OnScreenKeyboardManager.shared
        manager.testSetFrames(
            overlayFrame: Self.overlayFrame,
            panelFrame: Self.panelFrame
        )

        let original = manager.threadSafeLetterAreaScreenRect
        XCTAssertFalse(manager.testLetterAreaCacheDirty)

        // Change the overlay frame (simulates keyboard resize/move)
        let newOverlayFrame = CGRect(x: 30, y: 15, width: 900, height: 320)
        manager.testSetFrames(
            overlayFrame: newOverlayFrame,
            panelFrame: Self.panelFrame
        )
        XCTAssertTrue(manager.testLetterAreaCacheDirty, "Cache should be dirty after frame change")

        let recomputed = manager.threadSafeLetterAreaScreenRect
        XCTAssertNotEqual(original, recomputed, "Recomputed rect should differ after overlay frame change")
        XCTAssertFalse(manager.testLetterAreaCacheDirty, "Cache should be clean after recomputation")
    }

    /// Changing only the panel frame (window moved) also invalidates the cache
    @MainActor
    func testCacheInvalidatedOnPanelMove() {
        let manager = OnScreenKeyboardManager.shared
        manager.testSetFrames(
            overlayFrame: Self.overlayFrame,
            panelFrame: Self.panelFrame
        )

        let original = manager.threadSafeLetterAreaScreenRect

        // Move the panel (simulates user dragging the keyboard window)
        let newPanelFrame = CGRect(x: 600, y: 200, width: 1100, height: 400)
        manager.testSetFrames(
            overlayFrame: Self.overlayFrame,
            panelFrame: newPanelFrame
        )

        let recomputed = manager.threadSafeLetterAreaScreenRect
        XCTAssertNotEqual(original, recomputed, "Rect should change when panel moves")
    }

    /// Returns .zero when frames are not yet set
    @MainActor
    func testReturnsZeroForEmptyFrames() {
        let manager = OnScreenKeyboardManager.shared
        manager.testSetFrames(
            overlayFrame: .zero,
            panelFrame: .zero
        )

        let rect = manager.threadSafeLetterAreaScreenRect
        XCTAssertEqual(rect, .zero, "Should return .zero when frames are empty")
    }

    /// Cached value matches direct computation
    @MainActor
    func testCachedValueMatchesDirectComputation() {
        let manager = OnScreenKeyboardManager.shared
        manager.testSetFrames(
            overlayFrame: Self.overlayFrame,
            panelFrame: Self.panelFrame
        )

        let cached = manager.threadSafeLetterAreaScreenRect
        let direct = OnScreenKeyboardManager.testComputeLetterAreaScreenRect(
            overlayFrame: Self.overlayFrame,
            panelFrame: Self.panelFrame
        )
        XCTAssertEqual(cached, direct, "Cached value should exactly match direct computation")
    }
}
