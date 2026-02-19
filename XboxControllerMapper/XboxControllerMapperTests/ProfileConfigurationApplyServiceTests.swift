import XCTest
import SwiftUI
@testable import ControllerKeys

final class ProfileConfigurationApplyServiceTests: XCTestCase {
    func testResolveStatePreservesCurrentUiScaleWhenResultDoesNotProvideScale() {
        let profile = Profile(id: UUID(), name: "P")
        let result = ProfileConfigurationLoadResult(
            profiles: [profile],
            activeProfile: profile,
            activeProfileId: profile.id,
            uiScale: nil,
            didMigrate: false
        )

        let state = ProfileConfigurationApplyService.resolveState(
            currentUiScale: 1.4,
            result: result
        )

        XCTAssertEqual(state.uiScale, 1.4)
    }

    func testResolveStateUsesLoadedUiScaleWhenProvided() {
        let profile = Profile(id: UUID(), name: "P")
        let result = ProfileConfigurationLoadResult(
            profiles: [profile],
            activeProfile: profile,
            activeProfileId: profile.id,
            uiScale: 0.9,
            didMigrate: false
        )

        let state = ProfileConfigurationApplyService.resolveState(
            currentUiScale: 1.4,
            result: result
        )

        XCTAssertEqual(state.uiScale, 0.9)
    }

    func testResolveStatePassesThroughProfilesAndActiveSelection() {
        let first = Profile(id: UUID(), name: "First")
        let second = Profile(id: UUID(), name: "Second")
        let result = ProfileConfigurationLoadResult(
            profiles: [first, second],
            activeProfile: second,
            activeProfileId: second.id,
            uiScale: 1.0,
            didMigrate: true
        )

        let state = ProfileConfigurationApplyService.resolveState(
            currentUiScale: 1.0,
            result: result
        )

        XCTAssertEqual(state.profiles.map(\.id), [first.id, second.id])
        XCTAssertEqual(state.activeProfile?.id, second.id)
        XCTAssertEqual(state.activeProfileId, second.id)
    }
}
