import Foundation
import Combine

@MainActor
extension ProfileManager {
    // MARK: - Favicon Cache

    /// Load cached favicons for all website links in all profiles.
    func loadCachedFavicons() {
        Task { @MainActor in
            // Extract the IDs and URLs before any `await` suspension point to avoid iterating over mutating array.
            struct LoadRequest {
                let profileId: UUID
                let linkId: UUID
                let url: String
            }

            var requests: [LoadRequest] = []
            for profile in profiles {
                for link in profile.onScreenKeyboardSettings.websiteLinks where link.faviconData == nil {
                    requests.append(LoadRequest(profileId: profile.id, linkId: link.id, url: link.url))
                }

                // Also preload command wheel link favicons into memory cache to prevent UI blocking
                for action in profile.commandWheelActions {
                    if case .openLink(let url) = action.systemCommand, action.iconData == nil {
                        _ = await FaviconCache.shared.loadCachedFavicon(for: url)
                    }
                }
            }

            for request in requests {
                if let cached = await FaviconCache.shared.loadCachedFavicon(for: request.url) {
                    // Look up by ID safely after the suspension
                    if let profileIndex = profiles.firstIndex(where: { $0.id == request.profileId }),
                       let linkIndex = profiles[profileIndex].onScreenKeyboardSettings.websiteLinks.firstIndex(where: { $0.id == request.linkId }) {
                        profiles[profileIndex].onScreenKeyboardSettings.websiteLinks[linkIndex].faviconData = cached
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
