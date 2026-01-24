import Foundation
import AppKit

/// A single bookmark item (either a folder or a URL bookmark)
struct BookmarkItem: Identifiable {
    let id = UUID()
    let title: String
    let url: String?
    let children: [BookmarkItem]?

    var isFolder: Bool { children != nil }

    /// Used by OutlineGroup - returns children for folders, nil for leaves
    var optionalChildren: [BookmarkItem]? {
        guard let children = children, !children.isEmpty else { return nil }
        return children
    }
}

/// Supported browser types for bookmark reading
enum BrowserType: String {
    case safari = "Safari"
    case chrome = "Chrome"
    case brave = "Brave"
    case edge = "Edge"
    case arc = "Arc"
    case vivaldi = "Vivaldi"
    case unknown = "Unknown"
}

/// Reads bookmarks from the user's default browser
class BookmarkReader {

    /// Detects the default browser
    static func detectDefaultBrowser() -> BrowserType {
        guard let bundleId = LSCopyDefaultHandlerForURLScheme("https" as CFString)?.takeRetainedValue() as String? else {
            return .unknown
        }

        switch bundleId {
        case "com.apple.safari": return .safari
        case "com.google.chrome": return .chrome
        case "com.brave.browser": return .brave
        case "com.microsoft.edgemac": return .edge
        case "company.thebrowser.browser": return .arc
        case "com.vivaldi.vivaldi": return .vivaldi
        default:
            // Check if it's a Chromium-based browser by checking for Bookmarks file
            let lowered = bundleId.lowercased()
            if lowered.contains("chrome") { return .chrome }
            if lowered.contains("brave") { return .brave }
            if lowered.contains("edge") { return .edge }
            return .unknown
        }
    }

    /// Reads bookmarks for the given browser type
    static func readBookmarks(for browser: BrowserType) -> [BookmarkItem] {
        switch browser {
        case .safari:
            return readSafariBookmarks()
        case .chrome, .brave, .edge, .arc, .vivaldi:
            if let path = chromiumBookmarksPath(for: browser) {
                return readChromiumBookmarks(path: path)
            }
            return []
        case .unknown:
            return []
        }
    }

    /// Reads bookmarks from the default browser
    static func readDefaultBrowserBookmarks() -> (browser: BrowserType, bookmarks: [BookmarkItem]) {
        let browser = detectDefaultBrowser()
        let bookmarks = readBookmarks(for: browser)
        return (browser, bookmarks)
    }

    // MARK: - Safari

    private static func readSafariBookmarks() -> [BookmarkItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let plistURL = home.appendingPathComponent("Library/Safari/Bookmarks.plist")

        guard let dict = NSDictionary(contentsOf: plistURL) else {
            NSLog("[BookmarkReader] Failed to read Safari bookmarks plist")
            return []
        }

        guard let children = dict["Children"] as? [[String: Any]] else {
            return []
        }

        return parseSafariChildren(children)
    }

    private static func parseSafariChildren(_ children: [[String: Any]]) -> [BookmarkItem] {
        var items: [BookmarkItem] = []

        for child in children {
            guard let type = child["WebBookmarkType"] as? String else { continue }

            switch type {
            case "WebBookmarkTypeList":
                // Folder
                let title = child["Title"] as? String ?? "Untitled Folder"
                let subChildren = child["Children"] as? [[String: Any]] ?? []
                let subItems = parseSafariChildren(subChildren)
                // Skip empty folders and special folders like Reading List
                if title == "com.apple.ReadingList" { continue }
                let displayTitle = title == "BookmarksBar" ? "Favorites" : title
                items.append(BookmarkItem(title: displayTitle, url: nil, children: subItems))

            case "WebBookmarkTypeLeaf":
                // Bookmark
                let uriDict = child["URIDictionary"] as? [String: Any]
                let title = uriDict?["title"] as? String ?? child["URLString"] as? String ?? "Untitled"
                let url = child["URLString"] as? String
                if let url = url, !url.isEmpty {
                    items.append(BookmarkItem(title: title, url: url, children: nil))
                }

            default:
                continue
            }
        }

        return items
    }

    // MARK: - Chromium

    private static func chromiumBookmarksPath(for browser: BrowserType) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        switch browser {
        case .chrome:
            return "\(home)/Library/Application Support/Google/Chrome/Default/Bookmarks"
        case .brave:
            return "\(home)/Library/Application Support/BraveSoftware/Brave-Browser/Default/Bookmarks"
        case .edge:
            return "\(home)/Library/Application Support/Microsoft Edge/Default/Bookmarks"
        case .arc:
            return "\(home)/Library/Application Support/Arc/User Data/Default/Bookmarks"
        case .vivaldi:
            return "\(home)/Library/Application Support/Vivaldi/Default/Bookmarks"
        default:
            return nil
        }
    }

    private static func readChromiumBookmarks(path: String) -> [BookmarkItem] {
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roots = json["roots"] as? [String: Any] else {
            NSLog("[BookmarkReader] Failed to read Chromium bookmarks at: \(path)")
            return []
        }

        var items: [BookmarkItem] = []

        // Parse known root folders
        let rootKeys = ["bookmark_bar", "other", "synced"]
        let rootNames = ["Bookmarks Bar", "Other Bookmarks", "Mobile Bookmarks"]

        for (index, key) in rootKeys.enumerated() {
            guard let root = roots[key] as? [String: Any],
                  let children = root["children"] as? [[String: Any]],
                  !children.isEmpty else { continue }

            let folderItems = parseChromiumChildren(children)
            if !folderItems.isEmpty {
                items.append(BookmarkItem(title: rootNames[index], url: nil, children: folderItems))
            }
        }

        return items
    }

    private static func parseChromiumChildren(_ children: [[String: Any]]) -> [BookmarkItem] {
        var items: [BookmarkItem] = []

        for child in children {
            guard let type = child["type"] as? String,
                  let name = child["name"] as? String else { continue }

            switch type {
            case "folder":
                let subChildren = child["children"] as? [[String: Any]] ?? []
                let subItems = parseChromiumChildren(subChildren)
                items.append(BookmarkItem(title: name, url: nil, children: subItems))

            case "url":
                let url = child["url"] as? String
                if let url = url, !url.isEmpty {
                    items.append(BookmarkItem(title: name, url: url, children: nil))
                }

            default:
                continue
            }
        }

        return items
    }
}
