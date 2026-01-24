import Foundation

/// An app to show in the on-screen keyboard app bar for quick switching
struct AppBarItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var bundleIdentifier: String
    var displayName: String  // Cached for display when app not installed

    private enum CodingKeys: String, CodingKey {
        case id, bundleIdentifier, displayName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier) ?? ""
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
    }

    init(id: UUID = UUID(), bundleIdentifier: String, displayName: String) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
    }
}

/// A website link to show in the on-screen keyboard for quick access
struct WebsiteLink: Identifiable, Codable, Equatable {
    var id = UUID()
    var url: String
    var displayName: String
    var faviconData: Data?  // Cached favicon PNG data

    private enum CodingKeys: String, CodingKey {
        case id, url, displayName, faviconData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        faviconData = try container.decodeIfPresent(Data.self, forKey: .faviconData)
    }

    init(id: UUID = UUID(), url: String, displayName: String, faviconData: Data? = nil) {
        self.id = id
        self.url = url
        self.displayName = displayName
        self.faviconData = faviconData
    }

    /// Returns the URL as a proper URL object, or nil if invalid
    var urlObject: URL? {
        URL(string: url)
    }

    /// Returns the domain for display purposes (e.g., "google.com")
    var domain: String? {
        urlObject?.host?.replacingOccurrences(of: "www.", with: "")
    }
}

/// A quick text snippet that can be typed or run as a terminal command
struct QuickText: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var isTerminalCommand: Bool

    private enum CodingKeys: String, CodingKey {
        case id, text, isTerminalCommand
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        isTerminalCommand = try container.decodeIfPresent(Bool.self, forKey: .isTerminalCommand) ?? false
    }

    init(text: String = "", isTerminalCommand: Bool = false) {
        self.text = text
        self.isTerminalCommand = isTerminalCommand
    }

    /// Check if text contains any {variable} patterns
    var containsVariables: Bool {
        let pattern = #"\{[a-z._]+\}"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }
}

/// Settings for the on-screen keyboard feature
struct OnScreenKeyboardSettings: Codable, Equatable {
    var quickTexts: [QuickText] = []
    var defaultTerminalApp: String = "Terminal"  // Bundle name or path
    /// Delay between each character when typing text snippets (in seconds)
    var typingDelay: Double = 0.03  // 30ms default, roughly 33 chars/second
    /// Apps to show in the app bar for quick switching
    var appBarItems: [AppBarItem] = []
    /// Website links for quick browser access
    var websiteLinks: [WebsiteLink] = []
    /// Show extended function keys (F13-F20) above F1-F12
    var showExtendedFunctionKeys: Bool = false
    /// Global keyboard shortcut key code to toggle on-screen keyboard
    var toggleShortcutKeyCode: UInt16?
    /// Global keyboard shortcut modifiers to toggle on-screen keyboard
    var toggleShortcutModifiers: ModifierFlags = ModifierFlags()
    /// When activating an app, bring all its windows to front (not just one)
    var activateAllWindows: Bool = true
    /// Show website links in the command wheel instead of apps
    var wheelShowsWebsites: Bool = false
    /// Modifier key to hold for showing alternate wheel content (apps↔websites)
    var wheelAlternateModifiers: ModifierFlags = ModifierFlags()

    /// Available terminal apps to choose from
    static let terminalOptions = [
        "Terminal",
        "iTerm",
        "Warp",
        "Alacritty",
        "Kitty",
        "Hyper",
        "Tabby",
        "WezTerm",
        "Rio"
    ]

    /// Typing speed presets (0 = paste from clipboard instead of typing)
    static let typingSpeedPresets: [(name: String, delay: Double)] = [
        ("Paste", 0),         // Use clipboard paste (Cmd+V)
        ("Slow", 0.08),       // ~12 chars/sec
        ("Medium", 0.05),     // ~20 chars/sec
        ("Fast", 0.03),       // ~33 chars/sec
        ("Very Fast", 0.015)  // ~66 chars/sec
    ]

    // Custom decoder to handle missing keys from older config files
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        quickTexts = try container.decodeIfPresent([QuickText].self, forKey: .quickTexts) ?? []
        defaultTerminalApp = try container.decodeIfPresent(String.self, forKey: .defaultTerminalApp) ?? "Terminal"
        typingDelay = try container.decodeIfPresent(Double.self, forKey: .typingDelay) ?? 0.03
        appBarItems = try container.decodeIfPresent([AppBarItem].self, forKey: .appBarItems) ?? []
        websiteLinks = try container.decodeIfPresent([WebsiteLink].self, forKey: .websiteLinks) ?? []
        showExtendedFunctionKeys = try container.decodeIfPresent(Bool.self, forKey: .showExtendedFunctionKeys) ?? false
        toggleShortcutKeyCode = try container.decodeIfPresent(UInt16.self, forKey: .toggleShortcutKeyCode)
        toggleShortcutModifiers = try container.decodeIfPresent(ModifierFlags.self, forKey: .toggleShortcutModifiers) ?? ModifierFlags()
        activateAllWindows = try container.decodeIfPresent(Bool.self, forKey: .activateAllWindows) ?? true
        wheelShowsWebsites = try container.decodeIfPresent(Bool.self, forKey: .wheelShowsWebsites) ?? false
        wheelAlternateModifiers = try container.decodeIfPresent(ModifierFlags.self, forKey: .wheelAlternateModifiers) ?? ModifierFlags()
    }

    init(quickTexts: [QuickText] = [], defaultTerminalApp: String = "Terminal", typingDelay: Double = 0.03, appBarItems: [AppBarItem] = [], websiteLinks: [WebsiteLink] = [], showExtendedFunctionKeys: Bool = false, toggleShortcutKeyCode: UInt16? = nil, toggleShortcutModifiers: ModifierFlags = ModifierFlags(), activateAllWindows: Bool = true, wheelShowsWebsites: Bool = false, wheelAlternateModifiers: ModifierFlags = ModifierFlags()) {
        self.quickTexts = quickTexts
        self.defaultTerminalApp = defaultTerminalApp
        self.typingDelay = typingDelay
        self.appBarItems = appBarItems
        self.websiteLinks = websiteLinks
        self.showExtendedFunctionKeys = showExtendedFunctionKeys
        self.toggleShortcutKeyCode = toggleShortcutKeyCode
        self.toggleShortcutModifiers = toggleShortcutModifiers
        self.activateAllWindows = activateAllWindows
        self.wheelShowsWebsites = wheelShowsWebsites
        self.wheelAlternateModifiers = wheelAlternateModifiers
    }

    private enum CodingKeys: String, CodingKey {
        case quickTexts, defaultTerminalApp, typingDelay, appBarItems, websiteLinks, showExtendedFunctionKeys
        case toggleShortcutKeyCode, toggleShortcutModifiers, activateAllWindows, wheelShowsWebsites
        case wheelAlternateModifiers
    }
}
