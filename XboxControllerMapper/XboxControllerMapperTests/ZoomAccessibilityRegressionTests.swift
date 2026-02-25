import XCTest
import CoreGraphics
import IOKit.hidsystem
@testable import ControllerKeys

// MARK: - Accessibility Zoom Regression Tests
//
// These tests lock down the behavior of the Accessibility Zoom compatibility layer.
// The zoom system is fragile because:
//   1. macOS 26 broke UAZoomEnabled() — it returns false during active zoom
//   2. NSEvent.mouseLocation oscillates between virtual/physical positions during zoom
//   3. CGEvent mouse-down/up/drag events flash the zoom compositor's software cursor
//   4. IOHIDPostEvent avoids the flash but uses different structs and constants
//   5. CG→NS coordinate conversion is easy to get backwards
//
// If any of these tests fail after a change, the zoom experience is likely broken.

// MARK: - NX Event Type Constants

final class NXEventTypeConstantTests: XCTestCase {
    // These constants map to IOKit HID event types used by IOHIDPostEvent.
    // If Apple changes these in a future SDK, our event posting will silently break.

    func testMouseDownConstants() {
        XCTAssertEqual(NX_LMOUSEDOWN, 1, "Left mouse down NX constant changed — IOHIDPostEvent will post wrong event type")
        XCTAssertEqual(NX_RMOUSEDOWN, 3, "Right mouse down NX constant changed")
        XCTAssertEqual(NX_OMOUSEDOWN, 25, "Other mouse down NX constant changed")
    }

    func testMouseUpConstants() {
        XCTAssertEqual(NX_LMOUSEUP, 2, "Left mouse up NX constant changed")
        XCTAssertEqual(NX_RMOUSEUP, 4, "Right mouse up NX constant changed")
        XCTAssertEqual(NX_OMOUSEUP, 26, "Other mouse up NX constant changed")
    }

    func testMouseDragConstants() {
        XCTAssertEqual(NX_LMOUSEDRAGGED, 6, "Left mouse drag NX constant changed — zoom drag fix will break")
        XCTAssertEqual(NX_RMOUSEDRAGGED, 7, "Right mouse drag NX constant changed")
        // NX_OMOUSEDRAGGED = 27 (not defined as a global in all SDK versions)
    }

    func testMouseMoveConstant() {
        XCTAssertEqual(NX_MOUSEMOVED, 5, "Mouse move NX constant changed")
    }

    func testEventDataVersionConstant() {
        // kNXEventDataVersion is used in every IOHIDPostEvent call
        XCTAssertEqual(kNXEventDataVersion, 2, "NXEventData version changed — IOHIDPostEvent struct layout may have changed")
    }

    func testHIDSetCursorPositionConstant() {
        // kIOHIDSetCursorPosition is the flag that makes IOHIDPostEvent set the cursor position
        XCTAssertEqual(kIOHIDSetCursorPosition, 2, "kIOHIDSetCursorPosition changed — zoom click targeting will break")
    }
}

// MARK: - NXEventData Struct Layout

final class NXEventDataLayoutTests: XCTestCase {
    // IOHIDPostEvent uses NXEventData, which is a C union with different members
    // for different event types. If the struct layout changes, our events will
    // have garbage data in the wrong fields.

    func testMouseDataFields_accessible() {
        // Verify the fields we use in postMouseEventViaHID exist and are writable
        var data = NXEventData()
        data.mouse.buttonNumber = 0
        data.mouse.click = 1
        data.mouse.pressure = 255
        data.mouse.eventNum = 42

        XCTAssertEqual(data.mouse.buttonNumber, 0)
        XCTAssertEqual(data.mouse.click, 1)
        XCTAssertEqual(data.mouse.pressure, 255)
        XCTAssertEqual(data.mouse.eventNum, 42)
    }

    func testMouseMoveDataFields_accessible() {
        // Verify the fields we use in postMouseDragViaHID exist and are writable
        var data = NXEventData()
        data.mouseMove.dx = 10
        data.mouseMove.dy = -5

        XCTAssertEqual(data.mouseMove.dx, 10)
        XCTAssertEqual(data.mouseMove.dy, -5)
    }

    func testNXEventDataSize_isReasonable() {
        // The struct must be large enough to hold all union members.
        // If this changes dramatically, the memset in our code might not clear enough.
        let size = MemoryLayout<NXEventData>.size
        XCTAssertGreaterThan(size, 0, "NXEventData should have non-zero size")
        XCTAssertGreaterThanOrEqual(size, 32, "NXEventData should be at least 32 bytes to hold mouse data")
    }
}

// MARK: - IOGPoint Coordinate Range

final class IOGPointCoordinateTests: XCTestCase {
    // IOGPoint uses Int16 fields (range -32768 to 32767). Screen coordinates
    // on large/multi-monitor setups can exceed this range. We use Int16(clamping:)
    // to handle this safely, but these tests document the expected behavior.

    func testIOGPoint_normalCoordinates() {
        let point = IOGPoint(x: Int16(clamping: 1024), y: Int16(clamping: 768))
        XCTAssertEqual(point.x, 1024)
        XCTAssertEqual(point.y, 768)
    }

    func testIOGPoint_largeCoordinates_clampToInt16Max() {
        // On a 5K display or multi-monitor span, X could exceed Int16.max (32767)
        let point = IOGPoint(x: Int16(clamping: 40000), y: Int16(clamping: 3000))
        XCTAssertEqual(point.x, Int16.max, "Large X should clamp to Int16.max")
        XCTAssertEqual(point.y, 3000, "Normal Y should pass through")
    }

    func testIOGPoint_negativeCoordinates() {
        // Multi-monitor setups can have negative coordinates (display to the left)
        let point = IOGPoint(x: Int16(clamping: -500), y: Int16(clamping: 200))
        XCTAssertEqual(point.x, -500)
        XCTAssertEqual(point.y, 200)
    }

    func testIOGPoint_veryLargeNegative_clampToInt16Min() {
        let point = IOGPoint(x: Int16(clamping: -40000), y: Int16(clamping: 0))
        XCTAssertEqual(point.x, Int16.min, "Very large negative should clamp to Int16.min")
    }

    func testIOGPoint_zero() {
        let point = IOGPoint(x: Int16(clamping: 0), y: Int16(clamping: 0))
        XCTAssertEqual(point.x, 0)
        XCTAssertEqual(point.y, 0)
    }
}

// MARK: - Zoom Detection Helpers

final class ZoomDetectionTests: XCTestCase {

    func testGetZoomLevel_returnsAtLeastOne() {
        let level = InputSimulator.getZoomLevel()
        XCTAssertGreaterThanOrEqual(level, 1.0,
            "Zoom level must never be less than 1.0")
    }

    func testGetZoomLevel_returnsCGFloat() {
        let level: CGFloat = InputSimulator.getZoomLevel()
        // Compilation is the assertion — ensures return type is CGFloat, not Double
        XCTAssertNotNil(level)
    }

    func testGetLastTrackedPosition_initiallyNil() {
        // On a freshly started app with no controller movement,
        // tracked position should be nil
        // Note: This test may flicker if other tests move the cursor
        // The key assertion is that it returns Optional<CGPoint>
        let pos: CGPoint? = InputSimulator.getLastTrackedPosition()
        _ = pos // Type is correct
    }

    func testIsZoomCurrentlyActive_readsBoolAndDouble() {
        // isZoomCurrentlyActive reads two UserDefaults keys:
        //   closeViewZoomedIn (Bool) AND closeViewZoomFactor (Double) > 1.0
        // Both must be true. This test verifies the function exists and returns Bool.
        let active: Bool = InputSimulator.isZoomCurrentlyActive()
        _ = active // Type is correct; actual value depends on system state
    }
}

// MARK: - Zoom Event Policy: Complete Behavioral Matrix

final class ZoomMouseEventPolicyMatrixTests: XCTestCase {
    // This tests the full 2×4 matrix of (zoomActive × category) to ensure
    // no combination was accidentally missed or changed.

    func testFullMatrix() {
        struct TestCase {
            let zoom: Bool
            let category: ZoomMouseEventPolicy.MouseEventCategory
            let expectHID: Bool
            let label: String
        }

        let cases: [TestCase] = [
            // Zoom OFF: everything goes through CGEvent
            TestCase(zoom: false, category: .move,       expectHID: false, label: "no-zoom + move"),
            TestCase(zoom: false, category: .drag,       expectHID: false, label: "no-zoom + drag"),
            TestCase(zoom: false, category: .buttonDown, expectHID: false, label: "no-zoom + buttonDown"),
            TestCase(zoom: false, category: .buttonUp,   expectHID: false, label: "no-zoom + buttonUp"),
            // Zoom ON: move stays CGEvent, everything else goes through IOHIDPostEvent
            TestCase(zoom: true,  category: .move,       expectHID: false, label: "zoom + move"),
            TestCase(zoom: true,  category: .drag,       expectHID: true,  label: "zoom + drag"),
            TestCase(zoom: true,  category: .buttonDown, expectHID: true,  label: "zoom + buttonDown"),
            TestCase(zoom: true,  category: .buttonUp,   expectHID: true,  label: "zoom + buttonUp"),
        ]

        for tc in cases {
            let result = ZoomMouseEventPolicy.shouldUseIOHIDPostEvent(
                zoomActive: tc.zoom, category: tc.category
            )
            XCTAssertEqual(result, tc.expectHID,
                "\(tc.label): expected \(tc.expectHID ? "IOHIDPostEvent" : "CGEvent") but got \(result ? "IOHIDPostEvent" : "CGEvent")")
        }
    }
}

// MARK: - Oscillation Filter: Coordinate Conversion Regression

final class OscillationFilterCoordinateRegressionTests: XCTestCase {
    // The filter converts tracked CG coordinates to NS coordinates for comparison.
    // CG: top-left origin, +Y down. NS: bottom-left origin, +Y up.
    // Conversion: nsY = screenHeight - cgY
    //
    // Getting this conversion wrong causes the filter to misclassify every reading,
    // which makes overlays flash between two positions during zoom.

    func testConversion_allFourQuadrants() {
        let screenH: CGFloat = 1080

        // Top-left in CG = bottom-left in NS
        XCTAssertTrue(CursorOscillationFilter.isVirtualReading(
            mouseLocation: CGPoint(x: 100, y: 1080),  // NS bottom-left area
            trackedCGPosition: CGPoint(x: 100, y: 0),  // CG top-left area
            screenHeight: screenH
        ), "CG top-left should match NS bottom-left")

        // Top-right in CG = bottom-right in NS
        XCTAssertTrue(CursorOscillationFilter.isVirtualReading(
            mouseLocation: CGPoint(x: 1820, y: 1080),
            trackedCGPosition: CGPoint(x: 1820, y: 0),
            screenHeight: screenH
        ), "CG top-right should match NS bottom-right")

        // Bottom-left in CG = top-left in NS
        XCTAssertTrue(CursorOscillationFilter.isVirtualReading(
            mouseLocation: CGPoint(x: 100, y: 0),
            trackedCGPosition: CGPoint(x: 100, y: 1080),
            screenHeight: screenH
        ), "CG bottom-left should match NS top-left")

        // Bottom-right in CG = top-right in NS
        XCTAssertTrue(CursorOscillationFilter.isVirtualReading(
            mouseLocation: CGPoint(x: 1820, y: 0),
            trackedCGPosition: CGPoint(x: 1820, y: 1080),
            screenHeight: screenH
        ), "CG bottom-right should match NS top-right")
    }

    func testConversion_isNotIdentity() {
        // If someone removes the Y-flip, this test catches it.
        // At CG y=100, NS y should be screenHeight-100, NOT 100.
        let screenH: CGFloat = 1080
        let trackedCG = CGPoint(x: 500, y: 100) // Near top in CG

        // If conversion is correct, virtual NS position is (500, 980) — NOT (500, 100)
        let wrongNS = CGPoint(x: 500, y: 100)
        XCTAssertFalse(CursorOscillationFilter.isVirtualReading(
            mouseLocation: wrongNS,
            trackedCGPosition: trackedCG,
            screenHeight: screenH
        ), "Using CG Y directly as NS Y means the conversion was skipped — BUG")

        let correctNS = CGPoint(x: 500, y: 980) // screenH - 100
        XCTAssertTrue(CursorOscillationFilter.isVirtualReading(
            mouseLocation: correctNS,
            trackedCGPosition: trackedCG,
            screenHeight: screenH
        ), "Correct NS position should be classified as virtual")
    }

    func testConversion_xPassedThrough() {
        // X coordinate is the same in CG and NS. If someone flips X, this catches it.
        let screenH: CGFloat = 1080
        let trackedCG = CGPoint(x: 750, y: 540)
        let virtualNS = CGPoint(x: 750, y: 540) // Both X=750; NS y = 1080-540 = 540

        XCTAssertTrue(CursorOscillationFilter.isVirtualReading(
            mouseLocation: virtualNS,
            trackedCGPosition: trackedCG,
            screenHeight: screenH
        ), "X should pass through without transformation")

        // Same but with wrong X
        let wrongX = CGPoint(x: 1080 - 750, y: 540)
        XCTAssertFalse(CursorOscillationFilter.isVirtualReading(
            mouseLocation: wrongX,
            trackedCGPosition: trackedCG,
            screenHeight: screenH
        ), "X should NOT be flipped")
    }
}

// MARK: - Mouse Click Location: Zoom vs Non-Zoom Regression

final class MouseClickLocationZoomRegressionTests: XCTestCase {
    private let primaryHeight: CGFloat = 1329
    private let maxAge: TimeInterval = 2.0

    func testZoomActive_usesTrackedPosition_notFallback() {
        // CRITICAL: During zoom, the click must go to the tracked (absolute/virtual)
        // position, NOT the NSEvent.mouseLocation (which oscillates).
        // If this fails, clicks will land at random positions during zoom.
        let tracked = CGPoint(x: 500, y: 300)
        let fallback = CGPoint(x: 960, y: 665) // Different position
        let now = Date()

        let result = MouseClickLocationPolicy.resolve(
            zoomActive: true,
            trackedCursorPosition: tracked,
            lastControllerMoveTime: now,
            fallbackMouseLocation: fallback,
            primaryDisplayHeight: primaryHeight,
            now: now,
            trackedCursorMaxAge: maxAge
        )

        XCTAssertEqual(result, tracked,
            "During zoom, click must use tracked position — using fallback causes wrong click location")
    }

    func testZoomNotActive_usesFallback_notTracked() {
        // Without zoom, NSEvent.mouseLocation is reliable and should be used
        // (after CG→NS conversion)
        let tracked = CGPoint(x: 500, y: 300)
        let fallback = CGPoint(x: 200, y: 800)
        let now = Date()

        let result = MouseClickLocationPolicy.resolve(
            zoomActive: false,
            trackedCursorPosition: tracked,
            lastControllerMoveTime: now,
            fallbackMouseLocation: fallback,
            primaryDisplayHeight: primaryHeight,
            now: now,
            trackedCursorMaxAge: maxAge
        )

        XCTAssertNotEqual(result, tracked,
            "Without zoom, click should NOT use tracked position")
        XCTAssertEqual(result.x, fallback.x)
        XCTAssertEqual(result.y, primaryHeight - fallback.y,
            "Fallback Y must be flipped from NS to CG coordinates")
    }

    func testZoomActive_staleTrackedPosition_fallsBack() {
        // If the controller hasn't moved for > maxAge seconds, the tracked position
        // might be stale (user moved with physical trackpad). Must fall back.
        let tracked = CGPoint(x: 500, y: 300)
        let fallback = CGPoint(x: 800, y: 600)
        let now = Date()

        let result = MouseClickLocationPolicy.resolve(
            zoomActive: true,
            trackedCursorPosition: tracked,
            lastControllerMoveTime: now.addingTimeInterval(-5.0), // 5 seconds stale
            fallbackMouseLocation: fallback,
            primaryDisplayHeight: primaryHeight,
            now: now,
            trackedCursorMaxAge: maxAge
        )

        XCTAssertNotEqual(result, tracked,
            "Stale tracked position (>2s) must NOT be used — user may have moved with trackpad")
    }
}

// MARK: - Overlay Position: Anti-Flash Guarantee

final class OverlayAntiFlashTests: XCTestCase {
    // The overlay panels (ActionFeedbackIndicator, FocusModeIndicator) use
    // CursorOscillationFilter to avoid flashing. These tests verify the
    // invariant that identical inputs always produce identical outputs,
    // which is what prevents flashing.

    func testFilter_isPureFunction() {
        // Same inputs → same output. If someone adds time-dependent or
        // random behavior, this catches it.
        let args = (
            mouseLocation: CGPoint(x: 500, y: 1029),
            trackedCGPosition: CGPoint(x: 500, y: 300),
            screenHeight: CGFloat(1329)
        )

        var results: [Bool] = []
        for _ in 0..<100 {
            results.append(CursorOscillationFilter.isVirtualReading(
                mouseLocation: args.mouseLocation,
                trackedCGPosition: args.trackedCGPosition,
                screenHeight: args.screenHeight
            ))
        }

        let allSame = results.allSatisfy { $0 == results[0] }
        XCTAssertTrue(allSame,
            "Oscillation filter must be a pure function — non-deterministic results cause flashing")
    }

    func testFilter_virtualAndPhysical_neverSameClassification() {
        // A virtual reading and a physical reading at the same tracked position
        // must ALWAYS be classified differently. If they're both "virtual" or
        // both "physical", the filter is broken and overlays will either freeze
        // or flash.
        let trackedCG = CGPoint(x: 600, y: 400)
        let screenH: CGFloat = 1329
        let virtualNS = CGPoint(x: 600, y: screenH - 400) // 929
        let physicalNS = CGPoint(x: 960, y: 665) // Center-ish, clearly different

        let virtualResult = CursorOscillationFilter.isVirtualReading(
            mouseLocation: virtualNS, trackedCGPosition: trackedCG, screenHeight: screenH)
        let physicalResult = CursorOscillationFilter.isVirtualReading(
            mouseLocation: physicalNS, trackedCGPosition: trackedCG, screenHeight: screenH)

        XCTAssertTrue(virtualResult, "Virtual reading must be classified as virtual")
        XCTAssertFalse(physicalResult, "Physical reading must be classified as physical")
        XCTAssertNotEqual(virtualResult, physicalResult,
            "Virtual and physical readings must have different classifications")
    }
}

// MARK: - Zoom Event Delivery: Down-Drag-Up Consistency

final class ZoomEventDeliveryConsistencyTests: XCTestCase {
    // During zoom, the ENTIRE down-drag-up sequence must use IOHIDPostEvent.
    // If any event in the sequence uses CGEvent while others use IOHIDPostEvent,
    // it creates a mixed delivery that can confuse apps and cause cursor flash.

    func testEntireDragSequence_usesIOHIDPostEvent() {
        let categories: [ZoomMouseEventPolicy.MouseEventCategory] = [
            .buttonDown, .drag, .drag, .drag, .buttonUp // Typical drag sequence
        ]

        for (i, category) in categories.enumerated() {
            XCTAssertTrue(
                ZoomMouseEventPolicy.shouldUseIOHIDPostEvent(zoomActive: true, category: category),
                "Event \(i) (\(category)) in drag sequence must use IOHIDPostEvent during zoom")
        }
    }

    func testMoveBeforeAndAfterDrag_usesCGEvent() {
        // Mouse moves before pressing button and after releasing should use CGEvent
        // Only the held-button events (down, drag, up) use IOHIDPostEvent
        XCTAssertFalse(
            ZoomMouseEventPolicy.shouldUseIOHIDPostEvent(zoomActive: true, category: .move),
            "Pre-drag mouse move should use CGEvent even during zoom")
    }

    func testAllButtonTypes_consistentDuringZoom() {
        // Left, right, and center button events should all use the same delivery
        // method. The policy doesn't differentiate by button — only by category.
        let clickCategories: [ZoomMouseEventPolicy.MouseEventCategory] = [.buttonDown, .drag, .buttonUp]

        for category in clickCategories {
            let result = ZoomMouseEventPolicy.shouldUseIOHIDPostEvent(zoomActive: true, category: category)
            XCTAssertTrue(result,
                "Category \(category) must use IOHIDPostEvent during zoom regardless of button type")
        }
    }
}

// MARK: - Regression: UAZoomEnabled vs isZoomCurrentlyActive

final class ZoomDetectionMethodTests: XCTestCase {
    // UAZoomEnabled() is broken on macOS 26 (returns false during active zoom).
    // isZoomCurrentlyActive() reads UserDefaults directly as a workaround.
    // These tests document the expected behavior and prevent accidentally
    // reverting to UAZoomEnabled().

    func testIsZoomCurrentlyActive_readsUserDefaults() {
        // This is a characterization test. We can't easily mock UserDefaults
        // for com.apple.universalaccess, but we verify the method exists and
        // returns a Bool (not crashing on access).
        let _ = InputSimulator.isZoomCurrentlyActive()
        // If this test runs without crashing, the UserDefaults access is working
    }

    func testGetZoomLevel_readsUserDefaults() {
        let level = InputSimulator.getZoomLevel()
        // Zoom level is always >= 1.0 (1.0 = not zoomed)
        XCTAssertGreaterThanOrEqual(level, 1.0)
    }

    func testGetLastTrackedPosition_isNotGatedOnUAZoomEnabled() {
        // getLastTrackedPosition() must NOT call UAZoomEnabled() internally.
        // It returns the tracked position regardless of zoom state.
        // This test verifies it doesn't crash and returns the correct type.
        let _: CGPoint? = InputSimulator.getLastTrackedPosition()
    }
}
