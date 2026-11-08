import XCTest
@testable import ControllerKeys

/// A button pressed while input routes to the Universal Control peer must
/// finish on the peer even if the cursor returns before it is released.
final class UniversalControlHandoffReleaseTests: MappingEngineTestCase {

	override func tearDown() async throws {
		UniversalControlMouseRelay.shared.setRemoteSessionActive(false)
		UniversalControlMouseRelay.shared.setDropsOutgoingMessagesForTesting(false)
		try await super.tearDown()
	}

	func testRemotePressReleasedAfterReturnDoesNotFireLocally() async throws {
		let profile = Profile(name: "Remote", buttonMappings: [.a: .key(10)])
		await MainActor.run { profileManager.installTestProfile(profile) }

		UniversalControlMouseRelay.shared.setDropsOutgoingMessagesForTesting(true)
		UniversalControlMouseRelay.shared.setRemoteSessionActive(true)
		await MainActor.run { controllerService.buttonPressed(.a) }
		await waitForTasks(0.15)

		// Cursor returns to this Mac while A is still held.
		UniversalControlMouseRelay.shared.setRemoteSessionActive(false)
		await MainActor.run { controllerService.buttonReleased(.a) }
		await waitForTasks(0.4)

		let localKeyEvents = mockInputSimulator.events.filter {
			switch $0 {
			case .pressKey(10, _), .keyDown(10), .keyUp(10): return true
			default: return false
			}
		}
		XCTAssertTrue(localKeyEvents.isEmpty, "a peer press must not end as a local tap: \(localKeyEvents)")
		let stillTracked = await MainActor.run {
			let state = mappingEngine.state
			return state.lock.withLock { state.remoteRoutedButtons.contains(.a) }
		}
		XCTAssertFalse(stillTracked)
	}

	func testRemoteChordReleasedAfterReturnDoesNotFireLocally() async throws {
		let profile = Profile(name: "Remote", buttonMappings: [.a: .key(10), .b: .key(11)])
		await MainActor.run { profileManager.installTestProfile(profile) }

		UniversalControlMouseRelay.shared.setDropsOutgoingMessagesForTesting(true)
		UniversalControlMouseRelay.shared.setRemoteSessionActive(true)
		await MainActor.run {
			controllerService.buttonPressed(.a)
			controllerService.buttonPressed(.b)
		}
		await waitForTasks(0.2)

		UniversalControlMouseRelay.shared.setRemoteSessionActive(false)
		await MainActor.run {
			controllerService.buttonReleased(.a)
			controllerService.buttonReleased(.b)
		}
		await waitForTasks(0.4)

		let localKeyEvents = mockInputSimulator.events.filter {
			switch $0 {
			case .pressKey(10, _), .pressKey(11, _), .keyDown(10), .keyDown(11), .keyUp(10), .keyUp(11): return true
			default: return false
			}
		}
		XCTAssertTrue(localKeyEvents.isEmpty, "a peer chord must not end as local taps: \(localKeyEvents)")
	}

	func testLostPeerReleaseDoesNotSwallowTheNextLocalPress() async throws {
		let profile = Profile(name: "Remote", buttonMappings: [.a: .key(10)])
		await MainActor.run { profileManager.installTestProfile(profile) }

		UniversalControlMouseRelay.shared.setDropsOutgoingMessagesForTesting(true)
		UniversalControlMouseRelay.shared.setRemoteSessionActive(true)
		await MainActor.run { controllerService.buttonPressed(.a) }
		await waitForTasks(0.15)
		// The release of that peer press never arrives (e.g. the controller dropped).
		UniversalControlMouseRelay.shared.setRemoteSessionActive(false)
		await MainActor.run { controllerService.storage.lock.withLock { _ = controllerService.storage.activeButtons.remove(.a) } }

		await MainActor.run { controllerService.buttonPressed(.a) }
		await waitForTasks(0.15)
		await MainActor.run { controllerService.buttonReleased(.a) }
		await waitForTasks(0.5)

		let localTaps = mockInputSimulator.events.filter {
			if case .pressKey(10, _) = $0 { return true }
			return false
		}
		XCTAssertEqual(localTaps.count, 1, "the local press must end locally: \(mockInputSimulator.events)")
	}
}
