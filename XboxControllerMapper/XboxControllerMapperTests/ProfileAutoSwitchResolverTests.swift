import XCTest
@testable import ControllerKeys

final class ProfileAutoSwitchResolverTests: XCTestCase {
    private let configBundleId = "com.example.controllerkeys"

    func testResolveRestoresEditingProfileWhenReturningToConfigApp() {
        let editingProfile = makeProfile(name: "Editing")
        let activeProfile = makeProfile(name: "Auto")

        let state = ProfileAutoSwitchState(
            previousBundleId: "com.example.game",
            profileIdBeforeBackground: editingProfile.id,
            activeProfileId: activeProfile.id
        )

        let result = ProfileAutoSwitchResolver.resolve(
            bundleId: configBundleId,
            appBundleId: configBundleId,
            profiles: [editingProfile, activeProfile],
            state: state
        )

        XCTAssertEqual(
            result.action,
            ProfileAutoSwitchAction(
                profileId: editingProfile.id,
                reason: .restoreEditingProfile
            )
        )
        XCTAssertEqual(result.previousBundleId, configBundleId)
        XCTAssertEqual(result.profileIdBeforeBackground, editingProfile.id)
    }

    func testResolveDoesNotRestoreMissingEditingProfile() {
        let activeProfile = makeProfile(name: "Auto")
        let missingProfileId = UUID()

        let state = ProfileAutoSwitchState(
            previousBundleId: "com.example.game",
            profileIdBeforeBackground: missingProfileId,
            activeProfileId: activeProfile.id
        )

        let result = ProfileAutoSwitchResolver.resolve(
            bundleId: configBundleId,
            appBundleId: configBundleId,
            profiles: [activeProfile],
            state: state
        )

        XCTAssertNil(result.action)
        XCTAssertEqual(result.previousBundleId, configBundleId)
        XCTAssertEqual(result.profileIdBeforeBackground, missingProfileId)
    }

    func testResolveSavesCurrentProfileWhenLeavingConfigApp() {
        let activeProfile = makeProfile(name: "Editing")
        let state = ProfileAutoSwitchState(
            previousBundleId: configBundleId,
            profileIdBeforeBackground: nil,
            activeProfileId: activeProfile.id
        )

        let result = ProfileAutoSwitchResolver.resolve(
            bundleId: "com.example.notes",
            appBundleId: configBundleId,
            profiles: [activeProfile],
            state: state
        )

        XCTAssertEqual(result.previousBundleId, "com.example.notes")
        XCTAssertEqual(result.profileIdBeforeBackground, activeProfile.id)
    }

    func testResolveSwitchesToLinkedProfileBeforeDefault() {
        let defaultProfile = makeProfile(name: "Default", isDefault: true)
        let linkedProfile = makeProfile(name: "Game", linkedApps: ["com.example.game"])
        let state = ProfileAutoSwitchState(
            previousBundleId: "com.example.mail",
            profileIdBeforeBackground: nil,
            activeProfileId: defaultProfile.id
        )

        let result = ProfileAutoSwitchResolver.resolve(
            bundleId: "com.example.game",
            appBundleId: configBundleId,
            profiles: [defaultProfile, linkedProfile],
            state: state
        )

        XCTAssertEqual(
            result.action,
            ProfileAutoSwitchAction(
                profileId: linkedProfile.id,
                reason: .linkedApp(bundleId: "com.example.game")
            )
        )
    }

    func testResolveLinkedAppWinsOverLinkedController() {
        let identity = makeIdentity(stableId: "serial:abc")
        let controllerProfile = makeProfile(name: "Controller", linkedControllers: [
            ControllerProfileBinding(displayName: "DualSense", identity: identity)
        ])
        let appProfile = makeProfile(name: "Anki", linkedApps: ["net.ankiweb.launcher"])
        let state = ProfileAutoSwitchState(
            previousBundleId: "com.example.mail",
            profileIdBeforeBackground: nil,
            activeProfileId: controllerProfile.id
        )

        let result = ProfileAutoSwitchResolver.resolve(
            bundleId: "net.ankiweb.launcher",
            appBundleId: configBundleId,
            profiles: [controllerProfile, appProfile],
            state: state,
            controllerIdentity: identity
        )

        XCTAssertEqual(
            result.action,
            ProfileAutoSwitchAction(
                profileId: appProfile.id,
                reason: .linkedApp(bundleId: "net.ankiweb.launcher")
            )
        )
    }

    func testResolveSwitchesToControllerProfileBeforeDefault() {
        let identity = makeIdentity(stableId: "serial:abc")
        let defaultProfile = makeProfile(name: "Default", isDefault: true)
        let controllerProfile = makeProfile(name: "Controller", linkedControllers: [
            ControllerProfileBinding(displayName: "DualSense", identity: identity)
        ])
        let state = ProfileAutoSwitchState(
            previousBundleId: "com.example.mail",
            profileIdBeforeBackground: nil,
            activeProfileId: defaultProfile.id
        )

        let result = ProfileAutoSwitchResolver.resolve(
            bundleId: "com.example.notes",
            appBundleId: configBundleId,
            profiles: [defaultProfile, controllerProfile],
            state: state,
            controllerIdentity: identity
        )

        XCTAssertEqual(
            result.action,
            ProfileAutoSwitchAction(
                profileId: controllerProfile.id,
                reason: .linkedController(displayName: "DualSense")
            )
        )
    }

    func testResolveIgnoresAmbiguousFallbackControllerBindings() {
        let identity = makeIdentity(stableId: nil, fallbackId: "hid:054c:0ce6:dualsense:usb")
        let profileA = makeProfile(name: "A", linkedControllers: [
            ControllerProfileBinding(displayName: "DualSense", identity: identity)
        ])
        let profileB = makeProfile(name: "B", linkedControllers: [
            ControllerProfileBinding(displayName: "DualSense", identity: identity)
        ])
        let defaultProfile = makeProfile(name: "Default", isDefault: true)
        let state = ProfileAutoSwitchState(
            previousBundleId: "com.example.mail",
            profileIdBeforeBackground: nil,
            activeProfileId: profileA.id
        )

        let result = ProfileAutoSwitchResolver.resolve(
            bundleId: "com.example.notes",
            appBundleId: configBundleId,
            profiles: [profileA, profileB, defaultProfile],
            state: state,
            controllerIdentity: identity
        )

        XCTAssertEqual(
            result.action,
            ProfileAutoSwitchAction(
                profileId: defaultProfile.id,
                reason: .defaultProfile(bundleId: "com.example.notes")
            )
        )
    }

    func testResolveFallsBackToDefaultProfileWhenNoLinkedProfileExists() {
        let defaultProfile = makeProfile(name: "Default", isDefault: true)
        let customProfile = makeProfile(name: "Editing")
        let state = ProfileAutoSwitchState(
            previousBundleId: "com.example.game",
            profileIdBeforeBackground: customProfile.id,
            activeProfileId: customProfile.id
        )

        let result = ProfileAutoSwitchResolver.resolve(
            bundleId: "com.example.notes",
            appBundleId: configBundleId,
            profiles: [defaultProfile, customProfile],
            state: state
        )

        XCTAssertEqual(
            result.action,
            ProfileAutoSwitchAction(
                profileId: defaultProfile.id,
                reason: .defaultProfile(bundleId: "com.example.notes")
            )
        )
    }

    func testResolveDoesNothingWhenTargetProfileAlreadyActive() {
        let defaultProfile = makeProfile(name: "Default", isDefault: true)
        let state = ProfileAutoSwitchState(
            previousBundleId: "com.example.mail",
            profileIdBeforeBackground: nil,
            activeProfileId: defaultProfile.id
        )

        let result = ProfileAutoSwitchResolver.resolve(
            bundleId: "com.example.notes",
            appBundleId: configBundleId,
            profiles: [defaultProfile],
            state: state
        )

        XCTAssertNil(result.action)
        XCTAssertEqual(result.previousBundleId, "com.example.notes")
    }

    func testResolveKeepsLinkedProfileWhenAlreadyActiveForLinkedApp() {
        let defaultProfile = makeProfile(name: "Default", isDefault: true)
        let linkedProfile = makeProfile(name: "Game", linkedApps: ["com.example.game"])
        let state = ProfileAutoSwitchState(
            previousBundleId: configBundleId,
            profileIdBeforeBackground: nil,
            activeProfileId: linkedProfile.id
        )

        let result = ProfileAutoSwitchResolver.resolve(
            bundleId: "com.example.game",
            appBundleId: configBundleId,
            profiles: [defaultProfile, linkedProfile],
            state: state
        )

        XCTAssertNil(result.action)
        XCTAssertEqual(result.previousBundleId, "com.example.game")
        XCTAssertEqual(result.profileIdBeforeBackground, linkedProfile.id)
    }

    private func makeProfile(
        name: String,
        isDefault: Bool = false,
        linkedApps: [String] = [],
        linkedControllers: [ControllerProfileBinding] = []
    ) -> Profile {
        Profile(
            id: UUID(),
            name: name,
            isDefault: isDefault,
            linkedApps: linkedApps,
            linkedControllers: linkedControllers
        )
    }

    private func makeIdentity(
        stableId: String?,
        fallbackId: String = "hid:054c:0ce6:dualsense:usb"
    ) -> ControllerIdentity {
        ControllerIdentity(
            stableId: stableId,
            fallbackId: fallbackId,
            vendorId: 0x054c,
            productId: 0x0ce6,
            productName: "DualSense",
            transport: "USB",
            serialNumber: stableId?.replacingOccurrences(of: "serial:", with: ""),
            deviceAddress: nil
        )
    }
}
