import XCTest
import CoreFoundation
@testable import ControllerKeys

// =============================================================================
// Benchmark: Date() vs CFAbsoluteTimeGetCurrent()
//
// Date() allocates on the heap (class type, reference counted).
// CFAbsoluteTimeGetCurrent() returns a Double on the stack.
//
// In the button press path, Date() was called on every press and release
// for double-tap timing. At rapid input rates this creates allocation pressure.
// =============================================================================

final class DateVsCFAbsoluteTimeBenchmarkTests: XCTestCase {

    // --- Raw timestamp acquisition ---

    func testBenchmark_timestamp_OLD_Date() {
        measure {
            for _ in 0..<1_000_000 {
                let now = Date()
                _ = now
            }
        }
    }

    func testBenchmark_timestamp_NEW_CFAbsoluteTime() {
        measure {
            for _ in 0..<1_000_000 {
                let now = CFAbsoluteTimeGetCurrent()
                _ = now
            }
        }
    }

    // --- Timestamp comparison (the actual hot-path pattern) ---

    func testBenchmark_comparison_OLD_DateTimeIntervalSince() {
        let baseline = Date()
        measure {
            for _ in 0..<1_000_000 {
                let now = Date()
                let elapsed = now.timeIntervalSince(baseline)
                _ = elapsed < 0.3
            }
        }
    }

    func testBenchmark_comparison_NEW_CFAbsoluteTimeSubtraction() {
        let baseline = CFAbsoluteTimeGetCurrent()
        measure {
            for _ in 0..<1_000_000 {
                let now = CFAbsoluteTimeGetCurrent()
                let elapsed = now - baseline
                _ = elapsed < 0.3
            }
        }
    }

    // --- Dictionary write pattern (simulates lastTapTime[button] = now) ---

    func testBenchmark_dictWrite_OLD_Date() {
        var dict: [ControllerButton: Date] = [:]
        let buttons: [ControllerButton] = [.a, .b, .x, .y, .leftBumper, .rightBumper, .dpadUp, .dpadDown]
        measure {
            for i in 0..<1_000_000 {
                dict[buttons[i % buttons.count]] = Date()
            }
        }
    }

    func testBenchmark_dictWrite_NEW_CFAbsoluteTime() {
        var dict: [ControllerButton: CFAbsoluteTime] = [:]
        let buttons: [ControllerButton] = [.a, .b, .x, .y, .leftBumper, .rightBumper, .dpadUp, .dpadDown]
        measure {
            for i in 0..<1_000_000 {
                dict[buttons[i % buttons.count]] = CFAbsoluteTimeGetCurrent()
            }
        }
    }
}
