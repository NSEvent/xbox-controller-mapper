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
}
