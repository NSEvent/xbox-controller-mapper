import Foundation
import SwiftUI

struct ProfileConfigurationApplyState: Equatable {
    let profiles: [Profile]
    let activeProfile: Profile?
    let activeProfileId: UUID?
	let lastActiveProfileId: UUID?
    let uiScale: CGFloat
}

enum ProfileConfigurationApplyService {
    static func resolveState(
        currentUiScale: CGFloat,
        result: ProfileConfigurationLoadResult
    ) -> ProfileConfigurationApplyState {
        ProfileConfigurationApplyState(
            profiles: result.profiles,
			activeProfile: result.activeProfile,
			activeProfileId: result.activeProfileId,
			lastActiveProfileId: result.lastActiveProfileId,
			uiScale: result.uiScale ?? currentUiScale
        )
    }
}
