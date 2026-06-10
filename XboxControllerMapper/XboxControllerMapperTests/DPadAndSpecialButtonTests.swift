import XCTest
import Combine
import CoreGraphics
import Carbon.HIToolbox
import SwiftUI
import AppKit
@testable import ControllerKeys

/// D-pad, trigger-as-button, and special button (Xbox/Menu/View) mappings.
/// Split from the original XboxControllerMapperTests.swift monolith.
final class DPadAndSpecialButtonTests: MappingEngineTestCase {

    // MARK: - D-Pad Mapping Tests (High Priority)

    /// Tests all D-Pad directions are mapped correctly
    func testDPadMappings() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "DPad", buttonMappings: [
                .dpadUp: .key(KeyCodeMapping.upArrow),
                .dpadDown: .key(KeyCodeMapping.downArrow),
                .dpadLeft: .key(KeyCodeMapping.leftArrow),
                .dpadRight: .key(KeyCodeMapping.rightArrow)
            ]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Test each direction
        for (button, expectedKeyCode) in [
            (ControllerButton.dpadUp, KeyCodeMapping.upArrow),
            (ControllerButton.dpadDown, KeyCodeMapping.downArrow),
            (ControllerButton.dpadLeft, KeyCodeMapping.leftArrow),
            (ControllerButton.dpadRight, KeyCodeMapping.rightArrow)
        ] {
            await MainActor.run {
                controllerService.buttonPressed(button)
                controllerService.buttonReleased(button)
            }
            await waitForTasks()

            await MainActor.run {
                XCTAssertTrue(mockInputSimulator.events.contains { event in
                    switch event {
                    case .pressKey(let code, _):
                        return code == expectedKeyCode
                    case .startHoldMapping(let mapping):
                        return mapping.keyCode == expectedKeyCode
                    default:
                        return false
                    }
                }, "\(button) should map to arrow key \(expectedKeyCode)")
            }
        }
    }

    /// Tests D-Pad diagonal simulation (two directions at once)
    func testDPadDiagonal() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "DPadDiag", buttonMappings: [
                .dpadUp: .key(KeyCodeMapping.upArrow),
                .dpadRight: .key(KeyCodeMapping.rightArrow)
            ]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Press both up and right simultaneously
        await MainActor.run {
            controllerService.buttonPressed(.dpadUp)
            controllerService.buttonPressed(.dpadRight)
        }
        await waitForTasks()

        await MainActor.run {
            controllerService.buttonReleased(.dpadUp)
            controllerService.buttonReleased(.dpadRight)
        }
        await waitForTasks()

        await MainActor.run {
            let hasUp = mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == KeyCodeMapping.upArrow }
                return false
            }
            let hasRight = mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == KeyCodeMapping.rightArrow }
                return false
            }
            XCTAssertTrue(hasUp, "Up arrow should be pressed")
            XCTAssertTrue(hasRight, "Right arrow should be pressed")
        }
    }

	func testDPadPresetDiagonalUsesHeldKeysForMovement() async throws {
		await MainActor.run {
			var mappings: [ControllerButton: KeyMapping] = [:]
			DPadPreset.wasd.apply(to: &mappings)
			profileManager.setActiveProfile(Profile(name: "DPad WASD", buttonMappings: mappings, dpadPreset: .wasd))
		}
		try? await Task.sleep(nanoseconds: 10_000_000)

		await MainActor.run {
			controllerService.buttonPressed(.dpadUp)
			controllerService.buttonPressed(.dpadRight)
		}
		await waitForTasks()

		await MainActor.run {
			let startedW = mockInputSimulator.events.contains { event in
				if case .startHoldMapping(let mapping) = event { return mapping.keyCode == KeyCodeMapping.keyW }
				return false
			}
			let startedD = mockInputSimulator.events.contains { event in
				if case .startHoldMapping(let mapping) = event { return mapping.keyCode == KeyCodeMapping.keyD }
				return false
			}
			XCTAssertTrue(startedW, "D-pad Up preset movement should hold W")
			XCTAssertTrue(startedD, "D-pad Right preset movement should hold D")
			XCTAssertTrue(mockInputSimulator.heldDirectionKeys.contains(KeyCodeMapping.keyW))
			XCTAssertTrue(mockInputSimulator.heldDirectionKeys.contains(KeyCodeMapping.keyD))

			controllerService.buttonReleased(.dpadUp)
			controllerService.buttonReleased(.dpadRight)
		}
		await waitForTasks()

		await MainActor.run {
			let stoppedW = mockInputSimulator.events.contains { event in
				if case .stopHoldMapping(let mapping) = event { return mapping.keyCode == KeyCodeMapping.keyW }
				return false
			}
			let stoppedD = mockInputSimulator.events.contains { event in
				if case .stopHoldMapping(let mapping) = event { return mapping.keyCode == KeyCodeMapping.keyD }
				return false
			}
			XCTAssertTrue(stoppedW, "D-pad Up release should release W")
			XCTAssertTrue(stoppedD, "D-pad Right release should release D")
		}
	}

    // MARK: - Trigger Button Mapping Tests (High Priority)

    /// Tests left trigger as a button (digital, not analog)
    func testLeftTriggerAsButton() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "LT", buttonMappings: [
                .leftTrigger: .key(KeyCodeMapping.space)
            ]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.leftTrigger)
            controllerService.buttonReleased(.leftTrigger)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == KeyCodeMapping.space }
                return false
            }, "Left trigger should press space")
        }
    }

    /// Tests right trigger as a button
    func testRightTriggerAsButton() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "RT", buttonMappings: [
                .rightTrigger: .key(KeyCodeMapping.return)
            ]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.rightTrigger)
            controllerService.buttonReleased(.rightTrigger)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == KeyCodeMapping.return }
                return false
            }, "Right trigger should press return")
        }
    }

    /// Tests trigger as hold modifier
    func testTriggerAsHoldModifier() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "TrigMod", buttonMappings: [
                .leftTrigger: .holdModifier(.option),
                .a: .key(1)
            ]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.leftTrigger)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskAlternate), "Option should be held")
            controllerService.buttonPressed(.a)
            controllerService.buttonReleased(.a)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(1, _) = event { return true }
                return false
            }, "A should press while trigger holds modifier")
            controllerService.buttonReleased(.leftTrigger)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertFalse(mockInputSimulator.heldModifiers.contains(.maskAlternate), "Option should be released")
        }
    }

    // MARK: - Special Button Tests (High Priority)

    /// Tests Xbox/Guide button mapping
    func testXboxButtonMapping() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "Xbox", buttonMappings: [
                .xbox: .key(KeyCodeMapping.escape)
            ]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.xbox)
            controllerService.buttonReleased(.xbox)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == KeyCodeMapping.escape }
                return false
            }, "Xbox button should press escape")
        }
    }

    /// Tests Menu button mapping
    func testMenuButtonMapping() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "Menu", buttonMappings: [
                .menu: .key(KeyCodeMapping.tab)
            ]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.menu)
            controllerService.buttonReleased(.menu)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == KeyCodeMapping.tab }
                return false
            }, "Menu button should press tab")
        }
    }

    /// Tests View/Back button mapping
    func testViewButtonMapping() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "View", buttonMappings: [
                .view: .key(KeyCodeMapping.grave) // backtick/tilde key
            ]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.view)
            controllerService.buttonReleased(.view)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == KeyCodeMapping.grave }
                return false
            }, "View button should press grave/backtick")
        }
    }

}
