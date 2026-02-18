import XCTest
@testable import ControllerKeys

final class LayerAndConfigCoverageTests: XCTestCase {
    func testLayerInitDefaults() {
        let layer = Layer(name: "Combat")

        XCTAssertEqual(layer.name, "Combat")
        XCTAssertNil(layer.activatorButton)
        XCTAssertTrue(layer.buttonMappings.isEmpty)
    }

    func testLayerCodableRoundTripPreservesMappings() throws {
        let id = UUID()
        let layer = Layer(
            id: id,
            name: "Navigation",
            activatorButton: .leftBumper,
            buttonMappings: [
                .a: .key(0),
                .b: .combo(11, modifiers: .command)
            ]
        )

        let data = try JSONEncoder().encode(layer)
        let decoded = try JSONDecoder().decode(Layer.self, from: data)

        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.name, "Navigation")
        XCTAssertEqual(decoded.activatorButton, .leftBumper)
        XCTAssertEqual(decoded.buttonMappings[.a]?.keyCode, 0)
        XCTAssertEqual(decoded.buttonMappings[.b]?.keyCode, 11)
        XCTAssertEqual(decoded.buttonMappings[.b]?.modifiers, .command)
    }

    func testLayerDecodeMissingNameAndUnknownButtonKey() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "buttonMappings": {
            "a": { "keyCode": 1 },
            "not-a-button": { "keyCode": 2 }
          }
        }
        """

        let decoded = try JSONDecoder().decode(Layer.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.name, "Layer")
        XCTAssertEqual(decoded.buttonMappings.count, 1)
        XCTAssertEqual(decoded.buttonMappings[.a]?.keyCode, 1)
    }

    func testConfigDerivedValues() {
        XCTAssertEqual(Config.joystickPollInterval, 1.0 / Config.joystickPollFrequency, accuracy: 1e-12)
        XCTAssertEqual(Config.displayRefreshInterval, 1.0 / Config.displayRefreshFrequency, accuracy: 1e-12)
        XCTAssertEqual(Config.displayUpdateThrottleMs, Int(1000.0 / Config.displayRefreshFrequency))
        XCTAssertTrue(Config.configFilePath.hasSuffix(Config.configFileName))
        XCTAssertTrue(Config.legacyConfigFilePath.hasSuffix(Config.configFileName))
    }

    func testConfigAndButtonColorConstantsAreReferenced() {
        _ = Config.chordDetectionWindow
        _ = Config.defaultLongHoldThreshold
        _ = Config.defaultDoubleTapThreshold
        _ = Config.joystickPollFrequency
        _ = Config.joystickPollInterval
        _ = Config.joystickMinCutoffFrequency
        _ = Config.joystickMaxCutoffFrequency
        _ = Config.scrollDoubleTapWindow
        _ = Config.scrollTapThreshold
        _ = Config.scrollTapDirectionRatio
        _ = Config.scrollHorizontalThresholdRatio
        _ = Config.displayRefreshFrequency
        _ = Config.displayRefreshInterval
        _ = Config.displayUpdateDeadzone
        _ = Config.displayUpdateThrottleMs
        _ = Config.focusExitPauseDuration
        _ = Config.focusMultiplierSmoothingAlpha
        _ = Config.focusEntryHapticIntensity
        _ = Config.focusEntryHapticSharpness
        _ = Config.focusEntryHapticDuration
        _ = Config.focusExitHapticIntensity
        _ = Config.focusExitHapticSharpness
        _ = Config.focusExitHapticDuration
        _ = Config.wheelSegmentHapticIntensity
        _ = Config.wheelSegmentHapticSharpness
        _ = Config.wheelPerimeterHapticIntensity
        _ = Config.wheelPerimeterHapticSharpness
        _ = Config.wheelForceQuitHapticIntensity
        _ = Config.wheelForceQuitHapticSharpness
        _ = Config.wheelForceQuitHapticGap
        _ = Config.wheelActivateHapticIntensity
        _ = Config.wheelActivateHapticSharpness
        _ = Config.wheelActivateHapticDuration
        _ = Config.wheelSecondaryHapticIntensity
        _ = Config.wheelSecondaryHapticSharpness
        _ = Config.wheelSecondaryHapticDuration
        _ = Config.wheelSetEnterHapticIntensity
        _ = Config.wheelSetEnterHapticSharpness
        _ = Config.wheelSetEnterHapticDuration
        _ = Config.wheelSetExitHapticIntensity
        _ = Config.wheelSetExitHapticSharpness
        _ = Config.wheelSetExitHapticDuration
        _ = Config.wheelSegmentHapticCooldown
        _ = Config.wheelPerimeterHapticCooldown
        _ = Config.keyboardShowHapticIntensity
        _ = Config.keyboardShowHapticSharpness
        _ = Config.keyboardShowHapticDuration
        _ = Config.keyboardHideHapticIntensity
        _ = Config.keyboardHideHapticSharpness
        _ = Config.keyboardHideHapticDuration
        _ = Config.keyboardActionHapticIntensity
        _ = Config.keyboardActionHapticSharpness
        _ = Config.keyboardActionHapticDuration
        _ = Config.webhookSuccessHapticIntensity
        _ = Config.webhookSuccessHapticSharpness
        _ = Config.webhookSuccessHapticDuration
        _ = Config.webhookFailureHapticIntensity
        _ = Config.webhookFailureHapticSharpness
        _ = Config.webhookFailureHapticDuration
        _ = Config.webhookFailureHapticGap
        _ = Config.modifierPressDelay
        _ = Config.postModifierDelay
        _ = Config.keyPressDuration
        _ = Config.preReleaseDelay
        _ = Config.typingDelay
        _ = Config.multiClickThreshold
        _ = Config.touchpadSensitivityMultiplier
        _ = Config.touchpadAccelerationMaxDelta
        _ = Config.touchpadAccelerationMaxBoost
        _ = Config.touchpadMinSmoothingAlpha
        _ = Config.touchpadSmoothingResetInterval
        _ = Config.touchpadClickMovementThreshold
        _ = Config.touchpadTouchSettleInterval
        _ = Config.touchpadTapMaxDuration
        _ = Config.touchpadTapMaxMovement
        _ = Config.touchpadLongTapThreshold
        _ = Config.touchpadLongTapMaxMovement
        _ = Config.touchpadTwoFingerTapMaxMovement
        _ = Config.touchpadTwoFingerTapMaxGestureDistance
        _ = Config.touchpadTwoFingerTapMaxPinchDistance
        _ = Config.touchpadPinchDeadzone
        _ = Config.touchpadPinchDirectionLockInterval
        _ = Config.touchpadPinchSensitivityMultiplier
        _ = Config.touchpadPinchVsPanRatio
        _ = Config.touchpadTapCooldown
        _ = Config.touchpadPanSensitivityMultiplier
        _ = Config.touchpadPanDeadzone
        _ = Config.touchpadTwoFingerMinDistance
        _ = Config.touchpadSecondaryStaleInterval
        _ = Config.touchpadMomentumFrequency
        _ = Config.touchpadMomentumTickInterval
        _ = Config.touchpadMomentumMinDeltaTime
        _ = Config.touchpadMomentumMaxIdleInterval
        _ = Config.touchpadMomentumDecay
        _ = Config.touchpadMomentumStartVelocity
        _ = Config.touchpadMomentumSustainedDuration
        _ = Config.touchpadMomentumStopVelocity
        _ = Config.touchpadMomentumReleaseWindow
        _ = Config.touchpadMomentumMaxVelocity
        _ = Config.touchpadMomentumVelocitySmoothingAlpha
        _ = Config.touchpadMomentumBoostMin
        _ = Config.touchpadMomentumBoostMax
        _ = Config.touchpadMomentumBoostMaxVelocity
        _ = Config.lastControllerWasDualSenseKey
        _ = Config.lastControllerWasDualSenseEdgeKey
        _ = Config.touchpadDebugLoggingKey
        _ = Config.touchpadDebugEnvKey
        _ = Config.touchpadDebugLogInterval
        _ = Config.chordReleaseProcessingDelay
        _ = Config.modifierReleaseCheckDelay
        _ = Config.configDirectory
        _ = Config.legacyConfigDirectory
        _ = Config.configFileName
        _ = Config.batteryUpdateInterval
        _ = ButtonColors.xboxA
        _ = ButtonColors.xboxB
        _ = ButtonColors.xboxX
        _ = ButtonColors.xboxY
        _ = ButtonColors.psCross
        _ = ButtonColors.psCircle
        _ = ButtonColors.psSquare
        _ = ButtonColors.psTriangle
    }

    func testButtonColorsLookup() {
        XCTAssertNotNil(ButtonColors.xbox(.a))
        XCTAssertNotNil(ButtonColors.xbox(.b))
        XCTAssertNotNil(ButtonColors.xbox(.x))
        XCTAssertNotNil(ButtonColors.xbox(.y))
        XCTAssertNil(ButtonColors.xbox(.leftBumper))

        XCTAssertNotNil(ButtonColors.playStation(.a))
        XCTAssertNotNil(ButtonColors.playStation(.b))
        XCTAssertNotNil(ButtonColors.playStation(.x))
        XCTAssertNotNil(ButtonColors.playStation(.y))
        XCTAssertNil(ButtonColors.playStation(.rightTrigger))
    }
}
