import AppKit
import XCTest
@testable import ControllerKeys

@MainActor
final class TriggerMIDIMeterTests: XCTestCase {
	func testSamplesClampInvalidPressureAndSuppressSubPixelNoise() {
		XCTAssertEqual(TriggerMIDIMeterSample(raw: .nan, detail: "").pressure, 0)
		XCTAssertEqual(TriggerMIDIMeterSample(raw: 1.4, detail: "").pressure, 1)
		XCTAssertEqual(TriggerMIDIMeterSample(raw: -0.2, detail: "").pressure, 0)
		XCTAssertEqual(TriggerMIDIMeterSample(raw: 0.50001, detail: "CC 64"), TriggerMIDIMeterSample(raw: 0.50002, detail: "CC 64"))
	}
	func testChangingRawInputDrawsLatestValueWithoutAnimationOrUnchangedRedraws() {
		var pressure = 0.0
		let view = TriggerMIDIMeterView(frame: NSRect(x: 0, y: 0, width: 500, height: 54))
		view.sample = { TriggerMIDIMeterSample(raw: pressure, detail: "preview") }
		view.refresh(); view.refresh()
		XCTAssertEqual(view.updateCount, 1)
		pressure = 1; view.refresh()
		XCTAssertEqual(view.displayed?.pressure, 1)
		pressure = 0; view.refresh()
		XCTAssertEqual(view.displayed?.pressure, 0)
		XCTAssertEqual(view.updateCount, 3)
	}
	func testVisibleMeterSamplesWithinTwoFramesAndStopsAfterDetaching() async {
		var raw = 0.0
		let view = TriggerMIDIMeterView(frame: NSRect(x: 0, y: 0, width: 500, height: 54))
		view.sample = { TriggerMIDIMeterSample(raw: raw, detail: "preview") }
		let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
		window.isReleasedWhenClosed = false; window.contentView = view
		defer { view.stop(); window.close() }
		raw = 0.9
		try? await Task.sleep(for: .milliseconds(40))
		XCTAssertEqual(view.displayed?.pressure, 0.9)
		window.contentView = nil
		let updates = view.updateCount; raw = 0.2
		try? await Task.sleep(for: .milliseconds(40))
		XCTAssertEqual(view.updateCount, updates)
	}
}
