import XCTest
@testable import ControllerKeys

final class GuidedPresetTests: XCTestCase {
	func testEachPresetIsFreshLocalAndSafe() throws {
		for preset in GuidedPreset.allCases {
			let first = preset.makeProfile(name: "New", targetBundleId: "test.app", linkApp: true)
			let second = preset.makeProfile(name: "New", targetBundleId: nil, linkApp: false)
			XCTAssertNotEqual(first.id, second.id)
			XCTAssertEqual(first.linkedApps, ["test.app"])
			XCTAssertEqual(second.linkedApps, [])
			XCTAssertFalse(first.buttonMappings.isEmpty)
			XCTAssertFalse(ProfileImportSafetyAuditor.audit(first).requiresUserConfirmation)
			XCTAssertFalse(preset.testInstruction.isEmpty)
			_ = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(first))
		}
	}
	func testPhotoRatingUsesControlNumberNotColorLabelKeys() {
		let profile = GuidedPreset.photoCulling.makeProfile(name: "Photos", targetBundleId: nil, linkApp: false)
		XCTAssertEqual(profile.buttonMappings[.a]?.keyCode, 23)
		XCTAssertEqual(profile.buttonMappings[.a]?.modifiers.control, true)
		XCTAssertEqual(profile.buttonMappings[.rightBumper]?.keyCode, 124)
	}
}
