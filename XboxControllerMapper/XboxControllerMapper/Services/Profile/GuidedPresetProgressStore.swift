import Foundation
import Combine

struct GuidedPresetProgress: Codable, Equatable {
	var preset: GuidedPreset
	var hand: JoystickSide
	var targetBundleId: String
	var verifiedAt: Date?
}

@MainActor
final class GuidedPresetProgressStore: ObservableObject {
	static let shared = GuidedPresetProgressStore()
	@Published private(set) var entries: [String: GuidedPresetProgress]
	private let defaults: UserDefaults
	private let key = "guidedPresetProgress.v1"
	init(defaults: UserDefaults = .standard) {
		self.defaults = defaults
		entries = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([String: GuidedPresetProgress].self, from: $0) } ?? [:]
	}
	func save(_ progress: GuidedPresetProgress, for profileId: UUID) {
		entries[profileId.uuidString] = progress
		if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: key) }
	}
	func complete(_ profileId: UUID) {
		guard var progress = entries[profileId.uuidString] else { return }
		progress.verifiedAt = Date(); save(progress, for: profileId)
	}
	func pending(in profiles: [Profile]) -> [Profile] {
		profiles.filter { entries[$0.id.uuidString].map { $0.verifiedAt == nil } ?? false }
	}
}
