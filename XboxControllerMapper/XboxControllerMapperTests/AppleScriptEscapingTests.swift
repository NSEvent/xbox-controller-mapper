import XCTest
@testable import ControllerKeys

final class AppleScriptEscapingTests: XCTestCase {

    // MARK: - escapeForString

    func testEscapesBackslash() {
        XCTAssertEqual(AppleScriptEscaping.escapeForString(#"a\b"#), #"a\\b"#)
    }

    func testEscapesDoubleQuote() {
        XCTAssertEqual(AppleScriptEscaping.escapeForString(#"say "hello""#), #"say \"hello\""#)
    }

    func testEscapesNewline() {
        XCTAssertEqual(AppleScriptEscaping.escapeForString("line1\nline2"), "line1\\nline2")
    }

    func testEscapesCarriageReturn() {
        XCTAssertEqual(AppleScriptEscaping.escapeForString("line1\rline2"), "line1\\rline2")
    }

    func testEscapesTab() {
        XCTAssertEqual(AppleScriptEscaping.escapeForString("col1\tcol2"), "col1\\tcol2")
    }

    func testEscapesMultipleSpecialCharacters() {
        let input = "echo \"hello\"\nrm -rf \\"
        let expected = "echo \\\"hello\\\"\\nrm -rf \\\\"
        XCTAssertEqual(AppleScriptEscaping.escapeForString(input), expected)
    }

    func testPassthroughSafeString() {
        let safe = "ls -la /tmp"
        XCTAssertEqual(AppleScriptEscaping.escapeForString(safe), safe)
    }

    // MARK: - sanitizeAppName

    func testAcceptsValidAppName() {
        XCTAssertEqual(AppleScriptEscaping.sanitizeAppName("Terminal"), "Terminal")
        XCTAssertEqual(AppleScriptEscaping.sanitizeAppName("iTerm"), "iTerm")
        XCTAssertEqual(AppleScriptEscaping.sanitizeAppName("Warp"), "Warp")
    }

    func testRejectsEmptyName() {
        XCTAssertNil(AppleScriptEscaping.sanitizeAppName(""))
        XCTAssertNil(AppleScriptEscaping.sanitizeAppName("   "))
    }

    func testRejectsNameWithDoubleQuote() {
        XCTAssertNil(AppleScriptEscaping.sanitizeAppName(#"My"App"#))
    }

    func testRejectsNameWithBackslash() {
        XCTAssertNil(AppleScriptEscaping.sanitizeAppName(#"My\App"#))
    }

    func testRejectsNameWithNewline() {
        XCTAssertNil(AppleScriptEscaping.sanitizeAppName("My\nApp"))
    }

    func testRejectsNameWithCarriageReturn() {
        XCTAssertNil(AppleScriptEscaping.sanitizeAppName("My\rApp"))
    }

    func testRejectsNameWithControlCharacter() {
        XCTAssertNil(AppleScriptEscaping.sanitizeAppName("My\u{01}App"))
    }

    func testTrimsWhitespace() {
        XCTAssertEqual(AppleScriptEscaping.sanitizeAppName("  Terminal  "), "Terminal")
    }
}
