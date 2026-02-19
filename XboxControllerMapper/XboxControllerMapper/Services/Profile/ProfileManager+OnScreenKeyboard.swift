import Foundation
import SwiftUI

@MainActor
extension ProfileManager {
    @discardableResult
    private func mutateActiveOnScreenKeyboardSettings(
        _ mutate: (inout OnScreenKeyboardSettings) -> Bool
    ) -> Bool {
        guard var profile = activeProfile else { return false }
        let didChange = mutate(&profile.onScreenKeyboardSettings)
        if didChange {
            updateProfile(profile)
        }
        return didChange
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
