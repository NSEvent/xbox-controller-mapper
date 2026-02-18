import XCTest
@testable import ControllerKeys

@MainActor
final class OnScreenKeyboardManagerNavigationTests: XCTestCase {
    private var manager: OnScreenKeyboardManager!

    override func setUp() {
        super.setUp()
        manager = OnScreenKeyboardManager.shared
        resetManager()
    }

    override func tearDown() {
        resetManager()
        manager = nil
        super.tearDown()
    }

    func testHandleDPadNavigation_EntersModeAtDefaultKey() {
        manager.handleDPadNavigation(.dpadRight)

        XCTAssertTrue(manager.navigationModeActive)
        XCTAssertNotNil(manager.highlightedKeyPosition)
        XCTAssertTrue(manager.threadSafeNavigationModeActive)
        XCTAssertEqual(manager.threadSafeHighlightedItem, manager.highlightedItem)
    }

    func testHandleDPadNavigation_UsesLastMouseHoveredItemAsStart() {
        let idA = UUID()
        let idB = UUID()
        manager.setQuickTexts(
            [],
            defaultTerminal: "Terminal",
            websiteLinks: [
                WebsiteLink(id: idA, url: "https://a.example", displayName: "A"),
                WebsiteLink(id: idB, url: "https://b.example", displayName: "B")
            ]
        )
        manager.setMouseHoveredWebsiteLink(idA)

        manager.handleDPadNavigation(.dpadRight)

        XCTAssertEqual(manager.highlightedWebsiteLinkId, idB)
    }

    func testHandleDPadNavigation_ArrowClusterSpecialCases() {
        manager.navigationModeActive = true

        manager.highlightedItem = .keyPosition(row: 6, column: 7)
        manager.handleDPadNavigation(.dpadUp)
        XCTAssertEqual(manager.highlightedItem, .keyPosition(row: 6, column: 6))

        manager.handleDPadNavigation(.dpadDown)
        XCTAssertEqual(manager.highlightedItem, .keyPosition(row: 6, column: 8))

        manager.highlightedItem = .keyPosition(row: 6, column: 6)
        manager.handleDPadNavigation(.dpadLeft)
        XCTAssertEqual(manager.highlightedItem, .keyPosition(row: 6, column: 7))

        manager.highlightedItem = .keyPosition(row: 6, column: 5)
        manager.handleDPadNavigation(.dpadRight)
        XCTAssertEqual(manager.highlightedItem, .keyPosition(row: 6, column: 7))
    }

    func testHandleDPadNavigation_QuickTextTerminalRowBeforeTextRow() {
        let terminalID = UUID()
        let textID = UUID()
        var terminalQuickText = QuickText(text: "ls", isTerminalCommand: true)
        terminalQuickText.id = terminalID
        var textQuickText = QuickText(text: "hello", isTerminalCommand: false)
        textQuickText.id = textID
        manager.setQuickTexts(
            [
                terminalQuickText,
                textQuickText
            ],
            defaultTerminal: "Terminal"
        )
        manager.navigationModeActive = true
        manager.highlightedItem = .quickText(terminalID)

        manager.handleDPadNavigation(.dpadDown)

        XCTAssertEqual(manager.highlightedQuickTextId, textID)
    }

    func testHandleDPadNavigation_AppBarRowsChunkedAndNavigable() {
        let items = (0..<13).map {
            AppBarItem(id: UUID(), bundleIdentifier: "com.example.\($0)", displayName: "App \($0)")
        }
        manager.setQuickTexts([], defaultTerminal: "Terminal", appBarItems: items)
        manager.navigationModeActive = true
        manager.highlightedItem = .appBarItem(items[11].id)

        manager.handleDPadNavigation(.dpadDown)

        XCTAssertEqual(manager.highlightedItem, .appBarItem(items[12].id))
    }

    func testExitNavigationMode_ClearsHighlightAndThreadSafeState() {
        manager.handleDPadNavigation(.dpadRight)
        XCTAssertTrue(manager.navigationModeActive)

        manager.exitNavigationMode()

        XCTAssertFalse(manager.navigationModeActive)
        XCTAssertNil(manager.highlightedItem)
        XCTAssertFalse(manager.threadSafeNavigationModeActive)
        XCTAssertNil(manager.threadSafeHighlightedItem)
    }

    func testIsKeyboardPositionHighlighted_MatchesCurrentHighlight() {
        manager.highlightedItem = .keyPosition(row: 2, column: 3)

        XCTAssertTrue(manager.isKeyboardPositionHighlighted(keyboardRow: 2, column: 3))
        XCTAssertFalse(manager.isKeyboardPositionHighlighted(keyboardRow: 2, column: 4))
    }

    private func resetManager() {
        manager.exitNavigationMode()
        manager.hide()
        manager.highlightedItem = nil
        manager.lastMouseHoveredItem = nil
        manager.setQuickTexts(
            [],
            defaultTerminal: "Terminal",
            typingDelay: 0.03,
            appBarItems: [],
            websiteLinks: [],
            showExtendedFunctionKeys: false,
            activateAllWindows: true
        )
    }
}
