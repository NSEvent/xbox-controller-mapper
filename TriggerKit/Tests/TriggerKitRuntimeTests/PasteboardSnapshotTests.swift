import AppKit
import XCTest
@testable import TriggerKitRuntime

final class PasteboardSnapshotTests: XCTestCase {
	func testSnapshotRestoresAllPasteboardItemTypes() throws {
		let pasteboard = NSPasteboard(name: NSPasteboard.Name("TriggerKitTests-\(UUID().uuidString)"))
		defer { pasteboard.releaseGlobally() }
		let customType = NSPasteboard.PasteboardType("com.kevintang.triggerkit.test")
		let customData = Data([0, 1, 2, 3, 4])
		let item = NSPasteboardItem()
		item.setString("plain text", forType: .string)
		item.setData(customData, forType: customType)
		pasteboard.clearContents()
		XCTAssertTrue(pasteboard.writeObjects([item]))

		let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
		pasteboard.clearContents()
		pasteboard.setString("temporary", forType: .string)

		snapshot.restore(to: pasteboard)

		let restored = try XCTUnwrap(pasteboard.pasteboardItems?.first)
		XCTAssertEqual(restored.string(forType: .string), "plain text")
		XCTAssertEqual(restored.data(forType: customType), customData)
	}

	func testSnapshotRestoresEmptyPasteboard() {
		let pasteboard = NSPasteboard(name: NSPasteboard.Name("TriggerKitTests-\(UUID().uuidString)"))
		defer { pasteboard.releaseGlobally() }
		pasteboard.clearContents()

		let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
		pasteboard.setString("temporary", forType: .string)

		snapshot.restore(to: pasteboard)

		XCTAssertTrue(pasteboard.pasteboardItems?.isEmpty ?? true)
	}

	func testSnapshotDoesNotOverwriteUserClipboardChanges() {
		let pasteboard = NSPasteboard(name: NSPasteboard.Name("TriggerKitTests-\(UUID().uuidString)"))
		defer { pasteboard.releaseGlobally() }
		pasteboard.clearContents()
		pasteboard.setString("original", forType: .string)
		let snapshot = PasteboardSnapshot(pasteboard: pasteboard)

		pasteboard.clearContents()
		pasteboard.setString("temporary", forType: .string)
		let temporaryChangeCount = pasteboard.changeCount
		pasteboard.clearContents()
		pasteboard.setString("user changed", forType: .string)

		snapshot.restore(to: pasteboard, ifChangeCountMatches: temporaryChangeCount)

		XCTAssertEqual(pasteboard.string(forType: .string), "user changed")
	}
}
