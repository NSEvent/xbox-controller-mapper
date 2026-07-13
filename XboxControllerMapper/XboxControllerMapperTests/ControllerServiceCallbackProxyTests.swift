import XCTest
import AppKit
import CoreGraphics
import GameController
import IOKit.hid
@testable import ControllerKeys

@MainActor
final class ControllerServiceCallbackProxyTests: XCTestCase {
    private var controllerService: ControllerService!

    override func setUp() {
        super.setUp()
        controllerService = ControllerService(enableHardwareMonitoring: false)
    }

    override func tearDown() {
        controllerService.cleanup()
        controllerService = nil
        super.tearDown()
    }

	private func drainControllerQueue() {
		let expectation = expectation(description: "controller queue drained")
		controllerService.controllerQueue.async {
			expectation.fulfill()
		}
		wait(for: [expectation], timeout: 1.0)
	}

    func testInputEventSinkReceivesControllerEvents() {
        var events: [String] = []

        controllerService.onInputEvent = { event in
            switch event {
            case .buttonPressed:
                events.append("buttonPressed")
            case .buttonReleased:
                events.append("buttonReleased")
            case .chordDetected:
                events.append("chordDetected")
            case .touchpadMoved:
                events.append("touchpadMoved")
            case .steamLeftTouchpadMoved:
                events.append("steamLeftTouchpadMoved")
            case .appleTVRemoteCircularScroll:
                events.append("appleTVRemoteCircularScroll")
            case .touchpadGesture:
                events.append("touchpadGesture")
            case .touchpadTap:
                events.append("touchpadTap")
            case .controllerButtonTap:
                events.append("controllerButtonTap")
            case .touchpadTwoFingerTap:
                events.append("touchpadTwoFingerTap")
            case .touchpadLongTap:
                events.append("touchpadLongTap")
            case .touchpadTwoFingerLongTap:
                events.append("touchpadTwoFingerLongTap")
            case .touchpadRegionTap:
                events.append("touchpadRegionTap")
            case .motionGesture:
                events.append("motionGesture")
            }
        }

        controllerService.emitInputEvent(.buttonPressed(.a))
        controllerService.emitInputEvent(.buttonReleased(.a, holdDuration: 0.08))
        controllerService.emitInputEvent(.chordDetected([.a, .b]))
        controllerService.emitInputEvent(.touchpadMoved(CGPoint(x: 0.3, y: 0.2)))
        controllerService.emitInputEvent(.steamLeftTouchpadMoved(CGPoint(x: -0.3, y: 0.2)))
        controllerService.emitInputEvent(.appleTVRemoteCircularScroll(0.3))
        controllerService.emitInputEvent(.touchpadGesture(
            TouchpadGesture(
                centerDelta: CGPoint(x: 0.05, y: 0.01),
                distanceDelta: 0.02,
                isPrimaryTouching: true,
                isSecondaryTouching: false
            )
        ))
        controllerService.emitInputEvent(.touchpadTap)
        controllerService.emitInputEvent(.controllerButtonTap(.rightTouchpadTap))
        controllerService.emitInputEvent(.touchpadTwoFingerTap)
        controllerService.emitInputEvent(.touchpadLongTap)
        controllerService.emitInputEvent(.touchpadTwoFingerLongTap)
        controllerService.emitInputEvent(.touchpadRegionTap(.topLeft))
        controllerService.emitInputEvent(.motionGesture(.tiltBack))

        XCTAssertEqual(
            events,
            [
                "buttonPressed",
                "buttonReleased",
                "chordDetected",
                "touchpadMoved",
                "steamLeftTouchpadMoved",
                "appleTVRemoteCircularScroll",
                "touchpadGesture",
                "touchpadTap",
                "controllerButtonTap",
                "touchpadTwoFingerTap",
                "touchpadLongTap",
                "touchpadTwoFingerLongTap",
                "touchpadRegionTap",
                "motionGesture",
            ]
        )
    }

    func testInputEventSinkAllowsReplacementAndClearing() {
        var firstCount = 0
        var secondCount = 0

        controllerService.onInputEvent = { event in
            if case .touchpadTap = event {
                firstCount += 1
            }
        }
        controllerService.emitInputEvent(.touchpadTap)

        controllerService.onInputEvent = { event in
            if case .touchpadTap = event {
                secondCount += 1
            }
        }
        controllerService.emitInputEvent(.touchpadTap)

        controllerService.onInputEvent = nil
        controllerService.emitInputEvent(.touchpadTap)

        XCTAssertEqual(firstCount, 1)
        XCTAssertEqual(secondCount, 1)
        XCTAssertNil(controllerService.onInputEvent)
    }

    func testSteamTwoPadGestureLatchSuppressesSinglePadMovementBetweenAlternatingReports() {
        controllerService.storage.isSteamController = true
        var movements: [CGPoint] = []
        var gestures: [TouchpadGesture] = []
        controllerService.onInputEvent = { event in
            switch event {
            case .touchpadMoved(let delta):
                movements.append(delta)
            case .touchpadGesture(let gesture):
                gestures.append(gesture)
            default:
                break
            }
        }

        controllerService.updateSteamTouchpad(side: .left, x: 0.0, y: 0.0, isTouching: true)
        controllerService.updateSteamTouchpad(side: .right, x: 0.0, y: 0.0, isTouching: true)
        controllerService.updateSteamTouchpad(side: .left, x: -0.1, y: 0.0, isTouching: true)
        controllerService.updateSteamTouchpad(side: .right, x: 0.1, y: 0.0, isTouching: true)
        controllerService.updateSteamTouchpad(side: .left, x: -0.2, y: 0.0, isTouching: true)
        controllerService.updateSteamTouchpad(side: .right, x: 0.2, y: 0.0, isTouching: true)
        controllerService.updateSteamTouchpad(side: .left, x: -0.3, y: 0.0, isTouching: true)
        controllerService.updateSteamTouchpad(side: .right, x: 0.3, y: 0.0, isTouching: true)

        XCTAssertTrue(gestures.contains { $0.isPrimaryTouching && $0.isSecondaryTouching })
        movements.removeAll()
        gestures.removeAll()

        controllerService.updateSteamTouchpad(side: .left, x: -0.3, y: 0.0, isTouching: true)
        controllerService.updateSteamTouchpad(side: .right, x: 0.4, y: 0.0, isTouching: true)
        controllerService.updateSteamTouchpad(side: .right, x: 0.5, y: 0.0, isTouching: true)

        XCTAssertTrue(movements.isEmpty, "Right pad movement should stay blocked between alternating two-pad gesture reports")
    }

    func testSteamLeftTouchpadSinglePadMovementUsesDedicatedCallback() {
        controllerService.storage.isSteamController = true
        var leftPadMovements: [CGPoint] = []
        controllerService.onInputEvent = { event in
            if case .steamLeftTouchpadMoved(let delta) = event {
                leftPadMovements.append(delta)
            }
        }

        controllerService.updateSteamTouchpad(side: .left, x: 0.0, y: 0.0, isTouching: true)
        controllerService.updateSteamTouchpad(side: .left, x: 0.01, y: 0.0, isTouching: true)
        controllerService.updateSteamTouchpad(side: .left, x: 0.02, y: 0.0, isTouching: true)
        controllerService.updateSteamTouchpad(side: .left, x: 0.08, y: 0.0, isTouching: true)

        XCTAssertTrue(
            leftPadMovements.contains { $0.x > 0 },
            "Single left-pad Steam movement should produce app-owned scroll deltas when lizard mode is disabled"
        )
    }

	func testSteamRightTouchpadClickSuppressesClickInducedTouchJitter() {
		var movements: [CGPoint] = []
		controllerService.storage.isSteamController = true
		controllerService.onInputEvent = { event in
			if case .touchpadMoved(let delta) = event {
				movements.append(delta)
			}
		}

		controllerService.updateSteamTouchpad(side: .right, x: 0.0, y: 0.0, isTouching: true)
		controllerService.storage.touchpadFramesSinceTouch = 3
		controllerService.storage.touchpadTouchStartTime = CFAbsoluteTimeGetCurrent() - 1
		controllerService.storage.touchpadTouchStartPosition = CGPoint(x: 1.35, y: 0.0)

		controllerService.updateSteamTouchpad(side: .right, x: 0.10, y: 0.0, isTouching: true)
		controllerService.updateSteamTouchpad(side: .right, x: 0.20, y: 0.0, isTouching: true)
		XCTAssertFalse(movements.isEmpty, "Settled Steam right-pad touch movement should still produce mouse deltas")
		movements.removeAll()

		controllerService.handleSteamTouchpadClick(
			side: .right,
			state: SteamControllerTouchpadState(x: 0.20, y: 0.0, isTouching: true, isPressed: true),
			pressed: true
		)
		XCTAssertTrue(controllerService.storage.touchpadClickArmed)
		controllerService.updateSteamTouchpad(side: .right, x: 0.21, y: -0.015, isTouching: true)
		controllerService.updateSteamTouchpad(side: .right, x: 0.22, y: -0.030, isTouching: true)

		XCTAssertTrue(movements.isEmpty, "Steam right-pad click jitter should use the shared touchpad click suppression")
		controllerService.handleSteamTouchpadClick(
			side: .right,
			state: SteamControllerTouchpadState(x: 0.22, y: -0.030, isTouching: true, isPressed: false),
			pressed: false
		)
		XCTAssertFalse(controllerService.storage.touchpadClickArmed)
	}

	func testSteamLeftTouchpadClickSuppressesClickInducedTouchJitter() {
		var movements: [CGPoint] = []
		controllerService.storage.isSteamController = true
		controllerService.onInputEvent = { event in
			if case .steamLeftTouchpadMoved(let delta) = event {
				movements.append(delta)
			}
		}

		controllerService.updateSteamTouchpad(side: .left, x: 0.0, y: 0.0, isTouching: true)
		controllerService.storage.touchpadSecondaryFramesSinceTouch = 3

		controllerService.updateSteamTouchpad(side: .left, x: 0.10, y: 0.0, isTouching: true)
		XCTAssertFalse(movements.isEmpty, "Settled Steam left-pad touch movement should still produce deltas")
		movements.removeAll()

		controllerService.handleSteamTouchpadClick(
			side: .left,
			state: SteamControllerTouchpadState(x: 0.10, y: 0.0, isTouching: true, isPressed: true),
			pressed: true
		)
		XCTAssertTrue(controllerService.storage.steamLeftTouchpadClickArmed)
		controllerService.updateSteamTouchpad(side: .left, x: 0.11, y: -0.015, isTouching: true)
		controllerService.updateSteamTouchpad(side: .left, x: 0.12, y: -0.030, isTouching: true)

		XCTAssertTrue(movements.isEmpty, "Steam left-pad click jitter should be suppressed")
		controllerService.handleSteamTouchpadClick(
			side: .left,
			state: SteamControllerTouchpadState(x: 0.12, y: -0.030, isTouching: true, isPressed: false),
			pressed: false
		)
		XCTAssertFalse(controllerService.storage.steamLeftTouchpadClickArmed)
	}

    func testChordWindowRoundTripsThroughThreadSafeStorage() {
        controllerService.chordWindow = 0.23
        XCTAssertEqual(controllerService.chordWindow, 0.23, accuracy: 0.000_1)
    }

    func testLowLatencyNonChordButtonBypassesChordWindow() {
        var pressed: [ControllerButton] = []
        controllerService.lowLatencyInputEnabled = true
        controllerService.chordParticipantButtons = [.b]
        controllerService.onInputEvent = { event in
            if case .buttonPressed(let button) = event {
                pressed.append(button)
            }
        }

        controllerService.buttonPressed(.a)

        XCTAssertEqual(pressed, [.a])
    }

	func testAppleTVRemoteTapUsesGlobalTouchpadTapInQuadrantsMode() {
		var tapCount = 0
		var regionTapCount = 0
		controllerService.storage.isAppleTVRemote = true
		controllerService.storage.isSteamController = false
		controllerService.touchpadInputMode = .quadrants
		controllerService.onInputEvent = { event in
			switch event {
			case .touchpadTap:
				tapCount += 1
			case .touchpadRegionTap:
				regionTapCount += 1
			default:
				break
			}
		}

		controllerService.updateTouchpad(x: 0.5, y: 0.5, isTouching: true)
		controllerService.updateTouchpad(x: 0.5, y: 0.5, isTouching: false)

		XCTAssertEqual(tapCount, 1)
		XCTAssertEqual(regionTapCount, 0)
	}

	func testAppleTVRemoteClickpadButtonAggregatesDuplicateHIDSources() {
		var events: [ControllerButtonEvent] = []
		controllerService.lowLatencyInputEnabled = true
		controllerService.onInputEvent = { event in
			switch event {
			case .buttonPressed(let button):
				events.append(ControllerButtonEvent(button: button, pressed: true))
			case .buttonReleased(let button, _):
				events.append(ControllerButtonEvent(button: button, pressed: false))
			default:
				break
			}
		}

		controllerService.dispatchAppleTVRemoteButtonState(.touchpadButton, sourceKey: 1, isPressed: true)
		drainControllerQueue()
		controllerService.dispatchAppleTVRemoteButtonState(.touchpadButton, sourceKey: 2, isPressed: true)
		drainControllerQueue()
		controllerService.dispatchAppleTVRemoteButtonState(.touchpadButton, sourceKey: 1, isPressed: false)
		drainControllerQueue()
		controllerService.dispatchAppleTVRemoteButtonState(.touchpadButton, sourceKey: 2, isPressed: false)
		drainControllerQueue()

		XCTAssertEqual(
			events,
			[
				ControllerButtonEvent(button: .touchpadButton, pressed: true),
				ControllerButtonEvent(button: .touchpadButton, pressed: false)
			]
		)
	}

	func testAppleTVRemoteClickpadClickSuppressesClickInducedTouchJitter() {
		var movements: [CGPoint] = []
		controllerService.storage.isAppleTVRemote = true
		controllerService.storage.isSteamController = false
		controllerService.onInputEvent = { event in
			if case .touchpadMoved(let delta) = event {
				movements.append(delta)
			}
		}

		controllerService.updateTouchpad(x: 0.40, y: 0.40, isTouching: true)
		controllerService.storage.touchpadFramesSinceTouch = 3
		controllerService.storage.touchpadTouchStartTime = CFAbsoluteTimeGetCurrent() - 1
		controllerService.storage.touchpadTouchStartPosition = CGPoint(x: 0.40, y: 0.40)

		controllerService.updateTouchpad(x: 0.50, y: 0.40, isTouching: true)
		controllerService.updateTouchpad(x: 0.60, y: 0.40, isTouching: true)
		XCTAssertFalse(movements.isEmpty, "Settled Apple TV Remote touch movement should still produce mouse deltas")
		movements.removeAll()

		controllerService.dispatchAppleTVRemoteButtonState(.touchpadButton, sourceKey: 1, isPressed: true)
		XCTAssertTrue(controllerService.storage.touchpadClickArmed)
		controllerService.updateTouchpad(x: 0.61, y: 0.385, isTouching: true)
		controllerService.updateTouchpad(x: 0.62, y: 0.37, isTouching: true)

		XCTAssertTrue(movements.isEmpty, "Clickpad press jitter should be suppressed like DualSense touchpad click jitter")
		controllerService.dispatchAppleTVRemoteButtonState(.touchpadButton, sourceKey: 1, isPressed: false)
		XCTAssertFalse(controllerService.storage.touchpadClickArmed)
	}

	func testAppleTVRemoteTouchLiftReleasesTrackedClickpadButton() {
		var buttonEvents: [ControllerButtonEvent] = []
		var tapCount = 0
		controllerService.lowLatencyInputEnabled = true
		controllerService.storage.isAppleTVRemote = true
		controllerService.storage.isSteamController = false
		controllerService.onInputEvent = { event in
			switch event {
			case .buttonPressed(let button):
				buttonEvents.append(ControllerButtonEvent(button: button, pressed: true))
			case .buttonReleased(let button, _):
				buttonEvents.append(ControllerButtonEvent(button: button, pressed: false))
			case .touchpadTap:
				tapCount += 1
			default:
				break
			}
		}

		controllerService.updateTouchpad(x: 0.5, y: 0.5, isTouching: true)
		controllerService.dispatchAppleTVRemoteButtonState(.touchpadButton, sourceKey: 1, isPressed: true)
		drainControllerQueue()
		controllerService.releaseAppleTVRemoteTouchIfStillActive()
		drainControllerQueue()

		XCTAssertEqual(
			buttonEvents,
			[
				ControllerButtonEvent(button: .touchpadButton, pressed: true),
				ControllerButtonEvent(button: .touchpadButton, pressed: false)
			]
		)
		XCTAssertEqual(tapCount, 0)
		XCTAssertFalse(controllerService.storage.activeButtons.contains(.touchpadButton))
	}

	func testEliteControllerMetadataUsesActiveControllerNames() {
		XCTAssertTrue(
			ControllerService.isEliteControllerMetadata(
				vendorName: "Xbox Elite Wireless Controller",
				productCategory: "Xbox Controller"
			)
		)
		XCTAssertTrue(
			ControllerService.isEliteControllerMetadata(
				vendorName: nil,
				productCategory: "Xbox Elite Series 2 Controller"
			)
		)
		XCTAssertFalse(
			ControllerService.isEliteControllerMetadata(
				vendorName: "Xbox Wireless Controller",
				productCategory: "Xbox Controller"
			)
		)
	}

	    func testSteamControllerMetadataUsesSteamOrValveNames() {
        XCTAssertTrue(
            ControllerService.isSteamControllerMetadata(
                vendorName: "Steam Controller",
                productCategory: "Game Controller"
            )
        )
        XCTAssertTrue(
            ControllerService.isSteamControllerMetadata(
                vendorName: "Valve",
                productCategory: "Wireless Gamepad"
            )
        )
        XCTAssertFalse(
            ControllerService.isSteamControllerMetadata(
                vendorName: "Xbox Wireless Controller",
                productCategory: "Xbox Controller"
            )
        )
	    }

	    func testAppleTVRemoteMetadataMatchesRemoteCategoriesAndNames() {
			XCTAssertTrue(
				ControllerService.isAppleTVRemoteMetadata(
					vendorName: "Apple TV Remote",
					productCategory: GCProductCategorySiriRemote2ndGen
				)
			)
			XCTAssertTrue(
				ControllerService.isAppleTVRemoteMetadata(
					vendorName: "Universal Electronics",
					productCategory: "Universal Electronics Remote"
				)
			)
			XCTAssertFalse(
				ControllerService.isAppleTVRemoteMetadata(
					vendorName: "Apple",
					productCategory: "Keyboard"
				)
			)
	    }

	func testAppleTVRemoteHIDUsageMapsRemoteButtons() {
		XCTAssertEqual(
			ControllerService.appleTVRemoteButtonForHIDUsage(usagePage: 0x0C, usage: 0x00CF),
			.siri
		)
		XCTAssertEqual(
			ControllerService.appleTVRemoteButtonForHIDUsage(usagePage: 0x0C, usage: 0x0004),
			.siri
		)
		XCTAssertEqual(
			ControllerService.appleTVRemoteButtonForHIDUsage(usagePage: 0x0C, usage: 0x00CD),
			.menu
		)
		XCTAssertEqual(
			ControllerService.appleTVRemoteButtonForHIDUsage(usagePage: 0x0C, usage: 0x0080),
			.touchpadButton
		)
		XCTAssertEqual(
			ControllerService.appleTVRemoteButtonForHIDUsage(usagePage: 0x0C, usage: 0x0041),
			.touchpadButton
		)
		XCTAssertEqual(
			ControllerService.appleTVRemoteButtonForHIDUsage(usagePage: 0x0C, usage: 0x0060),
			.xbox
		)
		XCTAssertEqual(
			ControllerService.appleTVRemoteButtonForHIDUsage(usagePage: 0x0C, usage: 0x0040),
			.view
		)
		XCTAssertEqual(
			ControllerService.appleTVRemoteButtonForHIDUsage(usagePage: 0x0C, usage: 0x0046),
			.view
		)
		XCTAssertEqual(
			ControllerService.appleTVRemoteButtonForHIDUsage(usagePage: 0x0C, usage: 0x0030),
			.appleTVRemotePower
		)
		XCTAssertEqual(
			ControllerService.appleTVRemoteButtonForHIDUsage(usagePage: 0x0C, usage: 0x00E9),
			.appleTVRemoteVolumeUp
		)
		XCTAssertEqual(
			ControllerService.appleTVRemoteButtonForHIDUsage(usagePage: 0x0C, usage: 0x00EA),
			.appleTVRemoteVolumeDown
		)
		XCTAssertEqual(
			ControllerService.appleTVRemoteButtonForHIDUsage(usagePage: 0x0C, usage: 0x00E2),
			.appleTVRemoteMute
		)
		XCTAssertEqual(
			ControllerService.appleTVRemoteButtonForHIDUsage(usagePage: 0x0C, usage: 0x0042),
			.dpadUp
		)
		XCTAssertEqual(
			ControllerService.appleTVRemoteButtonForHIDUsage(usagePage: 0x0C, usage: 0x0043),
			.dpadDown
		)
		XCTAssertEqual(
			ControllerService.appleTVRemoteButtonForHIDUsage(usagePage: 0x0C, usage: 0x0044),
			.dpadLeft
		)
		XCTAssertEqual(
			ControllerService.appleTVRemoteButtonForHIDUsage(usagePage: 0x0C, usage: 0x0045),
			.dpadRight
		)
		XCTAssertEqual(
			ControllerService.appleTVRemoteButtonForHIDUsage(usagePage: 0x01, usage: 0x0086),
			.view
		)
		XCTAssertNil(
			ControllerService.appleTVRemoteButtonForHIDUsage(usagePage: 0x01, usage: 0x00CF)
		)
	}

	func testAppleTVRemoteSystemKeyTypesMapToNXConsumerControls() {
		XCTAssertEqual(ControllerService.appleTVRemoteSystemKeyType(for: .appleTVRemoteVolumeUp), 0)
		XCTAssertEqual(ControllerService.appleTVRemoteSystemKeyType(for: .appleTVRemoteVolumeDown), 1)
		XCTAssertEqual(ControllerService.appleTVRemoteSystemKeyType(for: .appleTVRemotePower), 6)
		XCTAssertEqual(ControllerService.appleTVRemoteSystemKeyType(for: .appleTVRemoteMute), 7)
		XCTAssertNil(ControllerService.appleTVRemoteSystemKeyType(for: .menu))
	}

	func testAppleTVRemoteSystemEventSuppressionRequiresRemoteHIDCorrelation() {
		controllerService.storage.isAppleTVRemote = true
		let systemDefinedType = CGEventType(rawValue: 14)!
		let volumeUpData1 = (0 << 16) | (0x0A << 8)

		XCTAssertFalse(
			controllerService.shouldSuppressAppleTVRemoteSystemEvent(
				systemDefinedEvent(subtype: 8, data1: volumeUpData1),
				type: systemDefinedType
			),
			"Mac keyboard media keys should pass through when no Apple TV Remote HID button was observed"
		)

		controllerService.storage.appleTVRemoteActiveSystemKeyTypes.insert(0)
		XCTAssertTrue(
			controllerService.shouldSuppressAppleTVRemoteSystemEvent(
				systemDefinedEvent(subtype: 8, data1: volumeUpData1),
				type: systemDefinedType
			)
		)
		controllerService.storage.appleTVRemoteActiveSystemKeyTypes.removeAll()

		controllerService.storage.appleTVRemoteSystemKeyTypeSuppressUntil[0] = CFAbsoluteTimeGetCurrent() + 1
		XCTAssertTrue(
			controllerService.shouldSuppressAppleTVRemoteSystemEvent(
				systemDefinedEvent(subtype: 8, data1: volumeUpData1),
				type: systemDefinedType
			)
		)

		controllerService.storage.appleTVRemoteSystemKeyTypeSuppressUntil.removeAll()
		controllerService.storage.appleTVRemoteSystemKeyTypeSuppressUntil[6] = CFAbsoluteTimeGetCurrent() + 1
		XCTAssertTrue(
			controllerService.shouldSuppressAppleTVRemoteSystemEvent(
				systemDefinedEvent(subtype: 1),
				type: systemDefinedType
			)
		)

		XCTAssertFalse(
			controllerService.shouldSuppressAppleTVRemoteSystemEvent(
				systemDefinedEvent(
					subtype: 8,
					data1: volumeUpData1,
					userData: Config.controllerKeysSyntheticMediaEventUserData
				),
				type: systemDefinedType
			)
		)

		controllerService.storage.isAppleTVRemote = false
		XCTAssertFalse(
			controllerService.shouldSuppressAppleTVRemoteSystemEvent(
				systemDefinedEvent(subtype: 8, data1: volumeUpData1),
				type: systemDefinedType
			)
		)
	}

	func testAppleTVRemoteDisconnectPreservesHIDManagersForWake() {
		controllerService.storage.isAppleTVRemote = true
		controllerService.appleTVRemoteHIDManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
		controllerService.appleTVRemoteHIDButtonManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

		controllerService.controllerDisconnected()

		XCTAssertFalse(controllerService.isConnected)
		XCTAssertNotNil(controllerService.appleTVRemoteHIDManager)
		XCTAssertNotNil(controllerService.appleTVRemoteHIDButtonManager)
	}

	func testAppleTVRemoteTouchReportParsesCurrentRemoteTouchPoint() {
		let report = currentAppleTVRemoteTouchReport(x: 75, y: 52, pressure: 17)
		let parsed = report.withUnsafeBufferPointer {
			ControllerService.appleTVRemoteTouchReport(
				reportID: 0xFF,
				report: $0.baseAddress!,
				length: $0.count
			)
		}

		XCTAssertEqual(parsed?.primary?.pressure, 17)
		XCTAssertEqual(parsed?.primary?.position.x ?? -2, 0, accuracy: 0.001)
		XCTAssertEqual(parsed?.primary?.position.y ?? -2, -0.0095, accuracy: 0.001)
		XCTAssertNil(parsed?.secondary)
	}

	func testAppleTVRemoteTouchReportTreatsZeroPressureAsLift() {
		let report = currentAppleTVRemoteTouchReport(x: 75, y: 52, pressure: 0)
		let parsed = report.withUnsafeBufferPointer {
			ControllerService.appleTVRemoteTouchReport(
				reportID: 0xFF,
				report: $0.baseAddress!,
				length: $0.count
			)
		}

		XCTAssertFalse(parsed?.isTouching ?? true)
	}

	func testAppleTVRemoteTouchReportsFeedTouchpadMovement() {
		var movements: [CGPoint] = []
		controllerService.onInputEvent = { event in
			if case .touchpadMoved(let delta) = event {
				movements.append(delta)
			}
		}

		for x in [75, 82, 90, 100, 112] {
			let report = currentAppleTVRemoteTouchReport(x: x, y: 52, pressure: 17)
			report.withUnsafeBufferPointer {
				controllerService.handleAppleTVRemoteTouchReport(
					reportID: 0xFF,
					report: $0.baseAddress!,
					length: $0.count
				)
			}
		}

		XCTAssertTrue(
			movements.contains { $0.x > 0 },
			"Apple TV Remote touch reports should enter the shared touchpad mouse pipeline."
		)
	}

		func testGlobalEliteHIDFallbackOnlyAppliesWhenSingleXboxControllerIsActive() {
		XCTAssertTrue(ControllerService.shouldUseGlobalEliteHIDFallback(connectedXboxControllerCount: 0))
		XCTAssertTrue(ControllerService.shouldUseGlobalEliteHIDFallback(connectedXboxControllerCount: 1))
		XCTAssertFalse(ControllerService.shouldUseGlobalEliteHIDFallback(connectedXboxControllerCount: 2))
	}

	func testRawHIDGuideSourcesAreDedupedTogether() {
		XCTAssertEqual(
			controllerService.guideMonitorGuideButtonEvents(pressed: true, now: 10),
			[ControllerButtonEvent(button: .xbox, pressed: true)]
		)
		XCTAssertEqual(
			controllerService.eliteHelperGuideButtonEvents(pressed: true, now: 10.1),
			[],
			"Same-state helper press should be ignored after guide monitor handled the press."
		)
		XCTAssertEqual(
			controllerService.eliteHelperGuideButtonEvents(pressed: false, now: 10.2),
			[ControllerButtonEvent(button: .xbox, pressed: false)]
		)
		XCTAssertEqual(
			controllerService.guideMonitorGuideButtonEvents(pressed: false, now: 10.3),
			[],
			"Same-state guide monitor release should be ignored after helper handled the release."
		)
	}

	func testRawHIDGuideStalePressRecoversMissingRelease() {
		XCTAssertEqual(
			controllerService.guideMonitorGuideButtonEvents(pressed: true, now: 20),
			[ControllerButtonEvent(button: .xbox, pressed: true)]
		)
		XCTAssertEqual(
			controllerService.eliteHelperGuideButtonEvents(pressed: true, now: 21),
			[],
			"Near-term duplicate press should stay deduped so duplicate HID interfaces do not double fire."
		)
		XCTAssertEqual(
			controllerService.guideMonitorGuideButtonEvents(pressed: true, now: 23),
			[
				ControllerButtonEvent(button: .xbox, pressed: false),
				ControllerButtonEvent(button: .xbox, pressed: true),
			],
			"A new press after a missing release should synthesize release then press."
		)
	}

	func testRawHIDGuideStaleRecoveryOnlyFiresOnceAcrossSources() {
		XCTAssertEqual(
			controllerService.guideMonitorGuideButtonEvents(pressed: true, now: 50),
			[ControllerButtonEvent(button: .xbox, pressed: true)]
		)
		XCTAssertEqual(
			controllerService.eliteHelperGuideButtonEvents(pressed: true, now: 52.1),
			[
				ControllerButtonEvent(button: .xbox, pressed: false),
				ControllerButtonEvent(button: .xbox, pressed: true),
			],
			"The first stale duplicate press recovers the missing release."
		)
		XCTAssertEqual(
			controllerService.guideMonitorGuideButtonEvents(pressed: true, now: 52.2),
			[],
			"A same-press report from the other raw source should not recover again."
		)
	}

	func testRawHIDGuideDoesNotRecoverWhilePressedReportsContinue() {
		XCTAssertEqual(
			controllerService.guideMonitorGuideButtonEvents(pressed: true, now: 40),
			[ControllerButtonEvent(button: .xbox, pressed: true)]
		)
		XCTAssertEqual(controllerService.guideMonitorGuideButtonEvents(pressed: true, now: 41), [])
		XCTAssertEqual(controllerService.guideMonitorGuideButtonEvents(pressed: true, now: 42.5), [])
		XCTAssertEqual(controllerService.guideMonitorGuideButtonEvents(pressed: true, now: 44), [])
	}

	func testRawHIDGuideReleaseClearsStateForLaterPress() {
		XCTAssertEqual(
			controllerService.guideMonitorGuideButtonEvents(pressed: true, now: 30),
			[ControllerButtonEvent(button: .xbox, pressed: true)]
		)
		XCTAssertEqual(
			controllerService.guideMonitorGuideButtonEvents(pressed: false, now: 30.2),
			[ControllerButtonEvent(button: .xbox, pressed: false)]
		)
		XCTAssertEqual(
			controllerService.eliteHelperGuideButtonEvents(pressed: true, now: 30.4),
			[ControllerButtonEvent(button: .xbox, pressed: true)]
		)
	}

	func testGuideMonitorPaddleButtonRequiresRawHIDSource() {
		controllerService.writeStorage(\.elitePaddleEventSource, .none)

		XCTAssertNil(
			controllerService.guideMonitorPaddleButton(for: 1, pressed: true),
			"Raw HID monitor paddle callbacks must be ignored when it does not own Elite paddles."
		)

		controllerService.writeStorage(\.elitePaddleEventSource, .rawHID)

		XCTAssertEqual(controllerService.guideMonitorPaddleButton(for: 1, pressed: true), .xboxPaddle1)
		XCTAssertEqual(controllerService.guideMonitorPaddleButton(for: 2, pressed: true), .xboxPaddle2)
		XCTAssertNil(controllerService.guideMonitorPaddleButton(for: 99, pressed: true))
	}

	func testRawHIDPaddleSourcesAreDedupedTogether() {
		controllerService.writeStorage(\.elitePaddleEventSource, .none)

		XCTAssertNil(
			controllerService.eliteHelperPaddleButton(for: 1, pressed: true),
			"Helper paddle callbacks must be ignored unless the helper owns Elite paddles."
		)

		controllerService.writeStorage(\.elitePaddleEventSource, .rawHID)

		XCTAssertEqual(controllerService.guideMonitorPaddleButton(for: 1, pressed: true), .xboxPaddle1)
		XCTAssertNil(
			controllerService.eliteHelperPaddleButton(for: 1, pressed: true),
			"Same-state helper event should be ignored after guide monitor handled the press."
		)
		XCTAssertEqual(controllerService.eliteHelperPaddleButton(for: 1, pressed: false), .xboxPaddle1)
		XCTAssertNil(
			controllerService.guideMonitorPaddleButton(for: 1, pressed: false),
			"Same-state guide monitor event should be ignored after helper handled the release."
		)
	}
}

private func systemDefinedEvent(subtype: Int16, data1: Int = 0, userData: Int64? = nil) -> CGEvent {
	let event = NSEvent.otherEvent(
		with: .systemDefined,
		location: .zero,
		modifierFlags: [],
		timestamp: 0,
		windowNumber: 0,
		context: nil,
		subtype: subtype,
		data1: data1,
		data2: -1
	)
	guard let cgEvent = event?.cgEvent else {
		fatalError("Failed to create system-defined test event")
	}
	if let userData {
		cgEvent.setIntegerValueField(.eventSourceUserData, value: userData)
	}
	return cgEvent
}

private func currentAppleTVRemoteTouchReport(x: Int, y: Int, pressure: UInt8) -> [UInt8] {
	let rawX = x * 15 + 230
	let highX = rawX / 255
	let lowX = rawX - highX * 255
	let rawY: Int
	if y <= 67 {
		rawY = y + 188
	} else {
		rawY = y - 67
	}
	return [
		0, 0, 0, 0,
		UInt8(lowX),
		UInt8(highX),
		UInt8(rawY),
		0,
		0,
		pressure,
		0,
	]
}
