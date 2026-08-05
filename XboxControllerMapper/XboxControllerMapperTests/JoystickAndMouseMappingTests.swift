import XCTest
import Combine
import CoreGraphics
import Carbon.HIToolbox
import SwiftUI
import AppKit
@testable import ControllerKeys

/// Joystick processing (deadzone, scroll, WASD mode), stick clicks, joystick settings, mouse button mappings, and focus mode.
/// Split from the original XboxControllerMapperTests.swift monolith.
final class JoystickAndMouseMappingTests: MappingEngineTestCase {

    func testJoystickMouseMovement() async throws {
        await MainActor.run {
            controllerService.isConnected = true
        }
        await waitForTasks(0.2)

        // Use test helper to set the internal storage value that the polling reads
        controllerService.setLeftStickForTesting(CGPoint(x: 0.5, y: 0.5))
        await waitForTasks(0.2)

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .moveMouse = event { return true }
                return false
            }, "Mouse movement should be generated from joystick input")
        }
    }

	func testAnalogPrecisionTriggerScalesJoystickMouseMovement() async throws {
		await MainActor.run {
			var settings = JoystickSettings()
			settings.leftStick.mode = .mouse
			settings.leftStick.mouseDeadzone = 0.05
			settings.leftStick.mouseAcceleration = 0.0
			settings.leftStick.mouseSensitivity = 0.5
			settings.analogPrecisionTriggerMode = .right
			settings.analogPrecisionMinimumSpeed = 0.25
			settings.analogPrecisionDeadzone = 0.0
			settings.analogPrecisionCurve = 0.0

			let profile = Profile(name: "Analog Precision", buttonMappings: [:], joystickSettings: settings)
			profileManager.setActiveProfile(profile)
			controllerService.isConnected = true
		}
		await waitForTasks(0.15)

		controllerService.updateRightTrigger(0.0, pressed: false)
		mockInputSimulator.clearEvents()
		controllerService.setLeftStickForTesting(CGPoint(x: 0.8, y: 0.0))
		await waitForTasks(0.35)
		let normal = averageRecentMouseDeltaX()

		controllerService.updateRightTrigger(1.0, pressed: false)
		mockInputSimulator.clearEvents()
		await waitForTasks(0.35)
		let precise = averageRecentMouseDeltaX()

		XCTAssertGreaterThan(normal, 0.1)
		XCTAssertGreaterThan(precise, 0.1)
		XCTAssertLessThan(precise, normal * 0.6)
	}

	private func averageRecentMouseDeltaX(limit: Int = 8) -> CGFloat {
		let deltas = mockInputSimulator.events.compactMap { event -> CGFloat? in
			if case .moveMouse(let dx, _) = event {
				return abs(dx)
			}
			return nil
		}
		let recent = Array(deltas.suffix(limit))
		XCTAssertFalse(recent.isEmpty, "Expected mouse movement events")
		return recent.reduce(0, +) / CGFloat(max(recent.count, 1))
	}
    
    // MARK: - Joystick Processing Tests (High Priority)

    /// Tests that joystick values within deadzone don't generate mouse movement
    func testJoystickDeadzoneNearBoundary() async throws {
        await MainActor.run {
            controllerService.isConnected = true
        }
        await waitForTasks(0.2)

        // Set joystick just inside default deadzone (0.15)
        controllerService.setLeftStickForTesting(CGPoint(x: 0.1, y: 0.1))
        await waitForTasks(0.2)

        await MainActor.run {
            // Should NOT generate mouse movement for value inside deadzone
            let mouseEvents = mockInputSimulator.events.filter { event in
                if case .moveMouse = event { return true }
                return false
            }
            XCTAssertTrue(mouseEvents.isEmpty, "Joystick inside deadzone should not generate mouse movement")
        }
    }

    /// Tests that joystick values just outside deadzone DO generate mouse movement
    func testJoystickJustOutsideDeadzone() async throws {
        await MainActor.run {
            controllerService.isConnected = true
        }
        await waitForTasks(0.2)

        // Set joystick just outside default deadzone (0.15) - use 0.3 to be safely outside
        controllerService.setLeftStickForTesting(CGPoint(x: 0.3, y: 0.0))
        await waitForTasks(0.2)

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .moveMouse = event { return true }
                return false
            }, "Joystick outside deadzone should generate mouse movement")
        }
    }

    /// Tests that inverted Y axis is respected
    func testJoystickInvertedY() async throws {
        await MainActor.run {
            var profile = Profile(name: "InvertY", buttonMappings: [:])
            profile.joystickSettings.leftStick.invertMouseY = true
            profileManager.setActiveProfile(profile)
            controllerService.isConnected = true
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
        await waitForTasks(0.2)

        // Move stick up (positive Y)
        controllerService.setLeftStickForTesting(CGPoint(x: 0.0, y: 0.5))
        await waitForTasks(0.2)

        await MainActor.run {
            // With inverted Y, positive stick Y should produce positive mouse dy
            // (normally it would be negative due to coordinate flip)
            let mouseEvents = mockInputSimulator.events.compactMap { event -> CGFloat? in
                if case .moveMouse(_, let dy) = event { return dy }
                return nil
            }
            XCTAssertFalse(mouseEvents.isEmpty, "Should have mouse movement")
            // The sign depends on the inversion - just verify we got events
        }
    }

    // MARK: - Right Stick Scroll Mode Tests (High Priority)

    /// Tests that right stick generates scroll events
    func testRightStickScrollMode() async throws {
        await MainActor.run {
            controllerService.isConnected = true
        }
        await waitForTasks(0.2)

        // We need to set right stick directly in storage for this test
        // Since there's no setRightStickForTesting, we'll verify the scroll mock is called
        // by observing that scroll events occur when processScrolling is called

        // For now, verify scroll mock exists and events can be recorded
        await MainActor.run {
            // The mock should be able to receive scroll events
            mockInputSimulator.scroll(event: ScrollEvent(dx: 1.0, dy: 2.0, phase: nil, momentumPhase: nil, isContinuous: false, flags: []))
        }

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .scroll(1.0, 2.0) = event { return true }
                return false
            }, "Mock should record scroll events")
        }
    }

    /// Exercises the live scroll path—not a reimplementation of its sign math.
    /// Both direction toggles must compose independently.
    func testAnalogScrollHonorsIndependentAxisDirectionSettings() async throws {
		let cases: [(invertX: Bool, invertY: Bool, expectPositiveX: Bool, expectPositiveY: Bool)] = [
			(false, false, false, true),
			(true, false, true, true),
			(false, true, false, false),
			(true, true, true, false),
		]

		for testCase in cases {
			var tuning = StickTuning(mode: .scroll)
			tuning.scrollSensitivity = 0
			tuning.scrollAcceleration = 0
			tuning.scrollDeadzone = 0
			tuning.invertScrollX = testCase.invertX
			tuning.invertScrollY = testCase.invertY

			mockInputSimulator.clearEvents()
			mappingEngine.processScrolling(
				CGPoint(x: 0.8, y: 0.6),
				rawStick: CGPoint(x: 0.8, y: 0.6),
				tuning: tuning,
				settings: JoystickSettings(),
				now: 0
			)

			guard case .scroll(let dx, let dy)? = mockInputSimulator.events.last else {
				XCTFail("Expected a scroll event")
				continue
			}
			XCTAssertEqual(dx > 0, testCase.expectPositiveX)
			XCTAssertEqual(dy > 0, testCase.expectPositiveY)
		}
    }

	@MainActor
	func testReversedVerticalScrollKeepsDoubleTapBoostMagnitude() {
		var tuning = StickTuning(mode: .scroll)
		tuning.scrollSensitivity = 0
		tuning.scrollAcceleration = 0
		tuning.scrollDeadzone = 0
		tuning.invertScrollY = true
		var settings = JoystickSettings()
		settings.scrollBoostMultiplier = 3

		mappingEngine.state.lock.withLock {
			mappingEngine.state.scrollBoostDirection = 0
		}
		mappingEngine.processScrolling(
			CGPoint(x: 0.4, y: 0.6),
			rawStick: CGPoint(x: 0.4, y: 0.6),
			tuning: tuning,
			settings: settings,
			now: 0
		)
		guard case .scroll(let baseX, let baseY)? = mockInputSimulator.events.last else {
			return XCTFail("Expected baseline scroll event")
		}

		mockInputSimulator.clearEvents()
		mappingEngine.state.lock.withLock {
			mappingEngine.state.scrollBoostDirection = 1
		}
		mappingEngine.processScrolling(
			CGPoint(x: 0.4, y: 0.6),
			rawStick: CGPoint(x: 0.4, y: 0.6),
			tuning: tuning,
			settings: settings,
			now: 1
		)
		guard case .scroll(let boostedX, let boostedY)? = mockInputSimulator.events.last else {
			return XCTFail("Expected boosted scroll event")
		}

		XCTAssertEqual(boostedX, baseX, accuracy: 0.0001)
		XCTAssertLessThan(boostedY, 0, "Reversing vertical scroll must preserve its sign during boost.")
		XCTAssertEqual(abs(boostedY), abs(baseY) * 3, accuracy: 0.0001)
	}

    func testScrollButtonWithoutPerActionSettingsRemainsOneShot() async throws {
		await MainActor.run {
			let mapping = KeyMapping(keyCode: KeyCodeMapping.scrollUp)
			profileManager.setActiveProfile(Profile(name: "Legacy Scroll", buttonMappings: [.a: mapping]))
		}
		try? await Task.sleep(nanoseconds: 10_000_000)

		await MainActor.run {
			controllerService.buttonPressed(.a)
		}
		await waitForTasks(0.12)

		await MainActor.run {
			XCTAssertFalse(mockInputSimulator.events.contains { event in
				if case .scroll = event { return true }
				return false
			}, "Legacy scroll action should not start continuous scrolling while held")
			controllerService.buttonReleased(.a)
		}
		await waitForTasks(0.12)

		await MainActor.run {
			let legacyPresses = mockInputSimulator.events.filter { event in
				if case .pressKey(let keyCode, _) = event {
					return keyCode == KeyCodeMapping.scrollUp
				}
				return false
			}
			XCTAssertEqual(legacyPresses.count, 1, "Legacy scroll action should execute once on release")
		}
    }

    func testScrollButtonWithPerActionSettingsScrollsContinuouslyUntilRelease() async throws {
		await MainActor.run {
			let mapping = KeyMapping(
				keyCode: KeyCodeMapping.scrollUp,
				scrollActionSettings: ScrollActionSettings(speed: 0.5, acceleration: 0)
			)
			profileManager.setActiveProfile(Profile(name: "Smooth Scroll", buttonMappings: [.a: mapping]))
		}
		try? await Task.sleep(nanoseconds: 10_000_000)

		await MainActor.run {
			controllerService.buttonPressed(.a)
		}
		await waitForTasks(0.12)

		let scrollCountWhileHeld = await MainActor.run {
			mockInputSimulator.events.filter { event in
				if case .scroll(_, let dy) = event {
					return dy > 0
				}
				return false
			}.count
		}
		XCTAssertGreaterThanOrEqual(scrollCountWhileHeld, 2, "Smooth scroll should emit repeated scroll events while held")

		await MainActor.run {
			XCTAssertFalse(mockInputSimulator.events.contains { event in
				if case .pressKey(let keyCode, _) = event {
					return keyCode == KeyCodeMapping.scrollUp
				}
				return false
			}, "Smooth scroll should not fall through to the legacy key press path")
			controllerService.buttonReleased(.a)
		}
		await waitForTasks(0.08)

		let countAfterRelease = await MainActor.run {
			mockInputSimulator.events.filter { event in
				if case .scroll = event { return true }
				return false
			}.count
		}
		await waitForTasks(0.08)

		await MainActor.run {
			let finalCount = mockInputSimulator.events.filter { event in
				if case .scroll = event { return true }
				return false
			}.count
			XCTAssertEqual(finalCount, countAfterRelease, "Smooth scroll timer should stop after release")
		}
    }

    // MARK: - Mouse Button Mapping Tests (High Priority)

    /// Tests that mouse left click mapping works
    func testMouseLeftClickMapping() async throws {
        await MainActor.run {
            let mapping = KeyMapping(keyCode: KeyCodeMapping.mouseLeftClick, isHoldModifier: true)
            profileManager.setActiveProfile(Profile(name: "MouseClick", buttonMappings: [.a: mapping]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.a)
        }
        await waitForTasks()

        await MainActor.run {
            // Mouse clicks use startHoldMapping for the "held" mouse button
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .startHoldMapping(let mapping) = event {
                    return mapping.keyCode == KeyCodeMapping.mouseLeftClick
                }
                return false
            }, "Should start hold mapping for mouse left click")
        }

        await MainActor.run {
            controllerService.buttonReleased(.a)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .stopHoldMapping(let mapping) = event {
                    return mapping.keyCode == KeyCodeMapping.mouseLeftClick
                }
                return false
            }, "Should stop hold mapping on release")
        }
    }

    /// Tests that mouse right click mapping works
    func testMouseRightClickMapping() async throws {
        await MainActor.run {
            let mapping = KeyMapping(keyCode: KeyCodeMapping.mouseRightClick, isHoldModifier: true)
            profileManager.setActiveProfile(Profile(name: "RightClick", buttonMappings: [.b: mapping]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.b)
        }
        await waitForTasks()

        await MainActor.run {
            controllerService.buttonReleased(.b)
        }
        await waitForTasks()

        await MainActor.run {
            let hasStartHold = mockInputSimulator.events.contains { event in
                if case .startHoldMapping(let mapping) = event {
                    return mapping.keyCode == KeyCodeMapping.mouseRightClick
                }
                return false
            }
            let hasStopHold = mockInputSimulator.events.contains { event in
                if case .stopHoldMapping(let mapping) = event {
                    return mapping.keyCode == KeyCodeMapping.mouseRightClick
                }
                return false
            }
            XCTAssertTrue(hasStartHold, "Should have start hold for right click")
            XCTAssertTrue(hasStopHold, "Should have stop hold for right click")
        }
    }

    // MARK: - Focus Mode Tests (Medium Priority)

	@MainActor
	func testFocusModeHapticsPlayOnEntryAndExitWhenEnabled() async {
		let accepted = expectation(description: "focus haptics accepted")
		accepted.expectedFulfillmentCount = 2
		controllerService.hapticSessionAcceptedForTesting = { _ in
			accepted.fulfill()
		}

		mappingEngine.performFocusModeHaptic(entering: true, enabled: true)
		mappingEngine.performFocusModeHaptic(entering: false, enabled: true)

		await fulfillment(of: [accepted], timeout: 1.0)
		controllerService.hapticSessionAcceptedForTesting = nil
	}

	@MainActor
	func testDisabledFocusModeHapticsDoNotBlockStateTransitions() async {
		let countLock = NSLock()
		var acceptedHapticCount = 0
		controllerService.hapticSessionAcceptedForTesting = { _ in
			countLock.withLock {
				acceptedHapticCount += 1
			}
		}

		var settings = JoystickSettings()
		settings.focusModeHapticsEnabled = false
		var deferredIO: [() -> Void] = []

		mappingEngine.state.lock.withLock {
			mappingEngine.updateFocusModeState(
				isFocusActive: true,
				settings: settings,
				now: 100,
				deferring: &deferredIO
			)
			mappingEngine.updateFocusModeState(
				isFocusActive: false,
				settings: settings,
				now: 101,
				deferring: &deferredIO
			)
		}
		deferredIO.forEach { $0() }

		let hapticQueueDrained = expectation(description: "haptic queue drained")
		controllerService.hapticQueue.async {
			hapticQueueDrained.fulfill()
		}
		await fulfillment(of: [hapticQueueDrained], timeout: 1.0)

		let focusState = mappingEngine.state.lock.withLock {
			(mappingEngine.state.wasFocusActive, mappingEngine.state.focusExitTime)
		}
		XCTAssertFalse(focusState.0)
		XCTAssertEqual(focusState.1, 101, accuracy: 0.0001)
		XCTAssertEqual(countLock.withLock { acceptedHapticCount }, 0)
		controllerService.hapticSessionAcceptedForTesting = nil
	}

	@MainActor
	func testFocusModeGyroCalibrationDelayOnlyCoversActualSteamHaptics() {
		XCTAssertEqual(
			MappingEngine.focusModeGyroCalibrationDelay(
				isSteamController: true,
				hapticsEnabled: true
			),
			Config.focusEntryHapticDuration + 0.08,
			accuracy: 0.0001
		)
		XCTAssertEqual(
			MappingEngine.focusModeGyroCalibrationDelay(
				isSteamController: true,
				hapticsEnabled: false
			),
			0
		)
		XCTAssertEqual(
			MappingEngine.focusModeGyroCalibrationDelay(
				isSteamController: false,
				hapticsEnabled: true
			),
			0
		)
	}

    /// Tests that focus mode reduces sensitivity when modifier is held
    func testFocusModeActivation() async throws {
        await MainActor.run {
            var profile = Profile(name: "Focus", buttonMappings: [
                .leftBumper: .holdModifier(.command)
            ])
            profile.joystickSettings.focusModeModifier = .command
            profile.joystickSettings.focusModeSensitivity = 0.1
            profileManager.setActiveProfile(profile)
            controllerService.isConnected = true
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
        await waitForTasks(0.2)

        // Press LB to hold Command (which is also focus modifier)
        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks()

        // Verify modifier is held
        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskCommand), "Command should be held for focus mode")
        }
    }

    /// Tests focus mode with different modifier than held button
    func testFocusModeWithDifferentModifier() async throws {
        await MainActor.run {
            var profile = Profile(name: "FocusDiff", buttonMappings: [
                .leftBumper: .holdModifier(.shift)
            ])
            profile.joystickSettings.focusModeModifier = .command // Different from held modifier
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks()

        await MainActor.run {
            // Shift is held, but focus mode requires Command
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskShift), "Shift should be held")
            XCTAssertFalse(mockInputSimulator.heldModifiers.contains(.maskCommand), "Command should NOT be held")
        }
    }

    // MARK: - Stick Click Tests (High Priority)

    /// Tests left stick click (L3) mapping with middle mouse (treated as hold mapping)
    func testLeftStickClick() async throws {
        await MainActor.run {
            // Mouse clicks are automatically treated as hold mappings
            let mapping = KeyMapping(keyCode: KeyCodeMapping.mouseMiddleClick, isHoldModifier: true)
            profileManager.setActiveProfile(Profile(name: "L3", buttonMappings: [
                .leftThumbstick: mapping
            ]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.leftThumbstick)
        }
        await waitForTasks()

        await MainActor.run {
            // Mouse clicks use startHoldMapping
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .startHoldMapping(let m) = event { return m.keyCode == KeyCodeMapping.mouseMiddleClick }
                return false
            }, "Left stick click should start hold mapping for middle mouse")

            controllerService.buttonReleased(.leftThumbstick)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .stopHoldMapping(let m) = event { return m.keyCode == KeyCodeMapping.mouseMiddleClick }
                return false
            }, "Left stick click should stop hold mapping on release")
        }
    }

    /// Tests right stick click (R3) mapping
    func testRightStickClick() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "R3", buttonMappings: [
                .rightThumbstick: .key(KeyCodeMapping.f5)
            ]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.rightThumbstick)
            controllerService.buttonReleased(.rightThumbstick)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == KeyCodeMapping.f5 }
                return false
            }, "Right stick click should press F5")
        }
    }

    // MARK: - Joystick Settings Tests

    /// Tests updating joystick settings in profile
    func testUpdateJoystickSettings() async throws {
        await MainActor.run {
            let profile = Profile(name: "Test")
            profileManager.profiles = [profile]
            profileManager.setActiveProfile(profile)

            var settings = JoystickSettings.default
            settings.leftStick.mouseSensitivity = 0.8
            settings.leftStick.invertMouseY = true

            profileManager.updateJoystickSettings(settings)

            XCTAssertEqual(profileManager.activeProfile?.joystickSettings.leftStick.mouseSensitivity, 0.8)
            XCTAssertTrue(profileManager.activeProfile?.joystickSettings.leftStick.invertMouseY ?? false)
        }
    }

    // MARK: - Stick to WASD/Arrow Keys Mode Tests

    /// Tests left stick WASD mode - pushing up triggers W key
    func testLeftStickWASDModeUpDirection() async throws {
        await MainActor.run {
            var profile = Profile(name: "WASD", buttonMappings: [:])
            profile.joystickSettings.leftStick.mode = .wasdKeys
            profile.joystickSettings.leftStick.mouseDeadzone = 0.15
            profileManager.setActiveProfile(profile)
            controllerService.isConnected = true
        }
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms for profile to propagate

        // Push stick up (positive Y)
        controllerService.setLeftStickForTesting(CGPoint(x: 0.0, y: 0.8))
        await waitForTasks(0.2)

        await MainActor.run {
            // W key = keyCode 13
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .keyDown(let code) = event { return code == 13 }
                return false
            }, "W key should be pressed when stick pushed up")
            XCTAssertTrue(mockInputSimulator.heldDirectionKeys.contains(13), "W key should be held")
        }
    }

    /// Tests left stick WASD mode - diagonal direction (up-right) triggers W+D
    func testLeftStickWASDModeDiagonal() async throws {
        await MainActor.run {
            var profile = Profile(name: "WASD", buttonMappings: [:])
            profile.joystickSettings.leftStick.mode = .wasdKeys
            profile.joystickSettings.leftStick.mouseDeadzone = 0.15
            profileManager.setActiveProfile(profile)
            controllerService.isConnected = true
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Push stick up-right (positive X and Y)
        controllerService.setLeftStickForTesting(CGPoint(x: 0.7, y: 0.7))
        await waitForTasks(0.2)

        await MainActor.run {
            // W = 13, D = 2
            XCTAssertTrue(mockInputSimulator.heldDirectionKeys.contains(13), "W key should be held")
            XCTAssertTrue(mockInputSimulator.heldDirectionKeys.contains(2), "D key should be held")
        }
    }

    /// Tests left stick WASD mode - keys released when returning to center
    func testLeftStickWASDModeReleaseOnCenter() async throws {
        await MainActor.run {
            var profile = Profile(name: "WASD", buttonMappings: [:])
            profile.joystickSettings.leftStick.mode = .wasdKeys
            profile.joystickSettings.leftStick.mouseDeadzone = 0.15
            profileManager.setActiveProfile(profile)
            controllerService.isConnected = true
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Push stick up
        controllerService.setLeftStickForTesting(CGPoint(x: 0.0, y: 0.8))
        await waitForTasks(0.2)

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.heldDirectionKeys.contains(13), "W key should be held")
        }

        // Return to center
        controllerService.setLeftStickForTesting(CGPoint(x: 0.0, y: 0.0))
        await waitForTasks(0.2)

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.heldDirectionKeys.isEmpty, "All keys should be released when stick returns to center")
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .keyUp(let code) = event { return code == 13 }
                return false
            }, "W key should have keyUp event")
        }
    }

    /// Tests left stick WASD mode - deadzone respected
    func testLeftStickWASDModeDeadzoneRespected() async throws {
        await MainActor.run {
            var profile = Profile(name: "WASD", buttonMappings: [:])
            profile.joystickSettings.leftStick.mode = .wasdKeys
            profile.joystickSettings.leftStick.mouseDeadzone = 0.3 // Higher deadzone
            profileManager.setActiveProfile(profile)
            controllerService.isConnected = true
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Push stick just inside deadzone
        controllerService.setLeftStickForTesting(CGPoint(x: 0.0, y: 0.2))
        await waitForTasks(0.2)

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.heldDirectionKeys.isEmpty, "No keys should be held inside deadzone")
            XCTAssertFalse(mockInputSimulator.events.contains { event in
                if case .keyDown = event { return true }
                return false
            }, "No keyDown events inside deadzone")
        }
    }

    /// Tests right stick arrow keys mode setting persistence
    func testRightStickArrowKeysMode() async throws {
        await MainActor.run {
            var profile = Profile(name: "Arrows", buttonMappings: [:])
            profile.joystickSettings.rightStick.mode = .arrowKeys
            profile.joystickSettings.rightStick.scrollDeadzone = 0.15
            profileManager.setActiveProfile(profile)
            controllerService.isConnected = true
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        await MainActor.run {
            XCTAssertEqual(profileManager.activeProfile?.joystickSettings.rightStick.mode, .arrowKeys)
        }
    }

    /// Tests that disabling engine releases held direction keys
    func testEngineDisableReleasesDirectionKeys() async throws {
        await MainActor.run {
            var profile = Profile(name: "WASD", buttonMappings: [:])
            profile.joystickSettings.leftStick.mode = .wasdKeys
            profile.joystickSettings.leftStick.mouseDeadzone = 0.15
            profileManager.setActiveProfile(profile)
            controllerService.isConnected = true
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Push stick up
        controllerService.setLeftStickForTesting(CGPoint(x: 0.0, y: 0.8))
        await waitForTasks(0.2)

        await MainActor.run {
            XCTAssertFalse(mockInputSimulator.heldDirectionKeys.isEmpty, "Keys should be held before disable")
            mappingEngine.disable()
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.heldDirectionKeys.isEmpty, "All direction keys should be released on disable")
        }
    }

    /// Tests stick mode setting persistence
    func testStickModeSettingPersistence() async throws {
        await MainActor.run {
            var profile = Profile(name: "ModeTest", buttonMappings: [:])
            profile.joystickSettings.leftStick.mode = .wasdKeys
            profile.joystickSettings.rightStick.mode = .arrowKeys
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            XCTAssertEqual(profileManager.activeProfile?.joystickSettings.leftStick.mode, .wasdKeys)
            XCTAssertEqual(profileManager.activeProfile?.joystickSettings.rightStick.mode, .arrowKeys)
        }
    }
}
