import XCTest
import CoreGraphics
@testable import ControllerKeys

final class CursorOscillationFilterTests: XCTestCase {

    // Screen height for a 14" MacBook Pro (2056×1329 retina → 1329 logical)
    private let screenHeight: CGFloat = 1329

    // MARK: - Virtual readings (should be filtered out)

    func testExactMatch_isVirtualReading() {
        // NSEvent.mouseLocation happens to exactly match the tracked position
        // (converted from CG to NS coords)
        let trackedCG = CGPoint(x: 500, y: 300)
        let mouseNS = CGPoint(x: 500, y: screenHeight - 300)

        XCTAssertTrue(
            CursorOscillationFilter.isVirtualReading(
                mouseLocation: mouseNS,
                trackedCGPosition: trackedCG,
                screenHeight: screenHeight
            ),
            "Exact match with tracked position should be classified as virtual")
    }

    func testNearMatch_withinTolerance_isVirtualReading() {
        let trackedCG = CGPoint(x: 500, y: 300)
        // Within 10pt tolerance
        let mouseNS = CGPoint(x: 505, y: screenHeight - 305)

        XCTAssertTrue(
            CursorOscillationFilter.isVirtualReading(
                mouseLocation: mouseNS,
                trackedCGPosition: trackedCG,
                screenHeight: screenHeight
            ),
            "Reading within tolerance of tracked position should be classified as virtual")
    }

    func testAtToleranceBoundary_X_isPhysicalReading() {
        let trackedCG = CGPoint(x: 500, y: 300)
        // Exactly at tolerance boundary (10pt) — should be physical (< not <=)
        let mouseNS = CGPoint(x: 510, y: screenHeight - 300)

        XCTAssertFalse(
            CursorOscillationFilter.isVirtualReading(
                mouseLocation: mouseNS,
                trackedCGPosition: trackedCG,
                screenHeight: screenHeight
            ),
            "Reading exactly at tolerance boundary should be classified as physical")
    }

    func testAtToleranceBoundary_Y_isPhysicalReading() {
        let trackedCG = CGPoint(x: 500, y: 300)
        let mouseNS = CGPoint(x: 500, y: screenHeight - 300 + 10)

        XCTAssertFalse(
            CursorOscillationFilter.isVirtualReading(
                mouseLocation: mouseNS,
                trackedCGPosition: trackedCG,
                screenHeight: screenHeight
            ),
            "Reading exactly at Y tolerance boundary should be classified as physical")
    }

    // MARK: - Physical readings (should be kept)

    func testFarFromTracked_isPhysicalReading() {
        // During 2× zoom, the physical position can be significantly different
        // from the virtual position
        let trackedCG = CGPoint(x: 500, y: 300)
        let mouseNS = CGPoint(x: 960, y: 540) // Physical center of screen

        XCTAssertFalse(
            CursorOscillationFilter.isVirtualReading(
                mouseLocation: mouseNS,
                trackedCGPosition: trackedCG,
                screenHeight: screenHeight
            ),
            "Reading far from tracked position should be classified as physical")
    }

    func testOnlyXDiverges_isPhysicalReading() {
        let trackedCG = CGPoint(x: 500, y: 300)
        // Y matches but X is far off
        let mouseNS = CGPoint(x: 800, y: screenHeight - 300)

        XCTAssertFalse(
            CursorOscillationFilter.isVirtualReading(
                mouseLocation: mouseNS,
                trackedCGPosition: trackedCG,
                screenHeight: screenHeight
            ),
            "Both X and Y must match for virtual classification")
    }

    func testOnlyYDiverges_isPhysicalReading() {
        let trackedCG = CGPoint(x: 500, y: 300)
        // X matches but Y is far off
        let mouseNS = CGPoint(x: 500, y: 200)

        XCTAssertFalse(
            CursorOscillationFilter.isVirtualReading(
                mouseLocation: mouseNS,
                trackedCGPosition: trackedCG,
                screenHeight: screenHeight
            ),
            "Both X and Y must match for virtual classification")
    }

    // MARK: - CG to NS coordinate conversion

    func testCoordinateConversion_topOfScreen() {
        // Tracked at CG top (y=0) → NS bottom (y=screenHeight)
        let trackedCG = CGPoint(x: 100, y: 0)
        let mouseNS = CGPoint(x: 100, y: screenHeight) // Matches virtual NS position

        XCTAssertTrue(
            CursorOscillationFilter.isVirtualReading(
                mouseLocation: mouseNS,
                trackedCGPosition: trackedCG,
                screenHeight: screenHeight
            ),
            "CG y=0 should convert to NS y=screenHeight for comparison")
    }

    func testCoordinateConversion_bottomOfScreen() {
        // Tracked at CG bottom (y=screenHeight) → NS top (y=0)
        let trackedCG = CGPoint(x: 100, y: screenHeight)
        let mouseNS = CGPoint(x: 100, y: 0)

        XCTAssertTrue(
            CursorOscillationFilter.isVirtualReading(
                mouseLocation: mouseNS,
                trackedCGPosition: trackedCG,
                screenHeight: screenHeight
            ),
            "CG y=screenHeight should convert to NS y=0 for comparison")
    }

    func testCoordinateConversion_center() {
        let center = screenHeight / 2
        let trackedCG = CGPoint(x: 500, y: center)
        let mouseNS = CGPoint(x: 500, y: center) // NS y = screenHeight - center = center

        XCTAssertTrue(
            CursorOscillationFilter.isVirtualReading(
                mouseLocation: mouseNS,
                trackedCGPosition: trackedCG,
                screenHeight: screenHeight
            ),
            "Screen center is the same in both CG and NS when screenHeight/2 is the Y")
    }

    // MARK: - Custom tolerance

    func testCustomTolerance_tighter() {
        let trackedCG = CGPoint(x: 500, y: 300)
        let mouseNS = CGPoint(x: 505, y: screenHeight - 305)

        // Within default tolerance (10) but outside custom tolerance (3)
        XCTAssertFalse(
            CursorOscillationFilter.isVirtualReading(
                mouseLocation: mouseNS,
                trackedCGPosition: trackedCG,
                screenHeight: screenHeight,
                tolerance: 3
            ),
            "Tighter tolerance should classify near-match as physical")
    }

    func testCustomTolerance_looser() {
        let trackedCG = CGPoint(x: 500, y: 300)
        let mouseNS = CGPoint(x: 515, y: screenHeight - 315)

        // Outside default tolerance (10) but within custom tolerance (20)
        XCTAssertTrue(
            CursorOscillationFilter.isVirtualReading(
                mouseLocation: mouseNS,
                trackedCGPosition: trackedCG,
                screenHeight: screenHeight,
                tolerance: 20
            ),
            "Looser tolerance should classify near-match as virtual")
    }

    // MARK: - Different screen sizes

    func testDifferentScreenHeight_1080() {
        let height: CGFloat = 1080
        let trackedCG = CGPoint(x: 400, y: 200)
        let mouseNS = CGPoint(x: 400, y: height - 200) // 880

        XCTAssertTrue(
            CursorOscillationFilter.isVirtualReading(
                mouseLocation: mouseNS,
                trackedCGPosition: trackedCG,
                screenHeight: height
            ))
    }

    func testDifferentScreenHeight_1440() {
        let height: CGFloat = 1440
        let trackedCG = CGPoint(x: 700, y: 500)
        let mouseNS = CGPoint(x: 700, y: height - 500) // 940

        XCTAssertTrue(
            CursorOscillationFilter.isVirtualReading(
                mouseLocation: mouseNS,
                trackedCGPosition: trackedCG,
                screenHeight: height
            ))
    }

    // MARK: - Edge cases

    func testTrackedAtOrigin() {
        let trackedCG = CGPoint(x: 0, y: 0)
        let mouseNS = CGPoint(x: 0, y: screenHeight)

        XCTAssertTrue(
            CursorOscillationFilter.isVirtualReading(
                mouseLocation: mouseNS,
                trackedCGPosition: trackedCG,
                screenHeight: screenHeight
            ),
            "Origin tracked position should work correctly")
    }

    func testNegativeDelta_withinTolerance() {
        let trackedCG = CGPoint(x: 500, y: 300)
        // mouseLocation slightly less than virtual position
        let mouseNS = CGPoint(x: 495, y: screenHeight - 295)

        XCTAssertTrue(
            CursorOscillationFilter.isVirtualReading(
                mouseLocation: mouseNS,
                trackedCGPosition: trackedCG,
                screenHeight: screenHeight
            ),
            "Negative delta within tolerance should be classified as virtual")
    }

    // MARK: - Alternating reads simulation

    func testAlternatingReads_virtualThenPhysical() {
        // Simulates the oscillation pattern observed during Accessibility Zoom:
        // Read 1: virtual (matches tracked position)
        // Read 2: physical (diverges from tracked position)
        let trackedCG = CGPoint(x: 500, y: 300)
        let virtualNS = CGPoint(x: 500, y: screenHeight - 300)
        let physicalNS = CGPoint(x: 800, y: 700) // Where cursor actually appears

        let read1 = CursorOscillationFilter.isVirtualReading(
            mouseLocation: virtualNS,
            trackedCGPosition: trackedCG,
            screenHeight: screenHeight
        )
        let read2 = CursorOscillationFilter.isVirtualReading(
            mouseLocation: physicalNS,
            trackedCGPosition: trackedCG,
            screenHeight: screenHeight
        )

        XCTAssertTrue(read1, "First read (virtual) should be identified as virtual")
        XCTAssertFalse(read2, "Second read (physical) should be identified as physical")
    }

    func testMultipleAlternatingReads_consistentClassification() {
        let trackedCG = CGPoint(x: 600, y: 400)
        let virtualNS = CGPoint(x: 600, y: screenHeight - 400)
        let physicalNS = CGPoint(x: 960, y: 665) // Physical display center-ish

        // Simulate 10 alternating reads
        for i in 0..<10 {
            let mouseLocation = (i % 2 == 0) ? virtualNS : physicalNS
            let expectedVirtual = (i % 2 == 0)

            let result = CursorOscillationFilter.isVirtualReading(
                mouseLocation: mouseLocation,
                trackedCGPosition: trackedCG,
                screenHeight: screenHeight
            )

            XCTAssertEqual(result, expectedVirtual,
                "Read \(i) should be classified as \(expectedVirtual ? "virtual" : "physical")")
        }
    }
}
