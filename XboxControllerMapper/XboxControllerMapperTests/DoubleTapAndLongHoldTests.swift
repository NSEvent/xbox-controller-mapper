import XCTest
import Combine
import CoreGraphics
import Carbon.HIToolbox
import SwiftUI
import AppKit
@testable import ControllerKeys

/// Double-tap and long-hold edge cases, macro variants, pending-tap interruption, and cancellation.
/// Split from the original XboxControllerMapperTests.swift monolith.
final class DoubleTapAndLongHoldTests: MappingEngineTestCase {

    // MARK: - Double-Tap Edge Cases

    /// Tests that a single tap followed by waiting longer than threshold executes single-tap action
    func testSingleTapAfterDoubleTapWindow() async throws {
        await MainActor.run {
            let doubleTap = DoubleTapMapping(keyCode: 2, threshold: 0.15)
            var aMapping = KeyMapping(keyCode: 1)
            aMapping.doubleTapMapping = doubleTap
            profileManager.setActiveProfile(Profile(name: "DT", buttonMappings: [.a: aMapping]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // First tap
        await MainActor.run {
            controllerService.onButtonPressed?(.a)
            controllerService.onButtonReleased?(.a, 0.05)
        }

        // Wait longer than double-tap threshold
        await waitForTasks(0.3)

        await MainActor.run {
            // Single tap should have executed (keyCode 1)
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 1 }
                return false
            }, "Single tap should execute after double-tap window expires")

            // Double-tap should NOT have executed
            XCTAssertFalse(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 2 }
                return false
            }, "Double-tap should not execute on single tap")
        }
    }

    /// Tests triple-tap behavior (third tap should start new double-tap detection)
    func testTripleTapBehavior() async throws {
        await MainActor.run {
            let doubleTap = DoubleTapMapping(keyCode: 2, threshold: 0.2)
            var aMapping = KeyMapping(keyCode: 1)
            aMapping.doubleTapMapping = doubleTap
            profileManager.setActiveProfile(Profile(name: "Triple", buttonMappings: [.a: aMapping]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // First tap
        await MainActor.run {
            controllerService.onButtonPressed?(.a)
            controllerService.onButtonReleased?(.a, 0.03)
        }
        await waitForTasks(0.05)

        // Second tap (double-tap)
        await MainActor.run {
            controllerService.onButtonPressed?(.a)
            controllerService.onButtonReleased?(.a, 0.03)
        }
        await waitForTasks(0.05)

        // Third tap (should start new sequence)
        await MainActor.run {
            controllerService.onButtonPressed?(.a)
            controllerService.onButtonReleased?(.a, 0.03)
        }
        await waitForTasks(0.3)

        await MainActor.run {
            // Should have one double-tap (keyCode 2) and one single-tap (keyCode 1)
            let doubleTapCount = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 2 }
                return false
            }.count

            XCTAssertEqual(doubleTapCount, 1, "Should have exactly one double-tap")
        }
    }

    // MARK: - Long-Hold Edge Cases

    /// Tests that releasing exactly at long-hold threshold triggers long-hold
    func testLongHoldExactThreshold() async throws {
        await MainActor.run {
            var aMapping = KeyMapping(keyCode: 1)
            aMapping.longHoldMapping = LongHoldMapping(keyCode: 2, threshold: 0.1)
            profileManager.setActiveProfile(Profile(name: "Exact", buttonMappings: [.a: aMapping]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.onButtonPressed?(.a)
        }

        // Wait exactly at threshold
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        await MainActor.run {
            // Release with hold duration exactly at threshold
            controllerService.onButtonReleased?(.a, 0.1)
        }
        await waitForTasks()

        await MainActor.run {
            // Long-hold should trigger (>= comparison)
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 2 }
                return false
            }, "Long-hold should trigger at exact threshold")
        }
    }

    /// Tests that releasing just before long-hold threshold triggers single-tap
    func testLongHoldJustBeforeThreshold() async throws {
        await MainActor.run {
            var aMapping = KeyMapping(keyCode: 1)
            aMapping.longHoldMapping = LongHoldMapping(keyCode: 2, threshold: 0.2)
            profileManager.setActiveProfile(Profile(name: "Before", buttonMappings: [.a: aMapping]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.onButtonPressed?(.a)
        }

        // Wait less than threshold
        try? await Task.sleep(nanoseconds: 50_000_000) // 0.05s

        await MainActor.run {
            controllerService.onButtonReleased?(.a, 0.05)
        }
        await waitForTasks()

        await MainActor.run {
            // Single tap should execute (keyCode 1)
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 1 }
                return false
            }, "Single tap should execute when released before threshold")

            // Long-hold should NOT execute
            XCTAssertFalse(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 2 }
                return false
            }, "Long-hold should not trigger before threshold")
        }
    }

    /// Tests long-hold timer fires while button still held (no release yet)
    func testLongHoldTimerFiresWhileHeld() async throws {
        await MainActor.run {
            var aMapping = KeyMapping(keyCode: 1)
            aMapping.longHoldMapping = LongHoldMapping(keyCode: 2, threshold: 0.1)
            profileManager.setActiveProfile(Profile(name: "Held", buttonMappings: [.a: aMapping]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.onButtonPressed?(.a)
        }

        // Wait for long-hold timer to fire (but don't release)
        await waitForTasks(0.3)

        await MainActor.run {
            // Long-hold should have executed
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 2 }
                return false
            }, "Long-hold should trigger while button still held")
        }

        // Now release
        await MainActor.run {
            controllerService.onButtonReleased?(.a, 0.3)
        }
        await waitForTasks()

        await MainActor.run {
            // Single tap should NOT execute after long-hold triggered
            XCTAssertFalse(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 1 }
                return false
            }, "Single tap should not execute after long-hold triggered")
        }
    }

    // MARK: - Double Tap with Macro Tests

    /// Tests double tap that triggers a macro
    func testDoubleTapWithMacro() async throws {
        let macroId = UUID()

        await MainActor.run {
            let macro = Macro(id: macroId, name: "DoubleTapMacro", steps: [
                .press(KeyMapping(keyCode: 10)),
                .press(KeyMapping(keyCode: 11))
            ])
            var profile = Profile(name: "DTMacro", buttonMappings: [:])
            profile.macros = [macro]
            var aMapping = KeyMapping(keyCode: 1)
            aMapping.doubleTapMapping = DoubleTapMapping(threshold: 0.2, macroId: macroId)
            profile.buttonMappings[.a] = aMapping
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Double tap
        await MainActor.run {
            controllerService.onButtonPressed?(.a)
            controllerService.onButtonReleased?(.a, 0.03)
        }
        await waitForTasks(0.05)

        await MainActor.run {
            controllerService.onButtonPressed?(.a)
            controllerService.onButtonReleased?(.a, 0.03)
        }
        await waitForTasks(0.3)

        await MainActor.run {
            let macroKeys = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 10 || code == 11 }
                return false
            }
            XCTAssertEqual(macroKeys.count, 2, "Double tap should trigger macro with 2 steps")
        }
    }

    // MARK: - Long Hold with Macro Tests

    /// Tests long hold that triggers a macro
    func testLongHoldWithMacro() async throws {
        let macroId = UUID()

        await MainActor.run {
            let macro = Macro(id: macroId, name: "LongHoldMacro", steps: [
                .press(KeyMapping(keyCode: 20))
            ])
            var profile = Profile(name: "LHMacro", buttonMappings: [:])
            profile.macros = [macro]
            var aMapping = KeyMapping(keyCode: 1)
            aMapping.longHoldMapping = LongHoldMapping(threshold: 0.1, macroId: macroId)
            profile.buttonMappings[.a] = aMapping
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.onButtonPressed?(.a)
        }

        // Wait for long hold to trigger
        await waitForTasks(0.3)

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(20, _) = event { return true }
                return false
            }, "Long hold should trigger macro")
        }
    }

    // MARK: - Button Press During Pending Double Tap

    /// Tests pressing a different button during double-tap window
    func testDifferentButtonDuringDoubleTapWindow() async throws {
        await MainActor.run {
            var aMapping = KeyMapping(keyCode: 1)
            aMapping.doubleTapMapping = DoubleTapMapping(keyCode: 2, threshold: 0.2)
            profileManager.setActiveProfile(Profile(name: "DTDiff", buttonMappings: [
                .a: aMapping,
                .b: .key(3)
            ]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // First tap of A
        await MainActor.run {
            controllerService.onButtonPressed?(.a)
            controllerService.onButtonReleased?(.a, 0.03)
        }
        await waitForTasks(0.05)

        // Press B during A's double-tap window
        await MainActor.run {
            controllerService.onButtonPressed?(.b)
            controllerService.onButtonReleased?(.b, 0.03)
        }
        await waitForTasks(0.3)

        await MainActor.run {
            // Both should execute their single-tap actions
            let hasA = mockInputSimulator.events.contains { event in
                if case .pressKey(1, _) = event { return true }
                return false
            }
            let hasB = mockInputSimulator.events.contains { event in
                if case .pressKey(3, _) = event { return true }
                return false
            }
            XCTAssertTrue(hasA, "Button A single tap should execute")
            XCTAssertTrue(hasB, "Button B should execute normally")
        }
    }

    // MARK: - Long Hold Cancel Tests

    /// Tests that releasing before threshold cancels long hold
    func testLongHoldCancelledByQuickRelease() async throws {
        await MainActor.run {
            var mapping = KeyMapping(keyCode: 1)
            mapping.longHoldMapping = LongHoldMapping(keyCode: 2, threshold: 0.5)
            profileManager.setActiveProfile(Profile(name: "LHCancel", buttonMappings: [.a: mapping]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.onButtonPressed?(.a)
        }

        // Release quickly (before 0.5s threshold)
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        await MainActor.run {
            controllerService.onButtonReleased?(.a, 0.1)
        }
        await waitForTasks()

        await MainActor.run {
            // Single tap should execute
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(1, _) = event { return true }
                return false
            }, "Single tap should execute")

            // Long hold should NOT execute
            XCTAssertFalse(mockInputSimulator.events.contains { event in
                if case .pressKey(2, _) = event { return true }
                return false
            }, "Long hold should NOT execute")
        }
    }

    // MARK: - Double Tap Cancel Tests

    /// Tests that slow second tap doesn't trigger double-tap
    func testDoubleTapCancelledBySlowSecondTap() async throws {
        await MainActor.run {
            var mapping = KeyMapping(keyCode: 1)
            mapping.doubleTapMapping = DoubleTapMapping(keyCode: 2, threshold: 0.2)
            profileManager.setActiveProfile(Profile(name: "DTCancel", buttonMappings: [.a: mapping]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // First tap
        await MainActor.run {
            controllerService.onButtonPressed?(.a)
            controllerService.onButtonReleased?(.a, 0.03)
        }

        // Wait longer than double-tap threshold
        await waitForTasks(0.3)

        // Second tap (too late)
        await MainActor.run {
            controllerService.onButtonPressed?(.a)
            controllerService.onButtonReleased?(.a, 0.03)
        }
        await waitForTasks(0.3)

        await MainActor.run {
            // Should have TWO single taps, no double tap
            let singleTaps = mockInputSimulator.events.filter { event in
                if case .pressKey(1, _) = event { return true }
                return false
            }.count

            let doubleTaps = mockInputSimulator.events.filter { event in
                if case .pressKey(2, _) = event { return true }
                return false
            }.count

            XCTAssertEqual(singleTaps, 2, "Should have two single taps")
            XCTAssertEqual(doubleTaps, 0, "Should have no double taps")
        }
    }

}
