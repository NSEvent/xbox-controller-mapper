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
}
