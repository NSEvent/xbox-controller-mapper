import XCTest
@testable import ControllerKeys

@MainActor
final class FootPedalSequencePlaybackTests: MappingEngineTestCase {
	private var decoder = FootPedalReportDecoder()

	private func configure() {
		controllerService.chordWindow = 0.15
		controllerService.setFootPedalConnected(true)
		profileManager.bindControllerPreview(to: controllerService)
		profileManager.setActiveProfile(Profile(name: "Pedal sequence", buttonMappings: [:],
			chordMappings: [
				ChordMapping(buttons: [.footPedalLeft, .footPedalMiddle], keyCode: 8),
				ChordMapping(buttons: [.footPedalMiddle, .footPedalRight], keyCode: 36)
			], sequenceMappings: [SequenceMapping(chordSteps: [
				SequenceStep([.footPedalLeft, .footPedalMiddle]),
				SequenceStep([.footPedalMiddle, .footPedalRight])
			], stepTimeout: 0.4, keyCode: 40)]))
	}

	private func report(_ mask: UInt8) async {
		for event in decoder.process(report: [mask, 0]) { controllerService.handleFootPedalInput(event) }
		let controllerQueue = controllerService.controllerQueue
		let inputQueue = mappingEngine.inputQueue
		await withCheckedContinuation { continuation in
			controllerQueue.async {
				DispatchQueue.main.async {
					inputQueue.async { continuation.resume() }
				}
			}
		}
	}

	private var sequenceActionCount: Int {
		mockInputSimulator.events.filter { if case .pressKey(40, _) = $0 { return true }; return false }.count
	}

	func testExactLeftMiddleThenMiddleRightThroughHIDReports() async {
		configure()
		await report(0b011)
		await waitForTasks(0.17)
		await report(0)
		await waitForTasks(0.05)
		await report(0b110)
		await waitForTasks(0.17)
		XCTAssertEqual(sequenceActionCount, 0)
		await report(0)
		XCTAssertEqual(sequenceActionCount, 1)
	}

	func testSeparateReportsForEachPedalStillFormSequenceChords() async {
		configure()
		await report(0b001)
		await report(0b011)
		await waitForTasks(0.17)
		await report(0b010)
		await report(0)
		await report(0b100)
		await report(0b110)
		await waitForTasks(0.17)
		await report(0b010)
		XCTAssertEqual(sequenceActionCount, 0)
		await report(0)
		XCTAssertEqual(sequenceActionCount, 1)
	}
}
