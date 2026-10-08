import Foundation

@MainActor
extension ProfileManager {
	func communitySharingSource(for profile: Profile) -> Profile {
		var copy = profiles.first { $0.id == profile.id } ?? profile
		copy.onScreenKeyboardSettings = resolvedOnScreenKeyboardSettings(for: copy)
		copy.sharedMacroSnapshots = SharedMacroSnapshotPolicy.syncedSnapshots(for: copy, store: sharedMacroStore)
		return copy
	}
}
