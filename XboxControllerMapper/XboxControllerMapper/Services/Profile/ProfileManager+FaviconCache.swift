import Foundation
import Combine

@MainActor
extension ProfileManager {
    // MARK: - Favicon Cache

    /// Load cached favicons for all website links in all profiles.
    func loadCachedFavicons() {
        for i in 0..<profiles.count {
            for j in 0..<profiles[i].onScreenKeyboardSettings.websiteLinks.count {
                let link = profiles[i].onScreenKeyboardSettings.websiteLinks[j]
                if link.faviconData == nil {
                    if let cached = FaviconCache.shared.loadCachedFavicon(for: link.url) {
                        profiles[i].onScreenKeyboardSettings.websiteLinks[j].faviconData = cached
                    }
                }
            }
        }

        // Update activeProfile reference
        if let activeId = activeProfileId,
           let profile = profiles.first(where: { $0.id == activeId }) {
            activeProfile = profile
        }

        // Trigger async refetch for any still-missing favicons
        refetchMissingFavicons()
    }

    /// Refetch favicons that are missing from cache.
    private func refetchMissingFavicons() {
        struct MissingFaviconRequest {
            let profileId: UUID
            let linkId: UUID
            let url: String
        }

        let pendingRequests: [MissingFaviconRequest] = profiles.flatMap { profile in
            profile.onScreenKeyboardSettings.websiteLinks.compactMap { link in
                guard link.faviconData == nil else { return nil }
                return MissingFaviconRequest(profileId: profile.id, linkId: link.id, url: link.url)
            }
        }

        guard !pendingRequests.isEmpty else { return }

        Task { @MainActor in
            var anyUpdated = false

            for request in pendingRequests {
                if Task.isCancelled { break }

                guard let data = await FaviconCache.shared.fetchFavicon(for: request.url) else {
                    continue
                }

                guard let profileIndex = profiles.firstIndex(where: { $0.id == request.profileId }) else {
                    continue
                }
                guard let linkIndex = profiles[profileIndex]
                    .onScreenKeyboardSettings
                    .websiteLinks
                    .firstIndex(where: { $0.id == request.linkId }) else {
                    continue
                }

                if profiles[profileIndex].onScreenKeyboardSettings.websiteLinks[linkIndex].faviconData == nil {
                    profiles[profileIndex].onScreenKeyboardSettings.websiteLinks[linkIndex].faviconData = data
                    anyUpdated = true
                }
            }

            if anyUpdated {
                // Update activeProfile reference
                if let activeId = activeProfileId,
                   let profile = profiles.first(where: { $0.id == activeId }) {
                    activeProfile = profile
                }
                objectWillChange.send()
            }
        }
    }
}
