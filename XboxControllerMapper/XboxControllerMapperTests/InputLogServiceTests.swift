import XCTest
import Combine
import CoreGraphics
import Carbon.HIToolbox
import SwiftUI
import AppKit
@testable import ControllerKeys

/// InputLogService logging of presses, chords, double taps, long presses, and entry limits.
/// Split from the original XboxControllerMapperTests.swift monolith.
final class InputLogServiceTests: MappingEngineTestCase {

    // MARK: - Input Log Service Tests

    /// Tests that InputLogService logs button presses correctly
    func testInputLogServiceLogsButtonPress() async throws {
        let logService = InputLogService()

        await MainActor.run {
            logService.log(buttons: [.a], type: .singlePress, action: "Key: A")
        }

        // Wait for batching delay (50ms) + buffer
        try? await Task.sleep(nanoseconds: 100_000_000)

        await MainActor.run {
            XCTAssertEqual(logService.entries.count, 1, "Should have one entry")
            XCTAssertEqual(logService.entries.first?.buttons, [.a])
            XCTAssertEqual(logService.entries.first?.type, .singlePress)
            XCTAssertEqual(logService.entries.first?.actionDescription, "Key: A")
        }
    }

    /// Tests that InputLogService limits entries to 8
    func testInputLogServiceLimitsEntries() async throws {
        let logService = InputLogService()

        await MainActor.run {
            // Log 12 entries
            for i in 0..<12 {
                logService.log(buttons: [.a], type: .singlePress, action: "Event \(i)")
            }
        }

        // Wait for batching
        try? await Task.sleep(nanoseconds: 100_000_000)

        await MainActor.run {
            XCTAssertLessThanOrEqual(logService.entries.count, 8, "Should limit to 8 entries")
        }
    }

    /// Tests that InputLogService shows newest entries first
    func testInputLogServiceNewestFirst() async throws {
        let logService = InputLogService()

        await MainActor.run {
            logService.log(buttons: [.a], type: .singlePress, action: "First")
            logService.log(buttons: [.b], type: .singlePress, action: "Second")
            logService.log(buttons: [.x], type: .singlePress, action: "Third")
        }

        // Wait for batching
        try? await Task.sleep(nanoseconds: 100_000_000)

        await MainActor.run {
            XCTAssertEqual(logService.entries.first?.actionDescription, "Third", "Newest should be first")
            XCTAssertEqual(logService.entries.last?.actionDescription, "First", "Oldest should be last")
        }
    }

    /// Tests that InputLogService logs chord events
    func testInputLogServiceLogsChord() async throws {
        let logService = InputLogService()

        await MainActor.run {
            logService.log(buttons: [.a, .b], type: .chord, action: "Chord: A+B")
        }

        try? await Task.sleep(nanoseconds: 100_000_000)

        await MainActor.run {
            XCTAssertEqual(logService.entries.count, 1)
            XCTAssertEqual(logService.entries.first?.buttons, [.a, .b])
            XCTAssertEqual(logService.entries.first?.type, .chord)
        }
    }

    /// Tests that InputLogService logs double-tap events
    func testInputLogServiceLogsDoubleTap() async throws {
        let logService = InputLogService()

        await MainActor.run {
            logService.log(buttons: [.a], type: .doubleTap, action: "Double Tap: A")
        }

        try? await Task.sleep(nanoseconds: 100_000_000)

        await MainActor.run {
            XCTAssertEqual(logService.entries.first?.type, .doubleTap)
        }
    }

    /// Tests that InputLogService logs long-press events
    func testInputLogServiceLogsLongPress() async throws {
        let logService = InputLogService()

        await MainActor.run {
            logService.log(buttons: [.a], type: .longPress, action: "Long Press: A")
        }

        try? await Task.sleep(nanoseconds: 100_000_000)

        await MainActor.run {
            XCTAssertEqual(logService.entries.first?.type, .longPress)
        }
    }

    /// Tests that InputLogService cleans up old entries
    func testInputLogServiceCleansUpOldEntries() async throws {
        let logService = InputLogService()

        await MainActor.run {
            logService.log(buttons: [.a], type: .singlePress, action: "Old entry")
        }

        // Wait for batching
        try? await Task.sleep(nanoseconds: 100_000_000)

        await MainActor.run {
            XCTAssertEqual(logService.entries.count, 1)
        }

        // Wait for retention period (3 seconds) + cleanup interval (0.5s) + buffer
        try? await Task.sleep(nanoseconds: 4_000_000_000)

        await MainActor.run {
            XCTAssertEqual(logService.entries.count, 0, "Entry should be cleaned up after retention period")
        }
    }

}
