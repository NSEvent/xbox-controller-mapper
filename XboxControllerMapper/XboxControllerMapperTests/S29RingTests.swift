import IOKit.hid
import XCTest
@testable import ControllerKeys

// MARK: - Identity

final class S29RingIdentityTests: XCTestCase {
	func testMatchesOnlyWhenAllFourIdentityFactsAgree() {
		XCTAssertTrue(S29RingIdentity.matches(
			vendorID: 0x05AC, productID: 0x0220, productName: "S29", transport: "Bluetooth Low Energy"
		))
		XCTAssertTrue(S29RingIdentity.matches(
			vendorID: 0x05AC, productID: 0x0220, productName: "S29", transport: "BluetoothLowEnergy"
		))
		XCTAssertTrue(
			S29RingIdentity.matches(
				vendorID: 0x05AC, productID: 0x0220, productName: "s29", transport: "Bluetooth Low Energy"
			),
			"product name comparison is case-insensitive"
		)
	}

	func testRejectsRealAppleKeyboardSharingTheSpoofedVendorAndProduct() {
		// The aluminum Apple keyboard uses the same VID/PID over USB.
		XCTAssertFalse(S29RingIdentity.matches(
			vendorID: 0x05AC, productID: 0x0220, productName: "Apple Keyboard", transport: "USB"
		))
		XCTAssertFalse(S29RingIdentity.matches(
			vendorID: 0x05AC, productID: 0x0220, productName: "Apple Keyboard", transport: "Bluetooth Low Energy"
		))
	}

	func testRejectsS29NameOverNonBluetoothLETransport() {
		XCTAssertFalse(S29RingIdentity.matches(
			vendorID: 0x05AC, productID: 0x0220, productName: "S29", transport: "USB"
		))
		XCTAssertFalse(S29RingIdentity.matches(
			vendorID: 0x05AC, productID: 0x0220, productName: "S29", transport: "Bluetooth"
		))
		XCTAssertFalse(S29RingIdentity.matches(
			vendorID: 0x05AC, productID: 0x0220, productName: "S29", transport: nil
		))
	}

	func testRejectsMissingOrDifferentIdentityFacts() {
		XCTAssertFalse(S29RingIdentity.matches(
			vendorID: nil, productID: nil, productName: "S29", transport: "Bluetooth Low Energy"
		))
		XCTAssertFalse(S29RingIdentity.matches(
			vendorID: 0x05AC, productID: 0x0221, productName: "S29", transport: "Bluetooth Low Energy"
		))
		XCTAssertFalse(S29RingIdentity.matches(
			vendorID: 0x05AD, productID: 0x0220, productName: "S29", transport: "Bluetooth Low Energy"
		))
		XCTAssertFalse(S29RingIdentity.matches(
			vendorID: 0x05AC, productID: 0x0220, productName: nil, transport: "Bluetooth Low Energy"
		))
		XCTAssertFalse(S29RingIdentity.matches(
			vendorID: 0x05AC, productID: 0x0220, productName: "S29 Pro", transport: "Bluetooth Low Energy"
		))
	}

	@MainActor
	func testDriverDescriptorScopesMatchingToBluetoothLE() {
		let descriptor = S29RingHIDDriverDescriptor()
		XCTAssertEqual(
			descriptor.matchingCriteria,
			[
				.vendorProductTransport(vendorID: 0x05AC, productID: 0x0220, transport: "Bluetooth Low Energy"),
				.vendorProductTransport(vendorID: 0x05AC, productID: 0x0220, transport: "BluetoothLowEnergy"),
			]
		)
		XCTAssertEqual(CFArrayGetCount(descriptor.matchingCFArray), 2)

		for criterion in descriptor.matchingCriteria {
			let dictionary = criterion.dictionary
			XCTAssertEqual(dictionary[kIOHIDVendorIDKey as String] as? Int, 0x05AC)
			XCTAssertEqual(dictionary[kIOHIDProductIDKey as String] as? Int, 0x0220)
			XCTAssertNotNil(dictionary[kIOHIDTransportKey as String], "every dictionary must require the BLE transport")
		}
	}
}

// MARK: - Report parsing

final class S29RingReportParsingTests: XCTestCase {
	func testTouchReportParsesFingerStateAnd12BitCoordinates() throws {
		// X = 0x234 → byte2 = 0x34, byte3 low nibble = 0x2
		// Y = 0xABC → byte3 high nibble = 0xC, byte4 = 0xAB
		let sample = try XCTUnwrap(S29RingReportDecoder.parseTouchReport([0x01, 0x01, 0x34, 0xC2, 0xAB]))
		XCTAssertTrue(sample.isTouching)
		XCTAssertEqual(sample.point, .init(x: 0x234, y: 0xABC))

		let lifted = try XCTUnwrap(S29RingReportDecoder.parseTouchReport([0x01, 0x00, 0xFF, 0xFF, 0xFF, 0x00]))
		XCTAssertFalse(lifted.isTouching)
		XCTAssertEqual(lifted.point, .init(x: 0xFFF, y: 0xFFF))
	}

	func testTouchReportRejectsShortOrForeignReports() {
		XCTAssertNil(S29RingReportDecoder.parseTouchReport([0x01, 0x01, 0x34, 0xC2]))
		XCTAssertNil(S29RingReportDecoder.parseTouchReport([0x03, 0x01, 0x34, 0xC2, 0xAB]))
		XCTAssertNil(S29RingReportDecoder.parseTouchReport([]))
	}

	func testConsumerReportParses24BitLittleEndianMask() {
		XCTAssertEqual(S29RingReportDecoder.parseConsumerReport([0x03, 0x08, 0x80, 0x09]), 0x09_8008)
		XCTAssertEqual(S29RingReportDecoder.parseConsumerReport([0x03, 0x00, 0x00, 0x01]), 1 << 16)
		XCTAssertNil(S29RingReportDecoder.parseConsumerReport([0x03, 0x08, 0x80]))
		XCTAssertNil(S29RingReportDecoder.parseConsumerReport([0x01, 0x08, 0x80, 0x09]))
	}

	func testSwipeDirectionsUseMirroredXAxis() {
		XCTAssertEqual(S29RingReportDecoder.swipeDirection(dx: 450, dy: 0), .left)
		XCTAssertEqual(S29RingReportDecoder.swipeDirection(dx: -450, dy: 0), .right)
		XCTAssertEqual(S29RingReportDecoder.swipeDirection(dx: 0, dy: 600), .up)
		XCTAssertEqual(S29RingReportDecoder.swipeDirection(dx: 0, dy: -600), .down)
		XCTAssertEqual(S29RingReportDecoder.swipeDirection(dx: 400, dy: 100), .left)
		XCTAssertEqual(S29RingReportDecoder.swipeDirection(dx: 100, dy: -500), .down)
	}

	func testSwipeDirectionRequiresDistanceAndDominance() {
		XCTAssertNil(S29RingReportDecoder.swipeDirection(dx: 399, dy: 0))
		XCTAssertNil(S29RingReportDecoder.swipeDirection(dx: 0, dy: 499))
		XCTAssertNil(S29RingReportDecoder.swipeDirection(dx: 450, dy: 300), "diagonal: neither axis dominates 2:1")
		XCTAssertNil(S29RingReportDecoder.swipeDirection(dx: 600, dy: 600))
	}

	func testControlsMapToDpadAndRingButtons() {
		XCTAssertEqual(S29RingControl.up.button, .dpadUp)
		XCTAssertEqual(S29RingControl.down.button, .dpadDown)
		XCTAssertEqual(S29RingControl.left.button, .dpadLeft)
		XCTAssertEqual(S29RingControl.right.button, .dpadRight)
		XCTAssertEqual(S29RingControl.camera.button, .s29Camera)
		XCTAssertEqual(S29RingControl.home.button, .s29Home)
	}
}

// MARK: - Decoder behavior

final class S29RingReportDecoderTests: XCTestCase {
	private var decoder = S29RingReportDecoder()
	private var events: [S29RingEvent] = []

	override func setUp() {
		super.setUp()
		decoder = S29RingReportDecoder()
		events = []
	}

	// MARK: Helpers

	private static func touchReport(down: Bool, x: Int, y: Int) -> [UInt8] {
		[
			0x01,
			down ? 0x01 : 0x00,
			UInt8(x & 0xFF),
			UInt8((x >> 8) & 0x0F) | UInt8((y & 0x0F) << 4),
			UInt8((y >> 4) & 0xFF),
		]
	}

	private static func consumerReport(bits: [Int]) -> [UInt8] {
		let mask = bits.reduce(UInt32(0)) { $0 | (UInt32(1) << UInt32($1)) }
		return [0x03, UInt8(mask & 0xFF), UInt8((mask >> 8) & 0xFF), UInt8((mask >> 16) & 0xFF)]
	}

	@discardableResult
	private func feed(_ report: [UInt8], at time: TimeInterval) -> [S29RingEvent] {
		let produced = decoder.process(report: report, at: time)
		events.append(contentsOf: produced)
		return produced
	}

	@discardableResult
	private func advance(to time: TimeInterval) -> [S29RingEvent] {
		let produced = decoder.advance(to: time)
		events.append(contentsOf: produced)
		return produced
	}

	/// Firmware pulse: the bit is set, then cleared, so each pulse is a new bit.
	private func pulse(bit: Int, at time: TimeInterval) {
		feed(Self.consumerReport(bits: [bit]), at: time)
		feed(Self.consumerReport(bits: []), at: time + 0.01)
	}

	/// One short touch from (x, y) to (x + dx, y + dy), lifting with the final
	/// coordinates.
	private func stroke(dx: Int = 0, dy: Int, at time: TimeInterval, x: Int = 2000, y: Int = 2000) {
		feed(Self.touchReport(down: true, x: x, y: y), at: time)
		feed(Self.touchReport(down: true, x: x + dx, y: y + dy), at: time + 0.01)
		feed(Self.touchReport(down: false, x: x + dx, y: y + dy), at: time + 0.02)
	}

	// MARK: Swipes

	func testSwipeFiresAsSoonAsThresholdIsCrossedWithoutWaitingForLift() {
		feed(Self.touchReport(down: true, x: 1000, y: 1000), at: 0)
		XCTAssertEqual(feed(Self.touchReport(down: true, x: 1200, y: 1000), at: 0.02), [])
		XCTAssertEqual(feed(Self.touchReport(down: true, x: 1450, y: 1010), at: 0.04), [.press(.left)])

		// Momentary: released a few tens of ms later, still before lift.
		XCTAssertEqual(advance(to: 0.075), [])
		XCTAssertEqual(advance(to: 0.085), [.release(.left)])

		// Further travel in the same touch does not fire again.
		XCTAssertEqual(feed(Self.touchReport(down: true, x: 1900, y: 1010), at: 0.1), [])
		XCTAssertEqual(feed(Self.touchReport(down: false, x: 1900, y: 1010), at: 0.12), [])
		XCTAssertEqual(advance(to: 5), [])
	}

	func testSwipeDirectionsIncludingMirroredX() {
		let cases: [(dx: Int, dy: Int, control: S29RingControl)] = [
			(500, 0, .left),
			(-500, 0, .right),
			(0, 600, .up),
			(0, -600, .down),
		]
		var time: TimeInterval = 0
		for (dx, dy, control) in cases {
			events = []
			feed(Self.touchReport(down: true, x: 2000, y: 2000), at: time)
			feed(Self.touchReport(down: true, x: 2000 + dx, y: 2000 + dy), at: time + 0.02)
			feed(Self.touchReport(down: false, x: 2000 + dx, y: 2000 + dy), at: time + 0.03)
			advance(to: time + 1)
			XCTAssertEqual(events, [.press(control), .release(control)], "dx=\(dx) dy=\(dy)")
			time += 2
		}
	}

	func testSwipeIsRecheckedOnLiftWhenNoSampleCrossedTheThreshold() {
		feed(Self.touchReport(down: true, x: 1000, y: 1000), at: 0)
		XCTAssertEqual(feed(Self.touchReport(down: true, x: 1000, y: 1300), at: 0.02), [])
		XCTAssertEqual(feed(Self.touchReport(down: false, x: 1000, y: 1550), at: 0.04), [.press(.up)])
		XCTAssertEqual(advance(to: 0.2), [.release(.up)])
	}

	func testZeroCoordinateLiftFallsBackToLastTouchedPosition() {
		feed(Self.touchReport(down: true, x: 1000, y: 1000), at: 0)
		feed(Self.touchReport(down: true, x: 800, y: 1000), at: 0.02)
		// A (0,0) lift would read as a huge swipe if taken literally.
		XCTAssertEqual(feed(Self.touchReport(down: false, x: 0, y: 0), at: 0.04), [])
		XCTAssertEqual(advance(to: 2), [])
	}

	// MARK: Consumer bits

	func testHomeTapIsMomentaryAndOnlyNewBitsCount() {
		XCTAssertEqual(feed(Self.consumerReport(bits: [3]), at: 0), [.press(.home)])
		// Repeating the same mask is not a new event.
		XCTAssertEqual(feed(Self.consumerReport(bits: [3]), at: 0.01), [])
		XCTAssertEqual(advance(to: 0.05), [.release(.home)])
		XCTAssertEqual(feed(Self.consumerReport(bits: []), at: 0.1), [])
		XCTAssertEqual(feed(Self.consumerReport(bits: [3]), at: 0.5), [.press(.home)])
		XCTAssertEqual(advance(to: 0.6), [.release(.home)])
	}

	func testHoldPulsesKeepControlHeldAndReleaseAfterPulsesStop() {
		let holdBits: [(bit: Int, control: S29RingControl)] = [(19, .home), (1, .camera), (15, .up)]
		var start: TimeInterval = 0
		for (bit, control) in holdBits {
			events = []
			pulse(bit: bit, at: start)
			pulse(bit: bit, at: start + 0.3)
			pulse(bit: bit, at: start + 0.6)
			XCTAssertEqual(events, [.press(control)], "bit \(bit) pulses should press once")

			XCTAssertEqual(advance(to: start + 0.6 + 0.74), [], "still held within the release delay")
			XCTAssertEqual(advance(to: start + 0.6 + 0.75), [.release(control)])
			XCTAssertEqual(advance(to: start + 10), [])
			start += 20
		}
	}

	func testMultipleNewBitsInOneReportAreAllHandled() {
		XCTAssertEqual(feed(Self.consumerReport(bits: [3, 15]), at: 0), [.press(.home), .press(.up)])
		XCTAssertEqual(advance(to: 0.05), [.release(.home)])
		XCTAssertEqual(advance(to: 0.75), [.release(.up)])
	}

	// MARK: Volume-down disambiguation

	func testLoneVolumeDownIsOneCameraTapAfterTheResolveWindow() {
		pulse(bit: 16, at: 0)
		XCTAssertEqual(events, [], "ambiguous until the follow-up window passes")
		XCTAssertEqual(advance(to: 0.74), [])
		XCTAssertEqual(advance(to: 0.75), [.press(.camera)])
		XCTAssertEqual(advance(to: 0.785), [])
		XCTAssertEqual(advance(to: 0.795), [.release(.camera)])
		XCTAssertEqual(advance(to: 5), [])
	}

	func testQuickSecondVolumeDownIsCameraDoubleTap() {
		pulse(bit: 16, at: 0)
		pulse(bit: 16, at: 0.3)
		advance(to: 5)
		XCTAssertEqual(events, [.press(.camera), .release(.camera), .press(.camera), .release(.camera)])
	}

	func testCameraDoubleTapEmitsTwoSeparatedTaps() {
		pulse(bit: 16, at: 0)
		feed(Self.consumerReport(bits: [16]), at: 0.4)
		XCTAssertEqual(events, [.press(.camera)])
		XCTAssertEqual(advance(to: 0.445), [.release(.camera)])
		XCTAssertEqual(advance(to: 0.475), [], "the second tap is separated from the first")
		XCTAssertEqual(advance(to: 0.485), [.press(.camera)])
		XCTAssertEqual(advance(to: 0.525), [.release(.camera)])
	}

	func testLaterSecondVolumeDownStartsDownHold() {
		pulse(bit: 16, at: 0)
		pulse(bit: 16, at: 0.5)
		XCTAssertEqual(events, [.press(.down)])

		// While Down is held every occurrence is another pulse.
		pulse(bit: 16, at: 0.9)
		pulse(bit: 16, at: 1.3)
		XCTAssertEqual(events, [.press(.down)])

		XCTAssertEqual(advance(to: 1.3 + 0.74), [])
		XCTAssertEqual(advance(to: 1.3 + 0.75), [.release(.down)])
		XCTAssertEqual(advance(to: 10), [], "no stray Camera tap from the first occurrence")
	}

	func testVolumeDownAfterDownHoldEndsIsAmbiguousAgain() {
		pulse(bit: 16, at: 0)
		pulse(bit: 16, at: 0.5)
		advance(to: 2)
		events = []

		pulse(bit: 16, at: 3)
		advance(to: 5)
		XCTAssertEqual(events, [.press(.camera), .release(.camera)])
	}

	// MARK: Left/Right hold bursts

	func testBurstWithOnePositiveStrokeIsLeftHoldPulse() {
		stroke(dy: 300, at: 0)
		stroke(dy: -150, at: 0.15)
		stroke(dy: -150, at: 0.3)
		XCTAssertEqual(events, [.press(.left)])
		XCTAssertEqual(advance(to: 0.32 + 0.73), [])
		XCTAssertEqual(advance(to: 0.32 + 0.76), [.release(.left)])
	}

	func testBurstWithThreePositiveStrokesIsRightHoldPulse() {
		stroke(dy: 300, at: 0)
		stroke(dy: 150, at: 0.15)
		stroke(dy: 150, at: 0.3)
		XCTAssertEqual(events, [.press(.right)])
		advance(to: 2)
		XCTAssertEqual(events, [.press(.right), .release(.right)])
	}

	func testRepeatedBurstsKeepTheHoldAlive() {
		for burst in 0..<3 {
			let start = TimeInterval(burst) * 0.6
			stroke(dy: 300, at: start)
			stroke(dy: -150, at: start + 0.15)
			stroke(dy: -150, at: start + 0.3)
		}
		XCTAssertEqual(events, [.press(.left)])
		advance(to: 1.52 + 0.73)
		XCTAssertEqual(events, [.press(.left)], "held until the last burst's pulse times out")
		advance(to: 1.52 + 0.76)
		XCTAssertEqual(events, [.press(.left), .release(.left)])
	}

	func testBurstWithTwoPositiveStrokesIsIgnored() {
		stroke(dy: 300, at: 0)
		stroke(dy: 150, at: 0.15)
		stroke(dy: -150, at: 0.3)
		advance(to: 5)
		XCTAssertEqual(events, [])
	}

	func testBurstMustStartWithLongPositiveStroke() {
		stroke(dy: 200, at: 0)
		stroke(dy: -150, at: 0.15)
		stroke(dy: -150, at: 0.3)
		advance(to: 5)
		XCTAssertEqual(events, [])
	}

	func testOutOfBoundsStrokeResetsBurstDetection() {
		stroke(dy: 300, at: 0)
		stroke(dx: 60, dy: -150, at: 0.1) // too much horizontal drift
		stroke(dy: -150, at: 0.2)
		stroke(dy: -150, at: 0.3)
		advance(to: 5)
		XCTAssertEqual(events, [])

		events = []
		stroke(dy: 300, at: 10)
		stroke(dy: -40, at: 10.1) // too short to be a stroke
		stroke(dy: -150, at: 10.2)
		stroke(dy: -150, at: 10.3)
		advance(to: 15)
		XCTAssertEqual(events, [])
	}

	func testStrokesOutsideTheBurstWindowDoNotCombine() {
		stroke(dy: 300, at: 0)
		stroke(dy: -150, at: 0.3)
		stroke(dy: -150, at: 0.7)
		advance(to: 5)
		XCTAssertEqual(events, [])
	}

	// MARK: Reset

	func testResetReleasesHeldButtonsAndDropsPendingWork() {
		pulse(bit: 19, at: 0)          // Home held
		pulse(bit: 16, at: 0.1)        // pending Camera-tap ambiguity
		stroke(dy: 300, at: 0.2)       // partial burst
		feed(Self.touchReport(down: true, x: 1000, y: 1000), at: 0.3) // touch in progress
		XCTAssertEqual(events, [.press(.home)])

		XCTAssertEqual(decoder.reset(), [.release(.home)])
		XCTAssertNil(decoder.nextDeadline)
		XCTAssertTrue(decoder.pressedControls.isEmpty)
		XCTAssertEqual(decoder.advance(to: 10), [])

		// A touch that began before the reset can't complete a swipe after it.
		XCTAssertEqual(decoder.process(report: Self.touchReport(down: true, x: 1600, y: 1000), at: 11), [])
	}

	func testResetReleasesAMomentaryTapThatIsStillDown() {
		feed(Self.consumerReport(bits: [3]), at: 0)
		XCTAssertEqual(decoder.reset(), [.release(.home)])
		XCTAssertEqual(decoder.advance(to: 1), [])
	}

	func testNextDeadlineTracksPendingWork() {
		XCTAssertNil(decoder.nextDeadline)
		feed(Self.consumerReport(bits: [16]), at: 1)
		XCTAssertEqual(decoder.nextDeadline ?? -1, 1.75, accuracy: 0.0001)
	}

	func testUnknownReportsAreIgnored() {
		XCTAssertEqual(feed([0x02, 0xFF, 0xFF, 0xFF, 0xFF], at: 0), [])
		XCTAssertEqual(feed([0x03, 0xFF], at: 0.1), [])
		XCTAssertNil(decoder.nextDeadline)
	}
}

// MARK: - Buttons, presentation, and connection

final class S29RingButtonTests: XCTestCase {
	func testRingButtonSetsReuseDpadAndAddCameraAndHome() {
		XCTAssertEqual(ControllerButton.s29RingDirectionButtons, [.dpadUp, .dpadDown, .dpadLeft, .dpadRight])
		XCTAssertEqual(ControllerButton.s29RingActionButtons, [.s29Camera, .s29Home])
		XCTAssertEqual(ControllerButton.s29RingButtons.count, 6)
		XCTAssertTrue(ControllerButton.s29Camera.isS29RingOnly)
		XCTAssertTrue(ControllerButton.s29Home.isS29RingOnly)
		XCTAssertFalse(ControllerButton.dpadUp.isS29RingOnly)
		XCTAssertEqual(ControllerButton.s29Camera.displayName, "Camera")
		XCTAssertEqual(ControllerButton.s29Home.displayName, "Home")
	}

	func testRingOnlyButtonsStayOffGamepadLayouts() {
		for list in [
			ControllerButton.xboxButtons,
			ControllerButton.dualSenseButtons,
			ControllerButton.dualShockButtons,
			ControllerButton.nintendoButtons,
		] {
			XCTAssertFalse(list.contains(.s29Camera))
			XCTAssertFalse(list.contains(.s29Home))
		}
	}
}

@MainActor
final class S29RingPresentationTests: XCTestCase {
	func testS29DescriptorIsAListLayoutWithRingControlsOnly() {
		let descriptor = ControllerVisualDescriptor(family: .s29Ring)
		XCTAssertTrue(descriptor.isS29Ring)
		XCTAssertFalse(descriptor.hasSticks)
		XCTAssertFalse(descriptor.hasTriggers)
		XCTAssertFalse(descriptor.supportsCommandWheel)
		XCTAssertNil(descriptor.minimapStyle)
		XCTAssertEqual(descriptor.shoulderButtons(side: .left), [])
		XCTAssertEqual(descriptor.leftSystemButtons, [])
		XCTAssertEqual(descriptor.rightSystemButtons, [])
		XCTAssertEqual(descriptor.supportedButtons, Set(ControllerButton.s29RingButtons))
		XCTAssertEqual(descriptor.displayName, "S29 Ring")
	}

	func testS29PreviewLayoutMetadataAndGuide() throws {
		let layout = ControllerPreviewLayout.s29Ring
		XCTAssertEqual(layout.displayName, "S29 Ring")
		XCTAssertEqual(layout.platformLabel, "Bluetooth button ring")
		XCTAssertEqual(ControllerVisualDescriptor.concrete(for: layout)?.family, .s29Ring)

		let guide = try XCTUnwrap(layout.pairingGuide)
		XCTAssertTrue(guide.bluetoothSteps.contains { $0.contains("S29") })
		XCTAssertTrue(guide.tip?.contains("exclusive control") == true)
	}

	func testActiveDescriptorPrecedence() {
		let xbox = ControllerPresentationState(controllerType: .xbox, eightBitDoModel: nil)
		XCTAssertEqual(
			ControllerVisualDescriptor.active(
				from: xbox, ouraRingIsActive: false, beamdeskHandsAreActive: false, s29RingIsActive: true
			).family,
			.s29Ring
		)
		XCTAssertEqual(
			ControllerVisualDescriptor.active(
				from: xbox, ouraRingIsActive: true, beamdeskHandsAreActive: false, s29RingIsActive: true
			).family,
			.ouraRing
		)
		XCTAssertEqual(
			ControllerVisualDescriptor.active(
				from: xbox, ouraRingIsActive: false, beamdeskHandsAreActive: false
			).family,
			.xbox
		)
	}

	func testConnectionPublishesS29RingAsTheActiveController() {
		let controllerService = ControllerService(enableHardwareMonitoring: false)

		controllerService.setS29RingConnected(true)
		XCTAssertTrue(controllerService.isConnected)
		XCTAssertTrue(controllerService.isS29RingActiveInputSource)
		XCTAssertEqual(controllerService.controllerName, "S29 Ring")
		XCTAssertEqual(ControllerVisualDescriptor.active(using: controllerService).family, .s29Ring)

		controllerService.setS29RingConnected(false)
		XCTAssertFalse(controllerService.isConnected)
		XCTAssertFalse(controllerService.isS29RingConnected)
		XCTAssertEqual(controllerService.controllerName, "")
		controllerService.cleanup()
	}

	func testS29RingOutranksBeamdeskAndHandsBackOnDisconnect() {
		let controllerService = ControllerService(enableHardwareMonitoring: false)

		controllerService.setBeamdeskHandsConnected(true)
		XCTAssertEqual(controllerService.controllerName, "Beamdesk Hands")
		controllerService.setS29RingConnected(true)
		XCTAssertEqual(controllerService.controllerName, "S29 Ring", "the ring outranks Beamdesk hands")

		controllerService.setBeamdeskHandsConnected(false)
		XCTAssertTrue(controllerService.isConnected)
		XCTAssertEqual(controllerService.controllerName, "S29 Ring")

		controllerService.setBeamdeskHandsConnected(true)
		XCTAssertEqual(controllerService.controllerName, "S29 Ring", "Beamdesk never displaces the ring")

		controllerService.setS29RingConnected(false)
		XCTAssertEqual(controllerService.controllerName, "Beamdesk Hands")
		controllerService.cleanup()
	}
}
