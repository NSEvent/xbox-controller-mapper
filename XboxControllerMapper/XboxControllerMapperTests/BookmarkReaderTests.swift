import XCTest
import Foundation
@testable import ControllerKeys

@MainActor
final class BookmarkReaderTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bookmark-reader-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        tempRoot = nil
    }

    func testDetectDefaultBrowser_ExactAndFuzzyMatches() {
        XCTAssertEqual(BookmarkReader.detectDefaultBrowser(bundleIdentifierOverride: "com.apple.safari"), .safari)
        XCTAssertEqual(BookmarkReader.detectDefaultBrowser(bundleIdentifierOverride: "com.google.chrome"), .chrome)
        XCTAssertEqual(BookmarkReader.detectDefaultBrowser(bundleIdentifierOverride: "org.random.brave.beta"), .brave)
        XCTAssertEqual(BookmarkReader.detectDefaultBrowser(bundleIdentifierOverride: "org.random.edge.beta"), .edge)
        XCTAssertEqual(BookmarkReader.detectDefaultBrowser(bundleIdentifierOverride: "com.example.unknown"), .unknown)
    }

    func testReadBookmarks_UnknownBrowserReturnsEmpty() {
        XCTAssertTrue(BookmarkReader.readBookmarks(for: .unknown, homeDirectoryOverride: tempRoot).isEmpty)
    }

    func testReadSafariBookmarks_ParsesFoldersBookmarksAndSkipsReadingList() throws {
        let safariChildren: [[String: Any]] = [
            [
                "WebBookmarkType": "WebBookmarkTypeList",
                "Title": "BookmarksBar",
                "Children": [
                    [
                        "WebBookmarkType": "WebBookmarkTypeLeaf",
                        "URLString": "https://apple.com",
                        "URIDictionary": ["title": "Apple"]
                    ],
                    [
                        "WebBookmarkType": "WebBookmarkTypeLeaf",
                        "URLString": "",
                        "URIDictionary": ["title": "IgnoredEmpty"]
                    ]
                ]
            ],
            [
                "WebBookmarkType": "WebBookmarkTypeList",
                "Title": "com.apple.ReadingList",
                "Children": [
                    [
                        "WebBookmarkType": "WebBookmarkTypeLeaf",
                        "URLString": "https://reading.list/",
                        "URIDictionary": ["title": "ShouldSkip"]
                    ]
                ]
            ],
            [
                "WebBookmarkType": "WebBookmarkTypeLeaf",
                "URLString": "https://example.com",
                "URIDictionary": ["title": "Example"]
            ]
        ]

        try writeSafariBookmarks(children: safariChildren, homeDirectory: tempRoot)

        let items = BookmarkReader.readBookmarks(for: .safari, homeDirectoryOverride: tempRoot)

        XCTAssertEqual(items.count, 2)

        let favorites = try XCTUnwrap(items.first)
        XCTAssertEqual(favorites.title, "Favorites")
        XCTAssertNil(favorites.url)
        XCTAssertEqual(favorites.children?.count, 1)
        XCTAssertEqual(favorites.children?.first?.title, "Apple")
        XCTAssertEqual(favorites.children?.first?.url, "https://apple.com")

        let directLink = try XCTUnwrap(items.last)
        XCTAssertEqual(directLink.title, "Example")
        XCTAssertEqual(directLink.url, "https://example.com")
    }

    func testReadChromiumBookmarks_ParsesRootsFoldersAndUrls() throws {
        let bookmarksJSON: [String: Any] = [
            "roots": [
                "bookmark_bar": [
                    "children": [
                        ["type": "url", "name": "GitHub", "url": "https://github.com"],
                        [
                            "type": "folder",
                            "name": "Dev",
                            "children": [
                                ["type": "url", "name": "Apple Docs", "url": "https://developer.apple.com"]
                            ]
                        ],
                        ["type": "url", "name": "NoURL", "url": ""],
                        ["type": "mystery", "name": "IgnoreMe"]
                    ]
                ],
                "other": [
                    "children": [
                        ["type": "url", "name": "Example", "url": "https://example.org"]
                    ]
                ],
                "synced": ["children": []]
            ]
        ]

        try writeChromiumBookmarks(bookmarksJSON, browser: .chrome, homeDirectory: tempRoot)

        let items = BookmarkReader.readBookmarks(for: .chrome, homeDirectoryOverride: tempRoot)

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].title, "Bookmarks Bar")
        XCTAssertEqual(items[1].title, "Other Bookmarks")

        let barChildren = try XCTUnwrap(items[0].children)
        XCTAssertEqual(barChildren.count, 2)
        XCTAssertEqual(barChildren[0].title, "GitHub")
        XCTAssertEqual(barChildren[0].url, "https://github.com")

        let folder = barChildren[1]
        XCTAssertEqual(folder.title, "Dev")
        XCTAssertNil(folder.url)
        XCTAssertEqual(folder.children?.count, 1)
        XCTAssertEqual(folder.children?.first?.title, "Apple Docs")
        XCTAssertEqual(folder.children?.first?.url, "https://developer.apple.com")
    }

    func testReadDefaultBrowserBookmarks_UsesBrowserAndHomeOverrides() throws {
        let bookmarksJSON: [String: Any] = [
            "roots": [
                "bookmark_bar": [
                    "children": [
                        ["type": "url", "name": "ControllerKeys", "url": "https://thekevintang.gumroad.com/l/xbox-controller-mapper"]
                    ]
                ],
                "other": ["children": []],
                "synced": ["children": []]
            ]
        ]

        try writeChromiumBookmarks(bookmarksJSON, browser: .chrome, homeDirectory: tempRoot)

        let result = BookmarkReader.readDefaultBrowserBookmarks(
            bundleIdentifierOverride: "com.google.chrome",
            homeDirectoryOverride: tempRoot
        )

        XCTAssertEqual(result.browser, .chrome)
        XCTAssertEqual(result.bookmarks.count, 1)
        XCTAssertEqual(result.bookmarks.first?.title, "Bookmarks Bar")
        XCTAssertEqual(result.bookmarks.first?.children?.first?.title, "ControllerKeys")
    }

    private func writeSafariBookmarks(children: [[String: Any]], homeDirectory: URL) throws {
        let safariDirectory = homeDirectory.appendingPathComponent("Library/Safari", isDirectory: true)
        try FileManager.default.createDirectory(at: safariDirectory, withIntermediateDirectories: true)

        let plistURL = safariDirectory.appendingPathComponent("Bookmarks.plist")
        let root: NSDictionary = ["Children": children]
        let success = root.write(to: plistURL, atomically: true)
        XCTAssertTrue(success, "Failed to write Safari Bookmarks.plist test fixture")
    }

    private func writeChromiumBookmarks(_ json: [String: Any], browser: BrowserType, homeDirectory: URL) throws {
        let bookmarksURL: URL
        switch browser {
        case .chrome:
            bookmarksURL = homeDirectory
                .appendingPathComponent("Library/Application Support/Google/Chrome/Default/Bookmarks")
        case .brave:
            bookmarksURL = homeDirectory
                .appendingPathComponent("Library/Application Support/BraveSoftware/Brave-Browser/Default/Bookmarks")
        case .edge:
            bookmarksURL = homeDirectory
                .appendingPathComponent("Library/Application Support/Microsoft Edge/Default/Bookmarks")
        case .arc:
            bookmarksURL = homeDirectory
                .appendingPathComponent("Library/Application Support/Arc/User Data/Default/Bookmarks")
        case .vivaldi:
            bookmarksURL = homeDirectory
                .appendingPathComponent("Library/Application Support/Vivaldi/Default/Bookmarks")
        case .safari, .unknown:
            XCTFail("Invalid browser type for Chromium bookmarks fixture")
            return
        }

        let parent = bookmarksURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        let data = try JSONSerialization.data(withJSONObject: json)
        try data.write(to: bookmarksURL)
    }
}
