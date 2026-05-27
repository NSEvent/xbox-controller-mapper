import XCTest
import CoreGraphics
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

    func testCallbackProxiesInvokeStoredHandlers() {
        var events: [String] = []

        controllerService.onButtonPressed = { _ in events.append("buttonPressed") }
        controllerService.onButtonReleased = { _, _ in events.append("buttonReleased") }
        controllerService.onChordDetected = { _ in events.append("chordDetected") }
        controllerService.onLeftStickMoved = { _ in events.append("leftStickMoved") }
        controllerService.onRightStickMoved = { _ in events.append("rightStickMoved") }
        controllerService.onTouchpadMoved = { _ in events.append("touchpadMoved") }
        controllerService.onTouchpadGesture = { _ in events.append("touchpadGesture") }
        controllerService.onTouchpadTap = { events.append("touchpadTap") }
        controllerService.onControllerButtonTap = { _ in events.append("controllerButtonTap") }
        controllerService.onTouchpadTwoFingerTap = { events.append("touchpadTwoFingerTap") }
        controllerService.onTouchpadLongTap = { events.append("touchpadLongTap") }
        controllerService.onTouchpadTwoFingerLongTap = { events.append("touchpadTwoFingerLongTap") }

        controllerService.onButtonPressed?(.a)
        controllerService.onButtonReleased?(.a, 0.08)
        controllerService.onChordDetected?([.a, .b])
        controllerService.onLeftStickMoved?(CGPoint(x: 0.2, y: -0.1))
        controllerService.onRightStickMoved?(CGPoint(x: -0.4, y: 0.7))
        controllerService.onTouchpadMoved?(CGPoint(x: 0.3, y: 0.2))
        controllerService.onTouchpadGesture?(
            TouchpadGesture(
                centerDelta: CGPoint(x: 0.05, y: 0.01),
                distanceDelta: 0.02,
                isPrimaryTouching: true,
                isSecondaryTouching: false
            )
        )
        controllerService.onTouchpadTap?()
        controllerService.onControllerButtonTap?(.rightTouchpadTap)
        controllerService.onTouchpadTwoFingerTap?()
        controllerService.onTouchpadLongTap?()
        controllerService.onTouchpadTwoFingerLongTap?()

        XCTAssertEqual(
            events,
            [
                "buttonPressed",
                "buttonReleased",
                "chordDetected",
                "leftStickMoved",
                "rightStickMoved",
                "touchpadMoved",
                "touchpadGesture",
                "touchpadTap",
                "controllerButtonTap",
                "touchpadTwoFingerTap",
                "touchpadLongTap",
                "touchpadTwoFingerLongTap",
            ]
        )
    }

    func testCallbackProxiesAllowReplacementAndClearing() {
        var firstCount = 0
        var secondCount = 0

        controllerService.onTouchpadTap = { firstCount += 1 }
        controllerService.onTouchpadTap?()

        controllerService.onTouchpadTap = { secondCount += 1 }
        controllerService.onTouchpadTap?()

        controllerService.onTouchpadTap = nil
        controllerService.onTouchpadTap?()

        XCTAssertEqual(firstCount, 1)
        XCTAssertEqual(secondCount, 1)
        XCTAssertNil(controllerService.onTouchpadTap)
    }

    func testChordWindowRoundTripsThroughThreadSafeStorage() {
        controllerService.chordWindow = 0.23
        XCTAssertEqual(controllerService.chordWindow, 0.23, accuracy: 0.000_1)
    }

    func testLowLatencyNonChordButtonBypassesChordWindow() {
        var pressed: [ControllerButton] = []
        controllerService.lowLatencyInputEnabled = true
        controllerService.chordParticipantButtons = [.b]
        controllerService.onButtonPressed = { pressed.append($0) }

        controllerService.buttonPressed(.a)

        XCTAssertEqual(pressed, [.a])
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
