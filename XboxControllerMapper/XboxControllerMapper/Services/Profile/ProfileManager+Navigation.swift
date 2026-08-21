import Foundation

enum ProfileNavigationResolver {
	static func targetProfileId(
		for action: ProfileNavigationAction,
		profiles: [Profile],
		activeProfileId: UUID?,
		lastActiveProfileId: UUID?
	) -> UUID? {
		guard profiles.count > 1 else { return nil }

		switch action {
		case .lastUsed:
			guard let lastActiveProfileId,
			      lastActiveProfileId != activeProfileId,
			      profiles.contains(where: { $0.id == lastActiveProfileId }) else {
				return nil
			}
			return lastActiveProfileId

		case .next, .previous:
			guard let activeProfileId,
			      let activeIndex = profiles.firstIndex(where: { $0.id == activeProfileId }) else {
				return nil
			}
			let offset = action == .next ? 1 : profiles.count - 1
			return profiles[(activeIndex + offset) % profiles.count].id
		}
	}
}

extension ProfileManager {
	@discardableResult
	func navigateProfile(_ action: ProfileNavigationAction) -> Bool {
		guard let targetId = ProfileNavigationResolver.targetProfileId(
			for: action,
			profiles: profiles,
			activeProfileId: activeProfileId,
			lastActiveProfileId: lastActiveProfileId
		), let target = profiles.first(where: { $0.id == targetId }) else {
			return false
		}

		setActiveProfile(target)
		return true
	}
}
