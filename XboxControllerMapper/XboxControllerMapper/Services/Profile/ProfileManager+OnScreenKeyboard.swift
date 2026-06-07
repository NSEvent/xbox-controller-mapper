import Foundation
import SwiftUI

@MainActor
extension ProfileManager {
    var activeOnScreenKeyboardSourceProfile: Profile? {
	guard let activeProfile else { return nil }
	return onScreenKeyboardSettingsOwner(for: activeProfile)
    }

    func resolvedOnScreenKeyboardSettings(for profile: Profile) -> OnScreenKeyboardSettings {
	onScreenKeyboardSettingsOwner(for: profile)?.onScreenKeyboardSettings ?? profile.onScreenKeyboardSettings
    }

    func inheritedOnScreenKeyboardSource(for profile: Profile) -> Profile? {
	guard let sourceId = profile.inheritedOnScreenKeyboardProfileId,
	      sourceId != profile.id else {
	    return nil
	}
	return profiles.first { $0.id == sourceId }
    }

    func onScreenKeyboardInheritanceCandidates(for profile: Profile) -> [Profile] {
	profiles.filter { candidate in
	    candidate.id != profile.id && !wouldCreateOnScreenKeyboardInheritanceCycle(
		profileId: profile.id,
		sourceProfileId: candidate.id
	    )
	}
    }

    func setOnScreenKeyboardInheritance(for profile: Profile, sourceProfileId: UUID?) {
	var updatedProfile = profiles.first { $0.id == profile.id } ?? profile
	if let sourceProfileId,
	   profiles.contains(where: { $0.id == sourceProfileId }),
	   sourceProfileId != updatedProfile.id,
	   !wouldCreateOnScreenKeyboardInheritanceCycle(profileId: updatedProfile.id, sourceProfileId: sourceProfileId) {
	    updatedProfile.inheritedOnScreenKeyboardProfileId = sourceProfileId
	} else {
	    updatedProfile.inheritedOnScreenKeyboardProfileId = nil
	}
	updateProfile(updatedProfile)
    }

    @discardableResult
    private func mutateActiveOnScreenKeyboardSettings(
        _ mutate: (inout OnScreenKeyboardSettings) -> Bool
    ) -> Bool {
	guard let activeProfile else { return false }
	let targetProfileId = onScreenKeyboardSettingsOwner(for: activeProfile)?.id ?? activeProfile.id
	guard var profile = profiles.first(where: { $0.id == targetProfileId }) else { return false }
        let didChange = mutate(&profile.onScreenKeyboardSettings)
        if didChange {
            updateProfile(profile)
	    if targetProfileId != activeProfile.id {
		self.activeProfile = activeProfile
	    }
        }
        return didChange
    }

    private func wouldCreateOnScreenKeyboardInheritanceCycle(profileId: UUID, sourceProfileId: UUID) -> Bool {
	var seen: Set<UUID> = [profileId]
	var cursor: UUID? = sourceProfileId
	while let currentId = cursor {
	    guard seen.insert(currentId).inserted else { return true }
	    cursor = profiles.first { $0.id == currentId }?.inheritedOnScreenKeyboardProfileId
	}
	return false
    }

    private func onScreenKeyboardSettingsOwner(for profile: Profile) -> Profile? {
	var seen: Set<UUID> = [profile.id]
	var current = profile
	while let sourceId = current.inheritedOnScreenKeyboardProfileId,
	      sourceId != current.id {
	    guard seen.insert(sourceId).inserted,
		  let source = profiles.first(where: { $0.id == sourceId }) else {
		return nil
	    }
	    current = source
	}
	return current.id == profile.id ? nil : current
    }

    // MARK: - On-Screen Keyboard Settings

    func updateOnScreenKeyboardSettings(_ settings: OnScreenKeyboardSettings) {
        mutateActiveOnScreenKeyboardSettings { current in
            current = settings
            return true
        }
    }

    func addQuickText(_ quickText: QuickText) {
        mutateActiveOnScreenKeyboardSettings { settings in
            settings.quickTexts.append(quickText)
            return true
        }
    }

    func removeQuickText(_ quickText: QuickText) {
        mutateActiveOnScreenKeyboardSettings { settings in
            settings.quickTexts.removeAll { $0.id == quickText.id }
            return true
        }
    }

    func updateQuickText(_ quickText: QuickText) {
        mutateActiveOnScreenKeyboardSettings { settings in
            if let index = settings.quickTexts.firstIndex(where: { $0.id == quickText.id }) {
                settings.quickTexts[index] = quickText
            }
            return true
        }
    }

    func moveQuickTexts(from source: IndexSet, to destination: Int) {
        mutateActiveOnScreenKeyboardSettings { settings in
            settings.quickTexts.move(fromOffsets: source, toOffset: destination)
            return true
        }
    }

    func setDefaultTerminalApp(_ appName: String) {
        mutateActiveOnScreenKeyboardSettings { settings in
            settings.defaultTerminalApp = appName
            return true
        }
    }

    func setTypingDelay(_ delay: Double) {
        mutateActiveOnScreenKeyboardSettings { settings in
            settings.typingDelay = delay
            return true
        }
    }

    // MARK: - App Bar Items

    func addAppBarItem(_ item: AppBarItem) {
        mutateActiveOnScreenKeyboardSettings { settings in
            settings.appBarItems.append(item)
            return true
        }
    }

    func removeAppBarItem(_ item: AppBarItem) {
        mutateActiveOnScreenKeyboardSettings { settings in
            settings.appBarItems.removeAll { $0.id == item.id }
            return true
        }
    }

    func moveAppBarItems(from source: IndexSet, to destination: Int) {
        mutateActiveOnScreenKeyboardSettings { settings in
            settings.appBarItems.move(fromOffsets: source, toOffset: destination)
            return true
        }
    }

    func updateAppBarItem(_ item: AppBarItem) {
        mutateActiveOnScreenKeyboardSettings { settings in
            guard let index = settings.appBarItems.firstIndex(where: { $0.id == item.id }) else {
                return false
            }
            settings.appBarItems[index] = item
            return true
        }
    }

    // MARK: - Website Links

    func addWebsiteLink(_ link: WebsiteLink) {
        mutateActiveOnScreenKeyboardSettings { settings in
            settings.websiteLinks.append(link)
            return true
        }
    }

    func removeWebsiteLink(_ link: WebsiteLink) {
        mutateActiveOnScreenKeyboardSettings { settings in
            settings.websiteLinks.removeAll { $0.id == link.id }
            return true
        }
    }

    func updateWebsiteLink(_ link: WebsiteLink) {
        mutateActiveOnScreenKeyboardSettings { settings in
            guard let index = settings.websiteLinks.firstIndex(where: { $0.id == link.id }) else {
                return false
            }
            settings.websiteLinks[index] = link
            return true
        }
    }

    func moveWebsiteLinks(from source: IndexSet, to destination: Int) {
        mutateActiveOnScreenKeyboardSettings { settings in
            settings.websiteLinks.move(fromOffsets: source, toOffset: destination)
            return true
        }
    }
}
