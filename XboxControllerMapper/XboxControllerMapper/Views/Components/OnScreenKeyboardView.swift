import SwiftUI
import AppKit
import Carbon.HIToolbox

// MARK: - Navigation Highlight Overlay System

/// Preference key for reporting navigable item bounds
struct NavigationItemBoundsKey: PreferenceKey {
    static var defaultValue: [KeyboardNavigationItem: Anchor<CGRect>] = [:]

    static func reduce(value: inout [KeyboardNavigationItem: Anchor<CGRect>], nextValue: () -> [KeyboardNavigationItem: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// View modifier to report an item's bounds for navigation highlight
struct NavigationItemBoundsModifier: ViewModifier {
    let item: KeyboardNavigationItem

    func body(content: Content) -> some View {
        content.anchorPreference(key: NavigationItemBoundsKey.self, value: .bounds) { anchor in
            [item: anchor]
        }
    }
}

extension View {
    func navigationItemBounds(_ item: KeyboardNavigationItem) -> some View {
        modifier(NavigationItemBoundsModifier(item: item))
    }
}

/// Floating overlay that draws the navigation highlight
struct NavigationHighlightOverlay: View {
    let highlightedItem: KeyboardNavigationItem?
    let itemBounds: [KeyboardNavigationItem: Anchor<CGRect>]
    let geometryProxy: GeometryProxy

    var body: some View {
        if let item = highlightedItem, let anchor = itemBounds[item] {
            let rect = geometryProxy[anchor]
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange, lineWidth: 3)
                .frame(width: rect.width + 6, height: rect.height + 6)
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
        }
    }
}

/// A clickable on-screen keyboard that sends key presses to the system
struct OnScreenKeyboardView: View {
    /// Callback to send a key press with modifiers
    var onKeyPress: (CGKeyCode, ModifierFlags) -> Void
    /// Callback to execute a quick text (text snippet or terminal command)
    var onQuickText: ((QuickText) -> Void)?
    /// Callback to activate an app from the app bar
    var onAppActivate: ((String) -> Void)?
    /// Callback to open a website link
    var onWebsiteLinkOpen: ((String) -> Void)?
    /// Quick texts to display above keyboard
    var quickTexts: [QuickText] = []
    /// App bar items for quick app switching
    var appBarItems: [AppBarItem] = []
    /// Website links for quick access
    var websiteLinks: [WebsiteLink] = []
    /// Whether to show extended function keys (F13-F20) above F1-F12
    var showExtendedFunctionKeys: Bool = false

    /// Observe keyboard manager for D-pad navigation state
    @ObservedObject private var keyboardManager = OnScreenKeyboardManager.shared

    @State private var activeModifiers = ModifierFlags()
    @State private var isCapsLockActive = false
    @State private var hoveredKey: CGKeyCode?
    @State private var pressedKey: CGKeyCode?
    @State private var hoveredQuickTextId: UUID?
    @State private var pressedQuickTextId: UUID?
    @State private var hoveredAppBarItemId: UUID?
    @State private var pressedAppBarItemId: UUID?
    @State private var hoveredWebsiteLinkId: UUID?
    @State private var pressedWebsiteLinkId: UUID?

    // Key size constants - slightly larger for the new aesthetic
    private let keyWidth: CGFloat = 68
    private let keyHeight: CGFloat = 60
    private let keySpacing: CGFloat = 8 // Increased spacing for "floating" look

    // Secondary characters for keys (shown above primary)
    private let secondaryKeys: [String: String] = [
        // Number row
        "`": "~", "1": "!", "2": "@", "3": "#", "4": "$", "5": "%",
        "6": "^", "7": "&", "8": "*", "9": "(", "0": ")", "-": "_", "=": "+",
        // Symbol keys
        "[": "{", "]": "}", "\\": "|",
        ";": ":", "'": "\"",
        ",": "<", ".": ">", "/": "?"
    ]

    private var textSnippets: [QuickText] {
        quickTexts.filter { !$0.isTerminalCommand }
    }

    private var terminalCommands: [QuickText] {
        quickTexts.filter { $0.isTerminalCommand }
    }

    // MARK: - Keyboard Row Indices (for position-based navigation)
    // These correspond to KeyboardNavigationMap.allRows() indices
    private var mediaRowIndex: Int { 0 }
    private var extendedFKeyRowIndex: Int { showExtendedFunctionKeys ? 1 : -1 }
    private var functionKeyRowIndex: Int { showExtendedFunctionKeys ? 2 : 1 }
    private var numberRowIndex: Int { showExtendedFunctionKeys ? 3 : 2 }
    private var qwertyRowIndex: Int { showExtendedFunctionKeys ? 4 : 3 }
    private var asdfRowIndex: Int { showExtendedFunctionKeys ? 5 : 4 }
    private var zxcvRowIndex: Int { showExtendedFunctionKeys ? 6 : 5 }
    private var bottomRowIndex: Int { showExtendedFunctionKeys ? 7 : 6 }

    var body: some View {
        keyboardContent
            .overlayPreferenceValue(NavigationItemBoundsKey.self) { itemBounds in
                GeometryReader { geometry in
                    if keyboardManager.navigationModeActive {
                        NavigationHighlightOverlay(
                            highlightedItem: keyboardManager.highlightedItem,
                            itemBounds: itemBounds,
                            geometryProxy: geometry
                        )
                    }
                }
            }
    }

    private var keyboardContent: some View {
        VStack(spacing: 12) {
            // Website links section (above app bar)
            if !websiteLinks.isEmpty {
                websiteLinksSection
                    .padding(.horizontal, 12)
                Divider()
                    .background(Color.white.opacity(0.1))
                    .padding(.horizontal, 8)
            }

            // App bar section (if any apps configured)
            if !appBarItems.isEmpty {
                appBarSection
                    .padding(.horizontal, 12)
                Divider()
                    .background(Color.white.opacity(0.1))
                    .padding(.horizontal, 8)
            }

            // Quick text sections (if any)
            if !quickTexts.isEmpty {
                quickTextSection
                    .padding(.horizontal, 12)
                Divider()
                    .background(Color.white.opacity(0.1))
                    .padding(.horizontal, 8)
            }

            // Media controls row (Playback, Volume, Brightness)
            mediaControlsRow
                .padding(.horizontal, 12)

            // Extended function key row (F13-F20) - shown above F1-F12 when enabled
            if showExtendedFunctionKeys {
                extendedFunctionKeyRow
                    .padding(.horizontal, 12)
            }

            // Function key row (Esc + F1-F12)
            functionKeyRow
                .padding(.horizontal, 12)

            // Main keyboard with navigation column
            HStack(alignment: .top, spacing: keySpacing * 2) {
                // Main keyboard
                VStack(spacing: keySpacing) {
                    numberRow
                    qwertyRow
                    asdfRow
                    zxcvRow
                    bottomRow
                }

                // Navigation keys column
                navigationKeyColumn
            }
            .padding(.horizontal, 12)

            // Controller Hint Footer
            HStack(spacing: 8) {
                Spacer()

                // Command Wheel Hint
                HStack(spacing: 8) {
                    ButtonIconView(button: .rightThumbstick, isPressed: false, isDualSense: false, showDirectionalArrows: true)
                        .frame(width: 32, height: 32)

                    Text("Command Wheel")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.3))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )

                Spacer()
            }
            .padding(.top, 4)
        }
        .padding(24)
        // GTA-style backdrop: Dark, blurred, slightly translucent
        .background(
            ZStack {
                Color.black.opacity(0.6)
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            }
        )
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
    }

    // MARK: - App Bar Section

    // Fixed width for app bar to ensure proper layout calculation
    private let appBarWidth: CGFloat = 1050 // Adjusted for new spacing
    private let itemsPerRow = 12

    private var appBarSection: some View {
        let rows = appBarItems.chunked(into: itemsPerRow)
        return VStack(spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row) { item in
                        appBarButton(item)
                    }
                }
            }
        }
        .frame(width: appBarWidth)
    }

    private func appBarButton(_ item: AppBarItem) -> some View {
        // Only use mouse hover - navigation highlight is handled by overlay
        let isHovered = hoveredAppBarItemId == item.id && !keyboardManager.navigationModeActive
        let isPressed = pressedAppBarItemId == item.id
        let iconSize: CGFloat = 56

        return Button {
            // Exit navigation mode when mouse clicks
            keyboardManager.exitNavigationMode()
            pressedAppBarItemId = item.id
            onAppActivate?(item.bundleIdentifier)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if pressedAppBarItemId == item.id {
                    pressedAppBarItemId = nil
                }
            }
        } label: {
            VStack(spacing: 4) {
                appIcon(for: item.bundleIdentifier)
                    .resizable()
                    .navigationItemBounds(.appBarItem(item.id))
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize, height: iconSize)
                    .saturation(isHovered ? 1.0 : 0.8) // Slight desaturation when idle

                Text(item.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: iconSize + 16)
                    .foregroundColor(isHovered ? .white : .secondary)
            }
            .padding(8)
            .background(GlassKeyBackground(isHovered: isHovered, isPressed: isPressed, specialColor: .orange, cornerRadius: 12))
            .cornerRadius(12)
            .scaleEffect(isPressed ? 0.95 : (isHovered ? 1.05 : 1.0))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isPressed)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredAppBarItemId = hovering ? item.id : nil
            if hovering {
                keyboardManager.setMouseHoveredAppBarItem(item.id)
            }
        }
    }

    private func appIcon(for bundleIdentifier: String) -> Image {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
           let icon = NSWorkspace.shared.icon(forFile: url.path) as NSImage? {
            return Image(nsImage: icon)
        }
        return Image(systemName: "app.fill")
    }

    // MARK: - Website Links Section

    private var websiteLinksSection: some View {
        let rows = websiteLinks.chunked(into: itemsPerRow)
        return VStack(spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row) { link in
                        websiteLinkButton(link)
                    }
                }
            }
        }
        .frame(width: appBarWidth)
    }

    private func websiteLinkButton(_ link: WebsiteLink) -> some View {
        // Only use mouse hover - navigation highlight is handled by overlay
        let isHovered = hoveredWebsiteLinkId == link.id && !keyboardManager.navigationModeActive
        let isPressed = pressedWebsiteLinkId == link.id
        let iconSize: CGFloat = 56

        return Button {
            // Exit navigation mode when mouse clicks
            keyboardManager.exitNavigationMode()
            pressedWebsiteLinkId = link.id
            onWebsiteLinkOpen?(link.url)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if pressedWebsiteLinkId == link.id {
                    pressedWebsiteLinkId = nil
                }
            }
        } label: {
            VStack(spacing: 4) {
                websiteFavicon(for: link)
                    .frame(width: iconSize, height: iconSize)
                    .saturation(isHovered ? 1.0 : 0.8)
                    .navigationItemBounds(.websiteLink(link.id))

                Text(link.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: iconSize + 16)
                    .foregroundColor(isHovered ? .white : .secondary)
            }
            .padding(8)
            .background(GlassKeyBackground(isHovered: isHovered, isPressed: isPressed, specialColor: .orange, cornerRadius: 12))
            .cornerRadius(12)
            .scaleEffect(isPressed ? 0.95 : (isHovered ? 1.05 : 1.0))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isPressed)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredWebsiteLinkId = hovering ? link.id : nil
            if hovering {
                keyboardManager.setMouseHoveredWebsiteLink(link.id)
            }
        }
    }

    @ViewBuilder
    private func websiteFavicon(for link: WebsiteLink) -> some View {
        if let data = link.faviconData,
           let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .cornerRadius(8)
        } else {
            Image(systemName: "globe")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Quick Text Section

    private var quickTextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !terminalCommands.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "terminal")
                        .font(.caption.bold())
                        .foregroundColor(.accentColor)
                    Text("COMMANDS")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 12) // Match button start
                quickTextButtonRow(terminalCommands)
            }

            if !textSnippets.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "text.quote")
                        .font(.caption.bold())
                        .foregroundColor(.accentColor)
                    Text("TEXT")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 12) // Match button start
                quickTextButtonRow(textSnippets)
            }
        }
    }

    private func quickTextButtonRow(_ items: [QuickText]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    quickTextButton(item)
                }
            }
            .padding(.vertical, 8) // Space for shadows/scaling
            .padding(.horizontal, 12) // Prevent clipping on left/right during scale
        }
        .padding(.horizontal, -12) // Negative padding to let scroll content touch edges if needed while inner padding prevents clipping
    }

    private func quickTextButton(_ quickText: QuickText) -> some View {
        // Only use mouse hover - navigation highlight is handled by overlay
        let isHovered = hoveredQuickTextId == quickText.id && !keyboardManager.navigationModeActive
        let isPressed = pressedQuickTextId == quickText.id

        return Button {
            // Exit navigation mode when mouse clicks
            keyboardManager.exitNavigationMode()
            pressedQuickTextId = quickText.id
            onQuickText?(quickText)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if pressedQuickTextId == quickText.id {
                    pressedQuickTextId = nil
                }
            }
        } label: {
            HStack(spacing: 6) {
                if quickText.isTerminalCommand {
                    Image(systemName: "terminal")
                        .font(.system(size: 10))
                }
                Text(quickText.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .navigationItemBounds(.quickText(quickText.id))
            .padding(.vertical, 12)
            .frame(minWidth: 80, maxWidth: 300)
            .background(GlassKeyBackground(isHovered: isHovered, isPressed: isPressed, specialColor: .orange))
            .foregroundColor(isPressed ? .white : (isHovered ? .white : .primary))
            .cornerRadius(8)
            .scaleEffect(isPressed ? 0.95 : (isHovered ? 1.02 : 1.0))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isPressed)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredQuickTextId = hovering ? quickText.id : nil
            if hovering {
                keyboardManager.setMouseHoveredQuickText(quickText.id)
            }
        }
    }

    // MARK: - Function Keys

    private let f1to12Codes: [Int] = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
        kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12
    ]

    private let f13to20Codes: [Int] = [
        kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20
    ]

    // MARK: - Media Controls Row

    private var mediaControlsRow: some View {
        HStack(spacing: keySpacing * 6) {
            mediaControlGroup(title: "PLAYBACK", icon: "play.circle.fill") {
                mediaKey(KeyCodeMapping.mediaPrevious, label: "", symbol: "backward.end.fill", keyboardRow: mediaRowIndex, column: 0)
                mediaKey(KeyCodeMapping.mediaPlayPause, label: "", symbol: "playpause.fill", keyboardRow: mediaRowIndex, column: 1)
                mediaKey(KeyCodeMapping.mediaNext, label: "", symbol: "forward.end.fill", keyboardRow: mediaRowIndex, column: 2)
            }

            mediaControlGroup(title: "SOUND", icon: "speaker.wave.2.fill") {
                mediaKey(KeyCodeMapping.volumeMute, label: "", symbol: "speaker.slash.fill", keyboardRow: mediaRowIndex, column: 3)
                mediaKey(KeyCodeMapping.volumeDown, label: "", symbol: "speaker.wave.1.fill", keyboardRow: mediaRowIndex, column: 4)
                mediaKey(KeyCodeMapping.volumeUp, label: "", symbol: "speaker.wave.3.fill", keyboardRow: mediaRowIndex, column: 5)
            }

            mediaControlGroup(title: "DISPLAY", icon: "sun.max.fill") {
                mediaKey(KeyCodeMapping.brightnessDown, label: "", symbol: "sun.min.fill", keyboardRow: mediaRowIndex, column: 6)
                mediaKey(KeyCodeMapping.brightnessUp, label: "", symbol: "sun.max.fill", keyboardRow: mediaRowIndex, column: 7)
            }
        }
        .padding(.vertical, 4)
    }

    private func mediaControlGroup<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(.secondary)
            .padding(.leading, 2)

            HStack(spacing: keySpacing) {
                content()
            }
        }
    }

    private func mediaKey(_ keyCode: CGKeyCode, label: String, symbol: String, keyboardRow: Int, column: Int) -> some View {
        // Only use mouse hover for visual feedback - navigation highlight is handled by overlay
        let isHovered = hoveredKey == keyCode && !keyboardManager.navigationModeActive
        let isPressed = pressedKey == keyCode

        return Button {
            // Exit navigation mode when mouse clicks
            keyboardManager.exitNavigationMode()
            pressedKey = keyCode
            onKeyPress(keyCode, activeModifiers)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if pressedKey == keyCode {
                    pressedKey = nil
                }
            }
        } label: {
            VStack(spacing: 0) {
                Image(systemName: symbol)
                    .font(.system(size: 16))
            }
            .frame(width: 50, height: 40)
            .background(GlassKeyBackground(isHovered: isHovered, isPressed: isPressed, specialColor: .orange))
            .foregroundColor(isPressed ? .white : .primary)
            .cornerRadius(8)
            .scaleEffect(isPressed ? 0.9 : (isHovered ? 1.1 : 1.0))
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovered)
        }
        .buttonStyle(.plain)
        .navigationItemBounds(.keyPosition(row: keyboardRow, column: column))
        .onHover { hovering in
            hoveredKey = hovering ? keyCode : nil
            if hovering {
                keyboardManager.setMouseHoveredKeyPosition(row: keyboardRow, column: column)
            }
        }
    }

    private var extendedFunctionKeyRow: some View {
        HStack(spacing: keySpacing) {
            Spacer().frame(width: 85) // Align with Esc
            Spacer().frame(width: 30)

            ForEach(0..<4, id: \.self) { i in
                clickableKey(CGKeyCode(f13to20Codes[i]), label: "F\(i + 13)", width: 75)
            }
            Spacer().frame(width: 19)
            ForEach(4..<8, id: \.self) { i in
                clickableKey(CGKeyCode(f13to20Codes[i]), label: "F\(i + 13)", width: 75)
            }
            Spacer().frame(width: 19)
            ForEach(0..<4, id: \.self) { _ in
                Color.clear.frame(width: 75, height: keyHeight)
            }
        }
    }

    private var functionKeyRow: some View {
        HStack(spacing: keySpacing) {
            clickableKey(CGKeyCode(kVK_Escape), label: "Esc", width: 85, isSpecial: true)

            Spacer().frame(width: 30)

            ForEach(0..<4, id: \.self) { i in
                clickableKey(CGKeyCode(f1to12Codes[i]), label: "F\(i + 1)", width: 75)
            }
            Spacer().frame(width: 19)
            ForEach(4..<8, id: \.self) { i in
                clickableKey(CGKeyCode(f1to12Codes[i]), label: "F\(i + 1)", width: 75)
            }
            Spacer().frame(width: 19)
            ForEach(8..<12, id: \.self) { i in
                clickableKey(CGKeyCode(f1to12Codes[i]), label: "F\(i + 1)", width: 75)
            }
        }
    }

    // MARK: - Number Row

    // Carbon key codes for number keys (NOT sequential!)
    private let numberKeyCodes: [Int] = [
        kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
        kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9, kVK_ANSI_0
    ]

    private var numberRow: some View {
        HStack(spacing: keySpacing) {
            clickableKey(CGKeyCode(kVK_ANSI_Grave), label: "`")

            ForEach(0..<10, id: \.self) { i in
                let keyCode = CGKeyCode(numberKeyCodes[i])
                let displayNum = i == 9 ? "0" : "\(i + 1)"
                clickableKey(keyCode, label: displayNum)
            }

            clickableKey(CGKeyCode(kVK_ANSI_Minus), label: "-")
            clickableKey(CGKeyCode(kVK_ANSI_Equal), label: "=")
            clickableKey(CGKeyCode(kVK_Delete), label: "⌫", width: 107, isSpecial: true)
        }
    }

    // MARK: - QWERTY Row

    private var qwertyRow: some View {
        HStack(spacing: keySpacing) {
            clickableKey(CGKeyCode(kVK_Tab), label: "Tab", width: 95, isSpecial: true)

            let qwertyKeys = ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"]
            let qwertyCodes: [Int] = [kVK_ANSI_Q, kVK_ANSI_W, kVK_ANSI_E, kVK_ANSI_R, kVK_ANSI_T, kVK_ANSI_Y, kVK_ANSI_U, kVK_ANSI_I, kVK_ANSI_O, kVK_ANSI_P]

            ForEach(0..<qwertyKeys.count, id: \.self) { i in
                clickableKey(CGKeyCode(qwertyCodes[i]), label: qwertyKeys[i])
            }

            clickableKey(CGKeyCode(kVK_ANSI_LeftBracket), label: "[")
            clickableKey(CGKeyCode(kVK_ANSI_RightBracket), label: "]")
            clickableKey(CGKeyCode(kVK_ANSI_Backslash), label: "\\", width: 95)
        }
    }

    // MARK: - ASDF Row

    private var asdfRow: some View {
        HStack(spacing: keySpacing) {
            capsLockKey(width: 112)

            let asdfKeys = ["A", "S", "D", "F", "G", "H", "J", "K", "L"]
            let asdfCodes: [Int] = [kVK_ANSI_A, kVK_ANSI_S, kVK_ANSI_D, kVK_ANSI_F, kVK_ANSI_G, kVK_ANSI_H, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L]

            ForEach(0..<asdfKeys.count, id: \.self) { i in
                clickableKey(CGKeyCode(asdfCodes[i]), label: asdfKeys[i])
            }

            clickableKey(CGKeyCode(kVK_ANSI_Semicolon), label: ";")
            clickableKey(CGKeyCode(kVK_ANSI_Quote), label: "'")
            clickableKey(CGKeyCode(kVK_Return), label: "Return", width: 125, isSpecial: true)
        }
    }

    // MARK: - ZXCV Row

    private var zxcvRow: some View {
        HStack(spacing: keySpacing) {
            modifierKey(label: "⇧ Shift", width: 140, modifier: \.shift, keyboardRow: zxcvRowIndex, column: 0)

            let zxcvKeys = ["Z", "X", "C", "V", "B", "N", "M"]
            let zxcvCodes: [Int] = [kVK_ANSI_Z, kVK_ANSI_X, kVK_ANSI_C, kVK_ANSI_V, kVK_ANSI_B, kVK_ANSI_N, kVK_ANSI_M]

            ForEach(0..<zxcvKeys.count, id: \.self) { i in
                clickableKey(CGKeyCode(zxcvCodes[i]), label: zxcvKeys[i])
            }

            clickableKey(CGKeyCode(kVK_ANSI_Comma), label: ",")
            clickableKey(CGKeyCode(kVK_ANSI_Period), label: ".")
            clickableKey(CGKeyCode(kVK_ANSI_Slash), label: "/")
            modifierKey(label: "⇧ Shift", width: 140, modifier: \.shift, keyboardRow: zxcvRowIndex, column: 11)
        }
    }

    // MARK: - Bottom Row

    private var bottomRow: some View {
        HStack(spacing: keySpacing) {
            modifierKey(label: "⌃", width: 78, modifier: \.control, keyboardRow: bottomRowIndex, column: 0)
            modifierKey(label: "⌥", width: 78, modifier: \.option, keyboardRow: bottomRowIndex, column: 1)
            modifierKey(label: "⌘", width: 93, modifier: \.command, keyboardRow: bottomRowIndex, column: 2)

            clickableKey(CGKeyCode(kVK_Space), label: "", width: 369) // Spacebar

            modifierKey(label: "⌘", width: 93, modifier: \.command, keyboardRow: bottomRowIndex, column: 4)
            modifierKey(label: "⌥", width: 78, modifier: \.option, keyboardRow: bottomRowIndex, column: 5)

            // Arrow keys cluster
            VStack(spacing: 4) {
                clickableKey(CGKeyCode(kVK_UpArrow), label: "↑", width: 60, height: 28, isSpecial: true)
                HStack(spacing: 4) {
                    clickableKey(CGKeyCode(kVK_LeftArrow), label: "←", width: 60, height: 28, isSpecial: true)
                    clickableKey(CGKeyCode(kVK_DownArrow), label: "↓", width: 60, height: 28, isSpecial: true)
                    clickableKey(CGKeyCode(kVK_RightArrow), label: "→", width: 60, height: 28, isSpecial: true)
                }
            }
        }
    }

    // MARK: - Navigation Keys

    private var navigationKeyColumn: some View {
        VStack(spacing: keySpacing) {
            clickableKey(CGKeyCode(kVK_ForwardDelete), label: "Del", isSpecial: true)
            clickableKey(CGKeyCode(kVK_Home), label: "Home", isSpecial: true)
            clickableKey(CGKeyCode(kVK_End), label: "End", isSpecial: true)
            clickableKey(CGKeyCode(kVK_PageUp), label: "PgUp", isSpecial: true)
            clickableKey(CGKeyCode(kVK_PageDown), label: "PgDn", isSpecial: true)
        }
    }

    // MARK: - Key Button

    @ViewBuilder
    private func clickableKey(_ keyCode: CGKeyCode, label: String, width: CGFloat? = nil, height: CGFloat? = nil, isSpecial: Bool = false, keyboardRow: Int? = nil, column: Int? = nil) -> some View {
        let actualWidth = width ?? keyWidth
        let actualHeight = height ?? keyHeight
        // Only use mouse hover - navigation highlight is handled by overlay
        let isHovered = hoveredKey == keyCode && !keyboardManager.navigationModeActive
        let isPressed = pressedKey == keyCode
        let secondary = secondaryKeys[label]
        let isShiftActive = activeModifiers.shift

        // Check if this is a single letter key (A-Z)
        let isSingleLetter = label.count == 1 && label.first?.isLetter == true

        Button {
            // Exit navigation mode when mouse clicks
            keyboardManager.exitNavigationMode()
            pressedKey = keyCode
            var modifiersToSend = activeModifiers
            if isCapsLockActive && isSingleLetter {
                modifiersToSend.shift = true
            }
            onKeyPress(keyCode, modifiersToSend)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if pressedKey == keyCode {
                    pressedKey = nil
                }
            }
        } label: {
            VStack(spacing: 0) {
                if let secondary = secondary {
                    // Secondary character
                    Text(secondary)
                        .font(.system(size: isShiftActive ? 16 : 12, weight: .bold))
                        .foregroundColor(isShiftActive ? .white : .secondary)
                        .opacity(isShiftActive ? 1.0 : 0.7)
                    // Primary character
                    Text(label)
                        .font(.system(size: isShiftActive ? 12 : 16, weight: .bold))
                        .foregroundColor(isShiftActive ? .secondary : .white)
                        .opacity(isShiftActive ? 0.7 : 1.0)
                } else {
                    Text(label)
                        .font(.system(size: fontSize(for: label), weight: .bold))
                        .foregroundColor(isSpecial ? .accentColor : .white)
                        .opacity(isSpecial && !isHovered ? 0.9 : 1.0)
                }
            }
            .frame(width: actualWidth, height: actualHeight)
            .background(GlassKeyBackground(isHovered: isHovered, isPressed: isPressed, isSpecial: isSpecial, specialColor: .orange))
            .cornerRadius(8)
            .scaleEffect(isPressed ? 0.95 : (isHovered ? 1.05 : 1.0))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredKey = hovering ? keyCode : nil
            if hovering {
                keyboardManager.setMouseHoveredKey(keyCode)
            }
        }
    }

    // MARK: - Modifier Key

    @ViewBuilder
    private func modifierKey(label: String, width: CGFloat, modifier: WritableKeyPath<ModifierFlags, Bool>, keyboardRow: Int? = nil, column: Int? = nil) -> some View {
        let isActive = activeModifiers[keyPath: modifier]
        let modKeyCode = modifierKeyCode(for: modifier)
        // Only use mouse hover - navigation highlight is handled by overlay
        let isHovered = hoveredKey == modKeyCode && !keyboardManager.navigationModeActive

        Button {
            // Exit navigation mode when mouse clicks
            keyboardManager.exitNavigationMode()
            activeModifiers[keyPath: modifier].toggle()
        } label: {
            Text(label)
                .font(.system(size: fontSize(for: label), weight: .bold))
                .frame(width: width, height: keyHeight)
                .background(GlassKeyBackground(isHovered: isHovered, isPressed: isActive, isSpecial: true, specialColor: .orange))
                .foregroundColor(isActive ? .white : (isHovered ? .white : .accentColor))
                .cornerRadius(8)
                .scaleEffect(isActive ? 0.95 : (isHovered ? 1.05 : 1.0))
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredKey = hovering ? modifierKeyCode(for: modifier) : nil
            if hovering {
                if let row = keyboardRow, let col = column {
                    keyboardManager.setMouseHoveredKeyPosition(row: row, column: col)
                } else {
                    keyboardManager.setMouseHoveredKey(modKeyCode)
                }
            }
        }
    }

    private func modifierKeyCode(for modifier: WritableKeyPath<ModifierFlags, Bool>) -> CGKeyCode {
        switch modifier {
        case \.command: return CGKeyCode(kVK_Command)
        case \.option: return CGKeyCode(kVK_Option)
        case \.shift: return CGKeyCode(kVK_Shift)
        case \.control: return CGKeyCode(kVK_Control)
        default: return 0
        }
    }

    // MARK: - Caps Lock Key

    @ViewBuilder
    private func capsLockKey(width: CGFloat) -> some View {
        let keyCode = CGKeyCode(kVK_CapsLock)
        // Only use mouse hover - navigation highlight is handled by overlay
        let isHovered = hoveredKey == keyCode && !keyboardManager.navigationModeActive

        Button {
            // Exit navigation mode when mouse clicks
            keyboardManager.exitNavigationMode()
            isCapsLockActive.toggle()
        } label: {
            HStack(spacing: 4) {
                Text("Caps")
                if isCapsLockActive {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                        .shadow(color: .green, radius: 4)
                }
            }
            .font(.system(size: 14, weight: .bold))
            .frame(width: width, height: keyHeight)
            .background(GlassKeyBackground(isHovered: isHovered, isPressed: isCapsLockActive, isSpecial: true, specialColor: .orange))
            .foregroundColor(isCapsLockActive ? .white : (isHovered ? .white : .accentColor))
            .cornerRadius(8)
            .scaleEffect(isCapsLockActive ? 0.95 : (isHovered ? 1.05 : 1.0))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredKey = hovering ? keyCode : nil
            if hovering {
                keyboardManager.setMouseHoveredKey(keyCode)
            }
        }
    }

    // MARK: - Helpers

    private func fontSize(for label: String) -> CGFloat {
        if label.count > 4 { return 12 }
        if label.count > 2 { return 13 }
        return 16
    }
}

// MARK: - New Glass Aesthetic Components

/// Custom background view for the GTA-style glass keys
struct GlassKeyBackground: View {
    var isHovered: Bool
    var isPressed: Bool
    var isSpecial: Bool = false
    var specialColor: Color? = nil
    var cornerRadius: CGFloat = 8

    var body: some View {
        ZStack {
            // Base layer: Dark, semi-transparent fill
            if isPressed {
                (specialColor ?? Color.accentColor)
                    .opacity(0.8)
                    .shadow(color: (specialColor ?? Color.accentColor).opacity(0.6), radius: 10)
            } else {
                Color.black.opacity(0.5)
            }

            // Highlight border (glows on hover)
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(borderColor, lineWidth: isHovered || isPressed ? 1.5 : 0.5)
                .shadow(color: borderColor.opacity(isHovered ? 0.8 : 0.0), radius: isHovered ? 8 : 0)
        }
    }

    private var borderColor: Color {
        if isPressed {
            return .white.opacity(0.9)
        }
        if isHovered {
            return (specialColor ?? Color.accentColor).opacity(0.8)
        }
        return Color.white.opacity(0.15)
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Array Chunking Extension

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

#Preview {
    OnScreenKeyboardView { keyCode, modifiers in
        print("Key pressed: \(keyCode), modifiers: \(modifiers)")
    }
    .frame(width: 1100, height: 700)
    .background(Color.gray)
}
