import XCTest
@testable import ControllerKeys

final class ControllerButtonCoverageTests: XCTestCase {

    func testAllCases_ExposeStableMetadata() {
        for button in ControllerButton.allCases {
            XCTAssertFalse(button.displayName.isEmpty)
            XCTAssertFalse(button.shortLabel.isEmpty)
            XCTAssertFalse(button.displayName(forDualSense: false).isEmpty)
            XCTAssertFalse(button.displayName(forDualSense: true).isEmpty)
				XCTAssertFalse(button.shortLabel(forDualSense: false).isEmpty)
				XCTAssertFalse(button.shortLabel(forDualSense: true).isEmpty)
				XCTAssertFalse(button.displayName(forAppleTVRemote: true).isEmpty)
				XCTAssertFalse(button.shortLabel(forAppleTVRemote: true).isEmpty)

            _ = button.systemImageName
            _ = button.systemImageName(forDualSense: false)
            _ = button.systemImageName(forDualSense: true)
            _ = button.category
            _ = button.isDualSenseOnly
            _ = button.isDualSenseEdgeOnly
        }
    }

    func testDualSenseOnlyAndEdgeOnlyClassification() {
        let expectedDualSenseOnly: Set<ControllerButton> = [
            .micMute,
            .leftPaddle,
            .rightPaddle,
            .leftFunction,
            .rightFunction,
            .gestureTiltBack,
            .gestureTiltForward,
            .gestureSteerLeft,
            .gestureSteerRight,
        ]

        let expectedEdgeOnly: Set<ControllerButton> = [
            .leftPaddle,
            .rightPaddle,
            .leftFunction,
            .rightFunction
        ]

        let dualSenseOnly = Set(ControllerButton.allCases.filter { $0.isDualSenseOnly })
        let edgeOnly = Set(ControllerButton.allCases.filter { $0.isDualSenseEdgeOnly })
        let playStationOnly = Set(ControllerButton.allCases.filter { $0.isPlayStationOnly })
        let expectedPlayStationOnly: Set<ControllerButton> = [
            .touchpadButton,
            .touchpadTwoFingerButton,
            .touchpadTap,
            .touchpadTwoFingerTap,
            .touchpadRegionTopLeftClick,
            .touchpadRegionTopRightClick,
            .touchpadRegionBottomLeftClick,
            .touchpadRegionBottomRightClick,
            .touchpadRegionTopLeftTouch,
            .touchpadRegionTopRightTouch,
            .touchpadRegionBottomLeftTouch,
            .touchpadRegionBottomRightTouch,
            .micMute,
            .leftPaddle,
            .rightPaddle,
            .leftFunction,
            .rightFunction,
            .gestureTiltBack,
            .gestureTiltForward,
            .gestureSteerLeft,
            .gestureSteerRight,
        ]

        XCTAssertEqual(dualSenseOnly, expectedDualSenseOnly)
        XCTAssertEqual(edgeOnly, expectedEdgeOnly)
        XCTAssertEqual(playStationOnly, expectedPlayStationOnly)
        XCTAssertTrue(edgeOnly.isSubset(of: dualSenseOnly))
        XCTAssertTrue(dualSenseOnly.isSubset(of: playStationOnly))
    }

    func testXboxAndDualSenseButtonLists() {
        XCTAssertFalse(ControllerButton.xboxButtons.contains(.touchpadTap))
        XCTAssertFalse(ControllerButton.xboxButtons.contains(.leftPaddle))
				XCTAssertTrue(ControllerButton.xboxButtons.contains(.a))
				XCTAssertFalse(ControllerButton.xboxButtons.contains(.siri))
				XCTAssertFalse(ControllerButton.xboxButtons.contains(.appleTVRemotePower))

				XCTAssertFalse(ControllerButton.dualSenseButtons.contains(.share), "Standard DualSense does not expose Share")
				XCTAssertTrue(ControllerButton.dualSenseButtons.contains(.touchpadButton))
				XCTAssertTrue(ControllerButton.dualSenseButtons.contains(.a))
				XCTAssertFalse(ControllerButton.dualSenseButtons.contains(.siri))
				XCTAssertFalse(ControllerButton.dualSenseButtons.contains(.appleTVRemoteVolumeUp))

				XCTAssertFalse(ControllerButton.dualShockButtons.contains(.siri))
				XCTAssertFalse(ControllerButton.nintendoButtons.contains(.siri))
				XCTAssertEqual(
					ControllerButton.appleTVRemoteButtons,
					[
						.appleTVRemotePower,
						.dpadUp, .dpadDown, .dpadLeft, .dpadRight,
						.touchpadButton, .touchpadTap, .view, .menu, .xbox, .siri,
						.appleTVRemoteVolumeUp, .appleTVRemoteVolumeDown, .appleTVRemoteMute
					]
				)
    }

    func testSteamTouchpadRegionButtonsAreSteamOnlyAndComplete() {
        let leftRegionButtons = Set(ControllerButton.steamTouchpadRegionButtons(side: .left))
        let rightRegionButtons = Set(ControllerButton.steamTouchpadRegionButtons(side: .right))
        let expectedSteamOnly = Set<ControllerButton>([
            .leftTouchpadButton,
            .rightTouchpadButton,
            .leftTouchpadTap,
            .rightTouchpadTap,
        ]).union(leftRegionButtons).union(rightRegionButtons)

        XCTAssertEqual(leftRegionButtons.count, 8)
        XCTAssertEqual(rightRegionButtons.count, 8)
        XCTAssertTrue(leftRegionButtons.isDisjoint(with: rightRegionButtons))
        XCTAssertEqual(Set(ControllerButton.allCases.filter { $0.isSteamControllerOnly }), expectedSteamOnly)

        for side in SteamTouchpadSide.allCases {
            for region in TouchpadRegion.allCases {
                XCTAssertNotNil(ControllerButton.from(steamTouchpadSide: side, region: region, trigger: .click))
                XCTAssertNotNil(ControllerButton.from(steamTouchpadSide: side, region: region, trigger: .touch))
                XCTAssertNil(ControllerButton.from(steamTouchpadSide: side, region: region, trigger: .both))
            }
        }
    }

	    func testDualSenseLabelOverrides() {
        XCTAssertEqual(ControllerButton.a.displayName(forDualSense: true), "Cross")
        XCTAssertEqual(ControllerButton.b.displayName(forDualSense: true), "Circle")
        XCTAssertEqual(ControllerButton.x.displayName(forDualSense: true), "Square")
        XCTAssertEqual(ControllerButton.y.displayName(forDualSense: true), "Triangle")
        XCTAssertEqual(ControllerButton.menu.displayName(forDualSense: true), "Options")
        XCTAssertEqual(ControllerButton.view.displayName(forDualSense: true), "Create")
        XCTAssertEqual(ControllerButton.xbox.displayName(forDualSense: true), "PS")

        XCTAssertEqual(ControllerButton.a.shortLabel(forDualSense: true), "✕")
        XCTAssertEqual(ControllerButton.b.shortLabel(forDualSense: true), "○")
        XCTAssertEqual(ControllerButton.x.shortLabel(forDualSense: true), "□")
        XCTAssertEqual(ControllerButton.y.shortLabel(forDualSense: true), "△")
	}

	func testAppleTVRemoteLabelOverrides() {
		XCTAssertEqual(ControllerButton.touchpadButton.displayName(forAppleTVRemote: true), "Clickpad Click")
		XCTAssertEqual(ControllerButton.touchpadTap.displayName(forAppleTVRemote: true), "Clickpad Tap")
		XCTAssertEqual(ControllerButton.menu.displayName(forAppleTVRemote: true), "Play/Pause")
		XCTAssertEqual(ControllerButton.view.displayName(forAppleTVRemote: true), "Back")
		XCTAssertEqual(ControllerButton.xbox.displayName(forAppleTVRemote: true), "TV/Home")
		XCTAssertEqual(ControllerButton.siri.displayName(forAppleTVRemote: true), "Siri")
		XCTAssertEqual(ControllerButton.appleTVRemotePower.displayName(forAppleTVRemote: true), "Power")
		XCTAssertEqual(ControllerButton.appleTVRemoteVolumeUp.displayName(forAppleTVRemote: true), "Volume Up")
		XCTAssertEqual(ControllerButton.appleTVRemoteVolumeDown.displayName(forAppleTVRemote: true), "Volume Down")
		XCTAssertEqual(ControllerButton.appleTVRemoteMute.displayName(forAppleTVRemote: true), "Mute")

		XCTAssertEqual(ControllerButton.touchpadButton.shortLabel(forAppleTVRemote: true), "Click")
		XCTAssertEqual(ControllerButton.touchpadTap.shortLabel(forAppleTVRemote: true), "Tap")
		XCTAssertEqual(ControllerButton.menu.shortLabel(forAppleTVRemote: true), "▶")
		XCTAssertEqual(ControllerButton.view.shortLabel(forAppleTVRemote: true), "←")
		XCTAssertEqual(ControllerButton.xbox.shortLabel(forAppleTVRemote: true), "TV")
		XCTAssertEqual(ControllerButton.siri.shortLabel(forAppleTVRemote: true), "Siri")
		XCTAssertEqual(ControllerButton.appleTVRemotePower.shortLabel(forAppleTVRemote: true), "PWR")
		XCTAssertEqual(ControllerButton.appleTVRemoteVolumeUp.shortLabel(forAppleTVRemote: true), "V+")
		XCTAssertEqual(ControllerButton.appleTVRemoteVolumeDown.shortLabel(forAppleTVRemote: true), "V-")
		XCTAssertEqual(ControllerButton.appleTVRemoteMute.shortLabel(forAppleTVRemote: true), "Mute")
	}

	func testSystemImageNameMappings() {
		XCTAssertEqual(ControllerButton.xbox.systemImageName(forDualSense: false), "xbox.logo")
		XCTAssertEqual(ControllerButton.xbox.systemImageName(forDualSense: true), "playstation.logo")
		XCTAssertEqual(ControllerButton.view.systemImageName(forDualSense: false), "rectangle.on.rectangle")
		XCTAssertEqual(ControllerButton.view.systemImageName(forDualSense: true), "square.and.arrow.up")
		XCTAssertEqual(ControllerButton.appleTVRemotePower.systemImageName(forDualSense: false), "power")
		XCTAssertEqual(ControllerButton.appleTVRemoteVolumeUp.systemImageName(forDualSense: false), "speaker.wave.3.fill")
		XCTAssertNil(ControllerButton.a.systemImageName(forDualSense: true), "DualSense face buttons use text symbols")
	}

		func testAppleTVRemoteSystemImageOverridesAvoidXboxGlyphs() {
			XCTAssertEqual(ControllerButton.touchpadButton.systemImageName(forAppleTVRemote: true), "hand.point.up.left")
			XCTAssertEqual(ControllerButton.touchpadTap.systemImageName(forAppleTVRemote: true), "hand.tap")
		XCTAssertEqual(ControllerButton.menu.systemImageName(forAppleTVRemote: true), "playpause.fill")
		XCTAssertEqual(ControllerButton.xbox.systemImageName(forAppleTVRemote: true), "tv.fill")
		XCTAssertEqual(ControllerButton.view.systemImageName(forAppleTVRemote: true), "chevron.left")
		XCTAssertEqual(ControllerButton.appleTVRemoteVolumeUp.systemImageName(forAppleTVRemote: true), "plus")
			XCTAssertEqual(ControllerButton.appleTVRemoteVolumeDown.systemImageName(forAppleTVRemote: true), "minus")
		}

		func testElitePaddleAliasesPointAtDualSenseEdgeControls() {
			XCTAssertEqual(ControllerButton.xboxPaddle1.logicalEquivalent, .leftPaddle)
			XCTAssertEqual(ControllerButton.xboxPaddle2.logicalEquivalent, .rightPaddle)
			XCTAssertEqual(ControllerButton.xboxPaddle3.logicalEquivalent, .leftFunction)
			XCTAssertEqual(ControllerButton.xboxPaddle4.logicalEquivalent, .rightFunction)
			XCTAssertEqual(ControllerButton.leftPaddle.physicalEquivalentButtons, [.xboxPaddle1])
			XCTAssertEqual(ControllerButton.leftFunction.physicalEquivalentButtons, [.xboxPaddle3])
			XCTAssertEqual(ControllerButton.xboxPaddle1.chordSequenceAlias, .leftPaddle)
			XCTAssertEqual(ControllerButton.xboxPaddle3.chordSequenceAlias, .leftFunction)
		}

		func testCategoryCoverageAndOrdering() {
        let categories = Set(ControllerButton.allCases.map(\.category))
        XCTAssertEqual(categories, Set(ButtonCategory.allCases))

        for category in ButtonCategory.allCases {
            XCTAssertFalse(category.displayName.isEmpty)
            XCTAssertGreaterThanOrEqual(category.chordDisplayOrder, 0)
        }

        let uniqueOrderValues = Set(ButtonCategory.allCases.map(\.chordDisplayOrder))
        XCTAssertEqual(uniqueOrderValues.count, ButtonCategory.allCases.count)
    }
}
