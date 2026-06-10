import XCTest
import Combine
import CoreGraphics
import Carbon.HIToolbox
import SwiftUI
import AppKit
@testable import ControllerKeys

/// Profile management: creation, deletion, duplication, switching, linked apps, UI scale, and mapping removal.
/// Split from the original XboxControllerMapperTests.swift monolith.
final class ProfileManagementTests: MappingEngineTestCase {

    // MARK: - App-Specific Profile Tests (Medium Priority)

    /// Tests that profile manager can store app-specific overrides (structural test)
    func testAppSpecificProfileStructure() async throws {
        await MainActor.run {
            let profile = Profile(name: "AppSpecific", buttonMappings: [.a: .key(1)])
            // Note: The actual app-specific override system depends on AppMonitor
            // This test verifies the profile can be created and stored
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            XCTAssertEqual(profileManager.activeProfile?.name, "AppSpecific")
        }
    }

    // MARK: - Profile Switching Tests (High Priority)

    /// Tests rapid profile switching
    func testRapidProfileSwitching() async throws {
        let profile1 = Profile(name: "P1", buttonMappings: [.a: .key(1)])
        let profile2 = Profile(name: "P2", buttonMappings: [.a: .key(2)])

        await MainActor.run {
            profileManager.setActiveProfile(profile1)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Switch profiles rapidly
        for i in 0..<5 {
            await MainActor.run {
                profileManager.setActiveProfile(i % 2 == 0 ? profile2 : profile1)
            }
            try? await Task.sleep(nanoseconds: 5_000_000) // 5ms
        }

        // Settle on profile2
        await MainActor.run {
            profileManager.setActiveProfile(profile2)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.a)
            controllerService.buttonReleased(.a)
        }
        await waitForTasks()

        await MainActor.run {
            // Should use profile2's mapping (keyCode 2)
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(2, _) = event { return true }
                return false
            }, "Should use final profile's mapping")
        }
    }

    /// Tests switching to profile with fewer mappings
    func testSwitchToSmallerProfile() async throws {
        let fullProfile = Profile(name: "Full", buttonMappings: [
            .a: .key(1),
            .b: .key(2),
            .x: .key(3),
            .y: .key(4)
        ])
        let minimalProfile = Profile(name: "Minimal", buttonMappings: [.a: .key(10)])

        await MainActor.run {
            profileManager.setActiveProfile(fullProfile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            profileManager.setActiveProfile(minimalProfile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // B should now be unmapped
        await MainActor.run {
            controllerService.buttonPressed(.b)
            controllerService.buttonReleased(.b)
        }
        await waitForTasks()

        await MainActor.run {
            // Should NOT trigger old mapping
            XCTAssertFalse(mockInputSimulator.events.contains { event in
                if case .pressKey(2, _) = event { return true }
                return false
            }, "Old mapping should not be used")
        }
    }

    // MARK: - Profile Management Tests

    /// Tests that creating a profile from template copies mappings
    func testCreateProfileFromTemplate() async throws {
        await MainActor.run {
            let template = Profile(
                name: "Template",
                buttonMappings: [.a: .key(1), .b: .key(2)],
                chordMappings: [ChordMapping(buttons: [.a, .b], keyCode: 3)]
            )
            profileManager.profiles.append(template)

            let newProfile = profileManager.createProfile(name: "Copy", basedOn: template)

            XCTAssertEqual(newProfile.name, "Copy")
            XCTAssertEqual(newProfile.buttonMappings.count, 2)
            XCTAssertEqual(newProfile.chordMappings.count, 1)
            XCTAssertNotEqual(newProfile.id, template.id, "New profile should have different ID")
            XCTAssertFalse(newProfile.isDefault, "Copy should not be default")
        }
    }

    /// Tests that deleting profile switches to another
    func testDeleteProfileSwitchesActive() async throws {
        await MainActor.run {
            let profile1 = Profile(name: "Profile1")
            let profile2 = Profile(name: "Profile2")
            profileManager.profiles = [profile1, profile2]
            profileManager.setActiveProfile(profile1)

            XCTAssertEqual(profileManager.activeProfileId, profile1.id)

            profileManager.deleteProfile(profile1)

            // Should switch to remaining profile
            XCTAssertEqual(profileManager.activeProfileId, profile2.id)
            XCTAssertEqual(profileManager.profiles.count, 1)
        }
    }

    /// Tests that last profile cannot be deleted
    func testCannotDeleteLastProfile() async throws {
        await MainActor.run {
            let onlyProfile = Profile(name: "Only")
            profileManager.profiles = [onlyProfile]
            profileManager.setActiveProfile(onlyProfile)

            profileManager.deleteProfile(onlyProfile)

            // Should still have the profile
            XCTAssertEqual(profileManager.profiles.count, 1)
            XCTAssertEqual(profileManager.activeProfileId, onlyProfile.id)
        }
    }

    /// Tests that duplicating a profile creates a copy
    func testDuplicateProfile() async throws {
        await MainActor.run {
            let original = Profile(
                name: "Original",
                buttonMappings: [.a: .key(1)]
            )
            profileManager.profiles = [original]

            let duplicate = profileManager.duplicateProfile(original)

            XCTAssertEqual(duplicate.name, "Original Copy")
            XCTAssertEqual(duplicate.buttonMappings[.a]?.keyCode, 1)
            XCTAssertNotEqual(duplicate.id, original.id)
            XCTAssertEqual(profileManager.profiles.count, 2)
        }
    }

    /// Tests that renaming a profile updates correctly
    func testRenameProfile() async throws {
        await MainActor.run {
            let profile = Profile(name: "OldName")
            profileManager.profiles = [profile]
            profileManager.setActiveProfile(profile)

            profileManager.renameProfile(profile, to: "NewName")

            XCTAssertEqual(profileManager.profiles.first?.name, "NewName")
            XCTAssertEqual(profileManager.activeProfile?.name, "NewName")
        }
    }

    /// Tests that setting profile icon updates correctly
    func testSetProfileIcon() async throws {
        await MainActor.run {
            let profile = Profile(name: "Test")
            profileManager.profiles = [profile]
            profileManager.setActiveProfile(profile)

            profileManager.setProfileIcon(profile, icon: "gamecontroller")

            XCTAssertEqual(profileManager.profiles.first?.icon, "gamecontroller")
        }
    }

    // MARK: - Linked Apps Tests

    /// Tests adding a linked app to profile
    func testAddLinkedApp() async throws {
        await MainActor.run {
            let profile = Profile(name: "Gaming")
            profileManager.profiles = [profile]
            profileManager.setActiveProfile(profile)

            profileManager.addLinkedApp("com.example.game", to: profile)

            let updatedProfile = profileManager.profiles.first { $0.id == profile.id }
            XCTAssertTrue(updatedProfile?.linkedApps.contains("com.example.game") ?? false)
        }
    }

    /// Tests that adding linked app to one profile removes it from another
    func testAddLinkedAppRemovesFromOther() async throws {
        await MainActor.run {
            var profile1 = Profile(name: "Profile1")
            profile1.linkedApps = ["com.example.game"]
            let profile2 = Profile(name: "Profile2")

            profileManager.profiles = [profile1, profile2]
            profileManager.setActiveProfile(profile1)

            // Move the app to profile2
            profileManager.addLinkedApp("com.example.game", to: profile2)

            let updated1 = profileManager.profiles.first { $0.id == profile1.id }
            let updated2 = profileManager.profiles.first { $0.id == profile2.id }

            XCTAssertFalse(updated1?.linkedApps.contains("com.example.game") ?? true)
            XCTAssertTrue(updated2?.linkedApps.contains("com.example.game") ?? false)
        }
    }

    /// Tests removing a linked app from profile
    func testRemoveLinkedApp() async throws {
        await MainActor.run {
            var profile = Profile(name: "Gaming")
            profile.linkedApps = ["com.example.game"]
            profileManager.profiles = [profile]
            profileManager.setActiveProfile(profile)

            profileManager.removeLinkedApp("com.example.game", from: profile)

            let updatedProfile = profileManager.profiles.first { $0.id == profile.id }
            XCTAssertFalse(updatedProfile?.linkedApps.contains("com.example.game") ?? true)
        }
    }

    // MARK: - UI Scale Tests

    /// Tests setting UI scale persists
    func testSetUiScale() async throws {
        await MainActor.run {
            profileManager.setUiScale(1.5)
            XCTAssertEqual(profileManager.uiScale, 1.5)
        }
    }

    // MARK: - Mapping Removal Tests

    /// Tests removing a button mapping
    func testRemoveMapping() async throws {
        await MainActor.run {
            let profile = Profile(name: "Test", buttonMappings: [.a: .key(1), .b: .key(2)])
            profileManager.profiles = [profile]
            profileManager.setActiveProfile(profile)

            profileManager.removeMapping(for: .a)

            XCTAssertNil(profileManager.activeProfile?.buttonMappings[.a])
            XCTAssertNotNil(profileManager.activeProfile?.buttonMappings[.b])
        }
    }

    /// Tests getting a mapping
    func testGetMapping() async throws {
        await MainActor.run {
            let mapping = KeyMapping(keyCode: 5, modifiers: .command)
            let profile = Profile(name: "Test", buttonMappings: [.a: mapping])
            profileManager.profiles = [profile]
            profileManager.setActiveProfile(profile)

            let retrieved = profileManager.getMapping(for: .a)

            XCTAssertEqual(retrieved?.keyCode, 5)
            XCTAssertTrue(retrieved?.modifiers.command ?? false)

            let missing = profileManager.getMapping(for: .b)
            XCTAssertNil(missing)
        }
    }

}
