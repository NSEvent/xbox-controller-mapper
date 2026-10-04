import Foundation
import Combine

/// Keeps a real-action test on the intended profile and records only ready visits to the target app.
@MainActor
final class GuidedPresetTestSession: ObservableObject {
	@Published private(set) var isTesting = false
	@Published private(set) var visitedTarget = false
	@Published private(set) var interruption = ""
	private var token: UUID?
	private weak var profiles: ProfileManager?
	private var subscriptions = Set<AnyCancellable>()

	func start(profileId: UUID, targetBundleId: String, engine: MappingEngine, accessibility: @escaping () -> Bool) {
		stop()
		guard engine.profileManager.activeProfileId == profileId,
			  let token = engine.profileManager.beginGuidedRouting(profileId: profileId) else { return }
		self.token = token; profiles = engine.profileManager
		visitedTarget = false; interruption = ""; isTesting = true
		engine.appMonitor.$frontmostBundleId.sink { [weak self, weak engine] bundle in
			guard let self, let engine, bundle == targetBundleId,
				  self.isReady(profileId: profileId, engine: engine, accessibilityGranted: accessibility()) else { return }
			self.visitedTarget = true
		}.store(in: &subscriptions)
		engine.profileManager.$activeProfileId.dropFirst().sink { [weak self] id in
			if id != profileId { self?.interrupt("Profile changed. Select the saved preset and restart its test.") }
		}.store(in: &subscriptions)
		engine.controllerService.$isConnected.dropFirst().sink { [weak self] _ in
			self?.interrupt("Controller changed or disconnected. Restart the test with the current controller.")
		}.store(in: &subscriptions)
	}
	func isReady(profileId: UUID, engine: MappingEngine, accessibilityGranted: Bool) -> Bool {
		isTesting && engine.controllerService.isConnected && accessibilityGranted && engine.isEnabled &&
		!engine.isLocked && engine.inputPreviewCount == 0 && engine.profileManager.activeProfileId == profileId
	}
	func stop() {
		subscriptions.removeAll(); isTesting = false
		if let token { profiles?.endGuidedRouting(token) }
		token = nil
	}
	private func interrupt(_ reason: String) { stop(); visitedTarget = false; interruption = reason }
}
