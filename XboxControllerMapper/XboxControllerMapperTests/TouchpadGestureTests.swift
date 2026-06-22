import XCTest
import Combine
import CoreGraphics
import Carbon.HIToolbox
import SwiftUI
import AppKit
@testable import ControllerKeys

/// DualSense touchpad tap and two-finger tap gesture mappings.
/// Split from the original XboxControllerMapperTests.swift monolith.
final class TouchpadGestureTests: MappingEngineTestCase {

    // MARK: - Touchpad Gesture Tests (High Priority - DualSense)

    /// Tests touchpad tap gesture callback
    func testTouchpadTapGesture() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "TouchTap", buttonMappings: [
                .touchpadTap: KeyMapping(keyCode: KeyCodeMapping.mouseLeftClick, isHoldModifier: true)
            ]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Simulate tap gesture callback
        await MainActor.run {
            controllerService.emitInputEvent(.touchpadTap)
        }
        await waitForTasks()

        await MainActor.run {
            let leftClickPresses = mockInputSimulator.events.filter { event in
                if case .pressKey(let keyCode, _) = event { return keyCode == KeyCodeMapping.mouseLeftClick }
                return false
            }.count
            let holdEvents = mockInputSimulator.events.contains { event in
                if case .startHoldMapping = event { return true }
                return false
            }

            XCTAssertEqual(leftClickPresses, 1, "Touchpad tap should emit one left click")
            XCTAssertFalse(holdEvents, "Touchpad tap should be a discrete click, not hold mapping")
        }
    }

    /// Tests touchpad two-finger tap (right click)
    func testTouchpadTwoFingerTap() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "TouchTwoFinger", buttonMappings: [
                .touchpadTwoFingerTap: KeyMapping(keyCode: KeyCodeMapping.mouseRightClick, isHoldModifier: true)
            ]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Simulate two-finger tap callback
        await MainActor.run {
            controllerService.emitInputEvent(.touchpadTwoFingerTap)
        }
        await waitForTasks()

        await MainActor.run {
            let rightClickPresses = mockInputSimulator.events.filter { event in
                if case .pressKey(let keyCode, _) = event { return keyCode == KeyCodeMapping.mouseRightClick }
                return false
            }.count
            let holdEvents = mockInputSimulator.events.contains { event in
                if case .startHoldMapping = event { return true }
                return false
            }

            XCTAssertEqual(rightClickPresses, 1, "Two-finger tap should emit one right click")
            XCTAssertFalse(holdEvents, "Two-finger tap should be a discrete click, not hold mapping")
        }
    }

}
