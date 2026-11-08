import AppKit
import XCTest
@testable import ControllerKeys

final class ClipboardRestoreSessionTests: XCTestCase {
	private var pasteboard: NSPasteboard!

	override func setUp() {
		super.setUp()
		pasteboard = NSPasteboard.withUniqueName()
		pasteboard.clearContents()
		pasteboard.setString("user clipboard", forType: .string)
	}

	override func tearDown() {
		pasteboard.releaseGlobally()
		pasteboard = nil
		super.tearDown()
	}

	func testSinglePasteRestoresClipboard() {
		let session = ClipboardRestoreSession(pasteboard: pasteboard)
		session.beginPaste("snippet")
		XCTAssertEqual(pasteboard.string(forType: .string), "snippet")
		session.endPaste()
		XCTAssertEqual(pasteboard.string(forType: .string), "user clipboard")
	}

	func testOverlappingPastesRestoreOriginalClipboard() {
		let session = ClipboardRestoreSession(pasteboard: pasteboard)
		session.beginPaste("snippet 1")
		session.beginPaste("snippet 2")
		session.endPaste()
		XCTAssertEqual(pasteboard.string(forType: .string), "snippet 2", "no restore while a paste is outstanding")
		session.endPaste()
		XCTAssertEqual(pasteboard.string(forType: .string), "user clipboard")
	}

	func testUserCopyDuringPasteIsKept() {
		let session = ClipboardRestoreSession(pasteboard: pasteboard)
		session.beginPaste("snippet")
		pasteboard.clearContents()
		pasteboard.setString("copied meanwhile", forType: .string)
		session.endPaste()
		XCTAssertEqual(pasteboard.string(forType: .string), "copied meanwhile")
	}

	func testUserCopyMidBurstBecomesRestoreTarget() {
		let session = ClipboardRestoreSession(pasteboard: pasteboard)
		session.beginPaste("snippet 1")
		pasteboard.clearContents()
		pasteboard.setString("copied meanwhile", forType: .string)
		session.beginPaste("snippet 2")
		session.endPaste()
		session.endPaste()
		XCTAssertEqual(pasteboard.string(forType: .string), "copied meanwhile")
	}
	func testOverlappingPastesRestoreEveryClipboardItemAndFormat() {
		pasteboard.clearContents()
		let first = NSPasteboardItem()
		first.setString("formatted text", forType: .string)
		let rich = Data([1, 2, 3, 4])
		first.setData(rich, forType: .rtf)
		let second = NSPasteboardItem()
		let image = Data([5, 6, 7, 8])
		second.setData(image, forType: .png)
		pasteboard.writeObjects([first, second])
		let session = ClipboardRestoreSession(pasteboard: pasteboard)
		session.beginPaste("one"); session.beginPaste("two")
		session.endPaste(); session.endPaste()
		XCTAssertEqual(pasteboard.pasteboardItems?.count, 2)
		XCTAssertEqual(pasteboard.pasteboardItems?.first?.data(forType: .rtf), rich)
		XCTAssertEqual(pasteboard.pasteboardItems?.last?.data(forType: .png), image)
	}

	func testEmptyClipboardIsRestoredInsteadOfLeavingSnippet() {
		pasteboard.clearContents()
		let session = ClipboardRestoreSession(pasteboard: pasteboard)
		session.beginPaste("snippet"); session.endPaste()
		XCTAssertNil(pasteboard.string(forType: .string))
		XCTAssertTrue(pasteboard.pasteboardItems?.isEmpty ?? true)
	}

}
