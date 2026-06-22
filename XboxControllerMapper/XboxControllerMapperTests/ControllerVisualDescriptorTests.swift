import XCTest
@testable import ControllerKeys

final class ControllerVisualDescriptorTests: XCTestCase {
	func testConcretePreviewLayoutsResolveExpectedFamilies() {
		let expected: [ControllerPreviewLayout: ControllerVisualFamily] = [
			.xbox: .xbox,
			.xboxElite: .xboxElite,
			.dualSense: .dualSense,
			.dualSenseEdge: .dualSenseEdge,
			.dualShock: .dualShock,
			.nintendo: .nintendo,
			.steam: .steam,
			.eightBitDoZero2: .eightBitDo(.zero2),
			.eightBitDoMicro: .eightBitDo(.micro),
			.eightBitDoLite2: .eightBitDo(.lite2),
			.eightBitDoLiteSE: .eightBitDo(.liteSE),
			.appleTVRemote: .appleTVRemote,
		]

		for layout in ControllerPreviewLayout.concreteLayouts {
			XCTAssertEqual(
				ControllerVisualDescriptor.concrete(for: layout)?.family,
				expected[layout],
				"\(layout.rawValue) should resolve to the expected visual family"
			)
		}
	}

	func testActivePreviewHasNoConcreteDescriptor() {
		XCTAssertNil(ControllerVisualDescriptor.concrete(for: .active))
	}

	func testConcreteGamepadLayoutsResolveExpectedMinimapStyles() {
		let expected: [ControllerPreviewLayout: ControllerMinimapStyle?] = [
			.xbox: .xbox,
			.xboxElite: .xboxElite,
			.dualSense: .dualSense,
			.dualSenseEdge: .dualSenseEdge,
			.dualShock: .dualShock,
			.nintendo: .nintendo,
			.steam: .steam,
			.eightBitDoZero2: .eightBitDoZero2,
			.eightBitDoMicro: .eightBitDoMicro,
			.eightBitDoLite2: .eightBitDoLite2,
			.eightBitDoLiteSE: .eightBitDoLiteSE,
			.appleTVRemote: nil,
		]

		for layout in ControllerPreviewLayout.concreteLayouts {
			XCTAssertEqual(
				ControllerVisualDescriptor.concrete(for: layout)?.minimapStyle,
				expected[layout] ?? nil,
				"\(layout.rawValue) should resolve to the expected minimap style"
			)
		}
	}

	func testEveryMinimapStyleIsReachableFromAPreviewLayout() {
		let renderedStyles = Set(
			ControllerPreviewLayout.concreteLayouts.compactMap {
				ControllerVisualDescriptor.concrete(for: $0)?.minimapStyle
			}
		)

		XCTAssertEqual(
			renderedStyles,
			Set(ControllerMinimapStyle.allCases),
			"Every minimap style should be reachable from a concrete preview layout"
		)
	}

	func testEveryGamepadMinimapStyleHasValidPreviewSize() {
		for style in ControllerMinimapStyle.allCases {
			XCTAssertGreaterThan(style.bodyAspectRatio, 0, "\(style) should have a positive aspect ratio")
			XCTAssertGreaterThan(style.previewSize.width, 0, "\(style) should have a positive width")
			XCTAssertGreaterThan(style.previewSize.height, 0, "\(style) should have a positive height")
			XCTAssertTrue(style.previewSize.width.isFinite, "\(style) width should be finite")
			XCTAssertTrue(style.previewSize.height.isFinite, "\(style) height should be finite")
		}
	}

	func testCapabilitiesMatchExistingControllerRules() {
		let zero2 = ControllerVisualDescriptor(family: .eightBitDo(.zero2))
		XCTAssertTrue(zero2.isStickless)
		XCTAssertFalse(zero2.hasSticks)
		XCTAssertFalse(zero2.hasTriggers)
		XCTAssertEqual(zero2.leftSystemButtons, [.view])
		XCTAssertEqual(zero2.shoulderButtons(side: .left), [.leftBumper])

		let micro = ControllerVisualDescriptor(family: .eightBitDo(.micro))
		XCTAssertTrue(micro.isStickless)
		XCTAssertTrue(micro.hasTriggers)
		XCTAssertEqual(micro.leftSystemButtons, [.view, .xbox])

		let lite2 = ControllerVisualDescriptor(family: .eightBitDo(.lite2))
		XCTAssertFalse(lite2.isStickless)
		XCTAssertTrue(lite2.hasSticks)
		XCTAssertTrue(lite2.hasTriggers)
	}

	func testSystemRowsMatchCurrentPreviewBehavior() {
		XCTAssertEqual(
			ControllerVisualDescriptor(family: .xbox).rightSystemButtons,
			[.menu, .share]
		)
		XCTAssertEqual(
			ControllerVisualDescriptor(family: .xboxElite).rightSystemButtons,
			[.menu],
			"Elite profile-cycle hardware button is not a mappable Share row"
		)
		XCTAssertEqual(
			ControllerVisualDescriptor(family: .steam).rightSystemButtons,
			[.menu, .share]
		)
		XCTAssertEqual(
			ControllerVisualDescriptor(family: .dualSense).rightSystemButtons,
			[.menu, .micMute]
		)
		XCTAssertEqual(
			ControllerVisualDescriptor(family: .dualSenseEdge).rightSystemButtons,
			[.menu, .micMute]
		)
		XCTAssertEqual(
			ControllerVisualDescriptor(family: .dualShock).rightSystemButtons,
			[.menu]
		)
	}

	func testSpecialSectionsAreDescriptorDriven() {
		let edge = ControllerVisualDescriptor(family: .dualSenseEdge)
		XCTAssertTrue(edge.showsDualSenseEdgeControls)
		XCTAssertFalse(edge.showsGripOrPaddleSection)

		let elite = ControllerVisualDescriptor(family: .xboxElite)
		XCTAssertFalse(elite.showsDualSenseEdgeControls)
		XCTAssertTrue(elite.showsGripOrPaddleSection)
		XCTAssertEqual(elite.gripOrPaddleSectionTitle, "ELITE PADDLES")

		let steam = ControllerVisualDescriptor(family: .steam)
		XCTAssertTrue(steam.showsGripOrPaddleSection)
		XCTAssertEqual(steam.gripOrPaddleSectionTitle, "STEAM GRIP BUTTONS")
	}
}
