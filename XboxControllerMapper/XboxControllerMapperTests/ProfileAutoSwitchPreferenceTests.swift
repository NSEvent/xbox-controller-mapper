import XCTest
@testable import ControllerKeys

final class ProfileAutoSwitchPreferenceTests: XCTestCase {
	func testActiveLinkedVariantWinsOverBothImportOrderAndRememberedVariant() {
		let first = Profile(name: "First", linkedApps: ["net.ankiweb.anki"])
		let selected = Profile(name: "Selected", linkedApps: ["net.ankiweb.anki"])
		let result = resolve([first, selected], active: selected.id, remembered: first.id)
		XCTAssertNil(result.action, "No profile switch or input reset needed")
	}

	func testRememberedLinkedVariantWinsAfterAnotherAppSelectedTheDefault() {
		let first = Profile(name: "First", linkedApps: ["net.ankiweb.anki"])
		let selected = Profile(name: "Selected", linkedApps: ["net.ankiweb.anki"])
		let desktop = Profile.createDefault()
		let result = resolve([desktop, first, selected], active: desktop.id, remembered: selected.id)
		XCTAssertEqual(result.action?.profileId, selected.id)
	}

	func testUnlinkedOrDeletedPreferenceCannotOverrideTheMatchingProfile() {
		let linked = Profile(name: "Anki", linkedApps: ["net.ankiweb.anki"])
		let desktop = Profile.createDefault()
		for remembered in [desktop.id, UUID()] {
			let result = resolve([desktop, linked], active: desktop.id, remembered: remembered)
			XCTAssertEqual(result.action?.profileId, linked.id)
		}
	}

	func testNoExplicitChoiceRetainsDeterministicFirstMatch() {
		let first = Profile(name: "First", linkedApps: ["net.ankiweb.anki"])
		let second = Profile(name: "Second", linkedApps: ["net.ankiweb.anki"])
		let result = resolve([first, second], active: nil, remembered: nil)
		XCTAssertEqual(result.action?.profileId, first.id)
	}

	func testPersistedPreviousProfileIsUsedOnlyIfItStillLinksTheApp() {
		let first = Profile(name: "First", linkedApps: ["net.ankiweb.anki"])
		let selected = Profile(name: "Selected", linkedApps: ["net.ankiweb.anki"])
		let desktop = Profile.createDefault()
		for previous in [selected.id, desktop.id, UUID()] {
			let result = ProfileAutoSwitchResolver.resolve(
				bundleId: "net.ankiweb.anki", appBundleId: "com.controllerkeys.fixture",
				profiles: [desktop, first, selected],
				state: ProfileAutoSwitchState(previousBundleId: "com.apple.finder",
					profileIdBeforeBackground: desktop.id, activeProfileId: desktop.id,
					lastActiveProfileId: previous)
			)
			XCTAssertEqual(result.action?.profileId, previous == selected.id ? selected.id : first.id)
		}
	}

	private func resolve(_ profiles: [Profile], active: UUID?, remembered: UUID?) -> ProfileAutoSwitchResult {
		ProfileAutoSwitchResolver.resolve(
			bundleId: "net.ankiweb.anki", appBundleId: "com.controllerkeys.fixture",
			profiles: profiles,
			state: ProfileAutoSwitchState(previousBundleId: "com.apple.finder",
				profileIdBeforeBackground: remembered, activeProfileId: active)
		)
	}
}
