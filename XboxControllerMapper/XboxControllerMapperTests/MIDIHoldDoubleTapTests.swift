import XCTest
@testable import ControllerKeys

/// A MIDI hold mapping with a double-tap: the second press fires the
/// double-tap, and its release must not later fire a single tap.
final class MIDIHoldDoubleTapTests: MappingEngineTestCase {
	func testDoubleTapReleaseDoesNotFireSpuriousSingleTap() async {
		await runDoubleTap(gap: 0.05)
	}

	func testSpacedDoubleTapReleaseDoesNotFireSpuriousSingleTap() async {
		await runDoubleTap(gap: 0.15)
	}

	private func runDoubleTap(gap: TimeInterval) async {
		let message = MIDIControlChange(channel: 2, controller: 30, pressValue: 127, releaseValue: 0)
		let mapping = KeyMapping(
			doubleTapMapping: DoubleTapMapping(keyCode: 20, threshold: 0.6),
			midiControlChange: message
		)
		await MainActor.run {
			profileManager.setActiveProfile(Profile(name: "MIDI", buttonMappings: [.a: mapping]))
		}
		await waitForTasks(0.05)

		await MainActor.run { controllerService.buttonPressed(.a) }
		await waitForTasks(gap)
		await MainActor.run { controllerService.buttonReleased(.a) }
		await waitForTasks(gap)
		await MainActor.run { controllerService.buttonPressed(.a) }
		await waitForTasks(gap)
		await MainActor.run { controllerService.buttonReleased(.a) }
		// Past the double-tap window, where a pending single tap would fire.
		await waitForTasks(1.0)

		XCTAssertEqual(mockMIDIService.events, [.press(message), .release(message)],
					   "only the first press holds the MIDI control")
		let doubleTaps = mockInputSimulator.events.filter {
			if case .pressKey(20, _) = $0 { return true }
			return false
		}
		XCTAssertEqual(doubleTaps.count, 1)
	}
}
