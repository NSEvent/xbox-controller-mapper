import Carbon.HIToolbox
import XCTest
@testable import TriggerKitCore

final class TriggerKeyCatalogTests: XCTestCase {
	func testCatalogGroupsAreStableAndNonEmpty() {
		XCTAssertEqual(
			TriggerKey.catalogGroups.map(\.title),
			["Common", "Letters", "Numbers", "Symbols", "Navigation", "Function", "Keypad", "Modifiers", "Media", "System"]
		)
		for group in TriggerKey.catalogGroups {
			XCTAssertFalse(group.keys.isEmpty, "\(group.title) should not be empty")
		}
	}

	func testCatalogKeyIDsAreUnique() {
		let ids = TriggerKey.allCatalogKeys.map(\.id)
		XCTAssertEqual(ids.count, Set(ids).count)
	}

	func testCatalogLookupFindsCanonicalKeysByKeyCode() {
		XCTAssertEqual(TriggerKey.catalogKey(keyCode: UInt16(kVK_Return)), .return)
		XCTAssertEqual(TriggerKey.catalogKey(keyCode: UInt16(kVK_F20))?.displayName, "F20")
		XCTAssertEqual(TriggerKey.catalogKey(keyCode: TriggerKey.mediaPlayPause.keyCode), .mediaPlayPause)
		XCTAssertNil(TriggerKey.catalogKey(keyCode: 0xFFFF))
	}

	func testCatalogContainsFullLettersNumbersAndFunctionRanges() {
		let names = Set(TriggerKey.allCatalogKeys.map(\.displayName))
		for letter in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" {
			XCTAssertTrue(names.contains(String(letter)), "Missing letter \(letter)")
		}
		for number in 0...9 {
			XCTAssertTrue(names.contains(String(number)), "Missing number \(number)")
		}
		for functionIndex in 1...20 {
			XCTAssertTrue(names.contains("F\(functionIndex)"), "Missing F\(functionIndex)")
		}
	}

	func testCatalogContainsControllerKeysStyleSpecialKeys() {
		let ids = Set(TriggerKey.allCatalogKeys.map(\.id))
		let expectedIDs = [
			"forward-delete",
			"help",
			"caps-lock",
			"function",
			"keypad-enter",
			"left-command",
			"right-command",
			"left-option",
			"right-option",
			"left-shift",
			"right-shift",
			"left-control",
			"right-control",
			"media-play-pause",
			"media-next",
			"media-previous",
			"media-fast-forward",
			"media-rewind",
			"volume-up",
			"volume-down",
			"volume-mute",
			"brightness-up",
			"brightness-down"
		]

		for id in expectedIDs {
			XCTAssertTrue(ids.contains(id), "Missing \(id)")
		}
	}

	func testMediaAndSystemClassificationOnlyMatchesSyntheticRanges() {
		for key in [TriggerKey.mediaPlayPause, .mediaNext, .mediaPrevious, .mediaFastForward, .mediaRewind, .volumeUp, .volumeDown, .volumeMute, .brightnessUp, .brightnessDown] {
			XCTAssertTrue(TriggerKey.isMediaOrSystemKeyCode(key.keyCode), "\(key.displayName) should be media/system")
		}

		for key in [TriggerKey.return, .tab, .space, .escape, .delete, .help, .function] {
			XCTAssertFalse(TriggerKey.isMediaOrSystemKeyCode(key.keyCode), "\(key.displayName) should not be media/system")
		}
	}
}
