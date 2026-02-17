import XCTest
import Foundation
import AppKit
@testable import ControllerKeys

final class VariableExpanderTests: XCTestCase {

    private func assertMatch(_ value: String, pattern: String, file: StaticString = #filePath, line: UInt = #line) {
        let range = value.range(of: pattern, options: .regularExpression)
        XCTAssertNotNil(range, "\(value) does not match regex \(pattern)", file: file, line: line)
    }

    func testExpand_UnknownVariableRemainsUnchanged() {
        let input = "prefix {does.not.exist} suffix"
        let output = VariableExpander.expand(input)
        XCTAssertEqual(output, input)
    }

    func testExpand_MalformedPlaceholdersRemainUnchanged() {
        let input = "{DATE} {date {date}} date}"
        let output = VariableExpander.expand(input)
        XCTAssertTrue(output.contains("{DATE}"))
        XCTAssertTrue(output.contains("date}"))
        XCTAssertFalse(output.contains("{date}"))
    }

    func testExpand_AllAvailableVariablesResolveWithoutPlaceholders() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("clipboard-value", forType: .string)

        let delimiter = "|||DELIM|||"
        let input = VariableExpander.availableVariables
            .map { "{\($0.name)}" }
            .joined(separator: delimiter)

        let output = VariableExpander.expand(input)
        let parts = output.components(separatedBy: delimiter)

        XCTAssertEqual(parts.count, VariableExpander.availableVariables.count)
        XCTAssertNil(output.range(of: #"\{[a-z0-9._]+\}"#, options: .regularExpression))

        for value in parts {
            XCTAssertNotNil(value)
        }
    }

    func testExpand_DateAndTimeValuesMatchExpectedFormats() {
        let text = "{date}|{date.us}|{date.eu}|{time}|{time.12}|{time.short}|{datetime}|{time.iso}|{unix}"
        let values = VariableExpander.expand(text).components(separatedBy: "|")

        XCTAssertEqual(values.count, 9)
        assertMatch(values[0], pattern: "^\\d{4}-\\d{2}-\\d{2}$")
        assertMatch(values[1], pattern: "^\\d{2}/\\d{2}/\\d{4}$")
        assertMatch(values[2], pattern: "^\\d{2}/\\d{2}/\\d{4}$")
        assertMatch(values[3], pattern: "^\\d{2}:\\d{2}:\\d{2}$")
        assertMatch(values[4], pattern: #"^\d{1,2}:\d{2}:\d{2}\s*(AM|PM)$"#)
        assertMatch(values[5], pattern: "^\\d{2}:\\d{2}$")
        assertMatch(values[6], pattern: "^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}$")
        assertMatch(values[7], pattern: "^\\d{4}-\\d{2}-\\d{2}T.*Z$")

        let unix = Int(values[8])
        XCTAssertNotNil(unix)
        let now = Int(Date().timeIntervalSince1970)
        if let unix {
            XCTAssertLessThanOrEqual(abs(unix - now), 10)
        }
    }

    func testExpand_YesterdayAndTomorrowBracketToday() throws {
        let values = VariableExpander.expand("{date.yesterday}|{date}|{date.tomorrow}").components(separatedBy: "|")
        XCTAssertEqual(values.count, 3)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        let yesterday = try XCTUnwrap(formatter.date(from: values[0]))
        let today = try XCTUnwrap(formatter.date(from: values[1]))
        let tomorrow = try XCTUnwrap(formatter.date(from: values[2]))

        let oneDay: TimeInterval = 24 * 60 * 60
        XCTAssertEqual(Int(today.timeIntervalSince(yesterday) / oneDay), 1)
        XCTAssertEqual(Int(tomorrow.timeIntervalSince(today) / oneDay), 1)
    }

    func testExpand_PathVariablesResolveUnderHomeDirectory() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let values = VariableExpander.expand("{home}|{desktop}|{downloads}").components(separatedBy: "|")

        XCTAssertEqual(values.count, 3)
        XCTAssertEqual(values[0], home)
        XCTAssertTrue(values[1].hasPrefix(home))
        XCTAssertTrue(values[2].hasPrefix(home))
    }

    func testExpand_FormattingVariablesProduceNewlineAndTab() {
        let output = VariableExpander.expand("A{newline}B{tab}C")
        XCTAssertEqual(output, "A\nB\tC")
    }

    func testExpand_UtilityVariablesHaveValidShape() {
        let values = VariableExpander.expand("{uuid}|{random}").components(separatedBy: "|")
        XCTAssertEqual(values.count, 2)

        let uuid = UUID(uuidString: values[0])
        XCTAssertNotNil(uuid)

        let random = try? XCTUnwrap(Int(values[1]))
        XCTAssertNotNil(random)
        if let random {
            XCTAssertGreaterThanOrEqual(random, 0)
            XCTAssertLessThanOrEqual(random, 9999)
        }
    }

    func testExpand_ReplacesRepeatedVariables() {
        let output = VariableExpander.expand("{username}::{username}")
        let components = output.components(separatedBy: "::")
        XCTAssertEqual(components.count, 2)
        XCTAssertEqual(components[0], components[1])
    }
}
