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
}
