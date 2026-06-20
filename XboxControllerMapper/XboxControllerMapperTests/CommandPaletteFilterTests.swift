import XCTest
@testable import ControllerKeys

/// Tests for the pure ⌘K command-palette ranking. No UI / app state — exercises
/// `CommandPaletteFilter` directly so the "jump to anything" behavior is locked
/// down without touching SwiftUI.
final class CommandPaletteFilterTests: XCTestCase {

    // MARK: Fixtures

    private func make(
        _ title: String,
        subtitle: String? = nil,
        group: String = "Map",
        keywords: [String] = [],
        section: Int = 0
    ) -> CommandPaletteDestination {
        CommandPaletteDestination(
            id: "id-\(title)-\(section)",
            title: title,
            subtitle: subtitle,
            groupLabel: group,
            systemImage: "circle",
            keywords: keywords,
            target: .section(section)
        )
    }

    private func titles(_ items: [CommandPaletteDestination]) -> [String] {
        items.map(\.title)
    }

    private var sampleSections: [CommandPaletteDestination] {
        [
            make("Buttons", group: "Map", keywords: ["mappings", "bindings"], section: 0),
            make("Chords", group: "Map", keywords: ["combo"], section: 1),
            make("Sequences", group: "Map", keywords: ["series"], section: 9),
            make("Macros", group: "Automate", keywords: ["automation", "record"], section: 7),
            make("Scripts", group: "Automate", keywords: ["javascript", "code"], section: 10),
            make("Stats", group: "Activity", keywords: ["usage", "wrapped"], section: 8)
        ]
    }

    // MARK: Empty query

    func testEmptyQueryReturnsAllInOriginalOrder() {
        let result = CommandPaletteFilter.filter(sampleSections, query: "")
        XCTAssertEqual(titles(result), titles(sampleSections))
    }

    func testWhitespaceQueryReturnsAll() {
        let result = CommandPaletteFilter.filter(sampleSections, query: "   ")
        XCTAssertEqual(result.count, sampleSections.count)
    }

    // MARK: Matching

    func testExactTitleMatchRanksFirst() {
        let result = CommandPaletteFilter.filter(sampleSections, query: "macros")
        XCTAssertEqual(result.first?.title, "Macros")
    }

    func testCaseInsensitive() {
        let result = CommandPaletteFilter.filter(sampleSections, query: "SCRIPTS")
        XCTAssertEqual(result.first?.title, "Scripts")
    }

    func testPrefixMatchFound() {
        let result = CommandPaletteFilter.filter(sampleSections, query: "seq")
        XCTAssertEqual(result.first?.title, "Sequences")
    }

    func testNoMatchReturnsEmpty() {
        let result = CommandPaletteFilter.filter(sampleSections, query: "zzzznope")
        XCTAssertTrue(result.isEmpty)
    }

    func testSubsequenceFuzzyMatch() {
        // "sqnc" is not a substring of "Sequences" but is a subsequence.
        let result = CommandPaletteFilter.filter(sampleSections, query: "sqnc")
        XCTAssertEqual(result.first?.title, "Sequences")
    }

    // MARK: Ranking tiers

    func testTitleMatchOutranksKeywordMatch() {
        let items = [
            make("Stats", group: "Activity", keywords: ["usage"], section: 8),
            make("Record", group: "Automate", keywords: ["macros"], section: 7) // keyword-only "mac" hit
        ]
        // "stat" is a title prefix of Stats (score 1) and unrelated to Record.
        let result = CommandPaletteFilter.filter(items, query: "stat")
        XCTAssertEqual(result.first?.title, "Stats")
    }

    func testTitlePrefixBeatsSubstring() {
        let items = [
            make("Touch Scripts", section: 1),   // "scr" is a substring (score 3)
            make("Scripts", section: 10)          // "scr" is a prefix (score 1)
        ]
        let result = CommandPaletteFilter.filter(items, query: "scr")
        XCTAssertEqual(result.first?.title, "Scripts")
    }

    func testKeywordMatchSurfacesSection() {
        // "javascript" only appears in Scripts' keywords.
        let result = CommandPaletteFilter.filter(sampleSections, query: "javascript")
        XCTAssertEqual(result.first?.title, "Scripts")
    }

    // MARK: Shortcut/binding search (the "jump to a shortcut" path)

    func testBindingSubtitleIsSearchable() {
        let items = [
            make("A Button", subtitle: "Left Click", group: "Button", keywords: ["a", "Left Click"], section: 0),
            make("B Button", subtitle: "⌘ C", group: "Button", keywords: ["b", "⌘ C"], section: 0),
            make("X Button", subtitle: "Esc", group: "Button", keywords: ["x", "Esc"], section: 0)
        ]
        // Typing the bound action finds the button carrying it.
        let result = CommandPaletteFilter.filter(items, query: "left click")
        XCTAssertEqual(result.first?.title, "A Button")
    }

    func testButtonFoundByRawName() {
        let items = [
            make("Cross", subtitle: "Jump", group: "Button", keywords: ["a"], section: 0)
        ]
        // PlayStation "Cross" is internally button `a` — searchable via keyword.
        let result = CommandPaletteFilter.filter(items, query: "a")
        XCTAssertEqual(result.first?.title, "Cross")
    }

    // MARK: Stability

    func testStableTiebreakKeepsOriginalOrder() {
        // Two items that match equally well (both exact title prefix of "item").
        let items = [
            make("Item One", section: 1),
            make("Item Two", section: 2)
        ]
        let result = CommandPaletteFilter.filter(items, query: "item")
        XCTAssertEqual(titles(result), ["Item One", "Item Two"])
    }

    // MARK: Score primitives

    func testMatchScoreTiers() {
        XCTAssertEqual(CommandPaletteFilter.matchScore("macros", "macros"), 0)   // exact
        XCTAssertEqual(CommandPaletteFilter.matchScore("macros", "mac"), 1)      // prefix
        XCTAssertEqual(CommandPaletteFilter.matchScore("automacro", "mac"), 3)   // substring
        XCTAssertEqual(CommandPaletteFilter.matchScore("sequences", "sqnc"), 8)  // subsequence
        XCTAssertNil(CommandPaletteFilter.matchScore("macros", "xyz"))           // no match
    }

    func testIsSubsequence() {
        XCTAssertTrue(CommandPaletteFilter.isSubsequence("sqnc", of: "sequences"))
        XCTAssertTrue(CommandPaletteFilter.isSubsequence("", of: "anything"))
        XCTAssertFalse(CommandPaletteFilter.isSubsequence("zzz", of: "sequences"))
        XCTAssertFalse(CommandPaletteFilter.isSubsequence("scs", of: "sc")) // needle longer
    }
}
