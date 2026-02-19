import Foundation

enum ProfileBootstrapSelectionAction: Equatable {
    case createAndActivateDefault
    case activateProfile(UUID)
    case none
}

enum ProfileBootstrapSelectionPolicy {
    static func resolve(profiles: [Profile], hasActiveProfile: Bool) -> ProfileBootstrapSelectionAction {
        if profiles.isEmpty {
            return .createAndActivateDefault
        }

        guard !hasActiveProfile else {
            return .none
        }

        if let defaultProfile = profiles.first(where: { $0.isDefault }) {
            return .activateProfile(defaultProfile.id)
        }

        if let firstProfile = profiles.first {
            return .activateProfile(firstProfile.id)
        }

        return .none
    }
}
