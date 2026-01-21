import SwiftUI
import AppKit
import Carbon.HIToolbox

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

    // Key size constants - increase for larger keyboard
    private let keyWidth: CGFloat = 68    // 54 * 1.25
    private let keyHeight: CGFloat = 60   // 48 * 1.25
    private let keySpacing: CGFloat = 6

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

    var body: some View {
        VStack(spacing: 10) {
            // Website links section (above app bar)
            if !websiteLinks.isEmpty {
                websiteLinksSection
                Divider()
                    .padding(.horizontal, 8)
            }

            // App bar section (if any apps configured)
            if !appBarItems.isEmpty {
                appBarSection
                Divider()
                    .padding(.horizontal, 8)
            }

            // Quick text sections (if any)
            if !quickTexts.isEmpty {
                quickTextSection
                Divider()
                    .padding(.horizontal, 8)
            }

            // Media controls row (Playback, Volume, Brightness)
            mediaControlsRow

            // Extended function key row (F13-F20) - shown above F1-F12 when enabled
            if showExtendedFunctionKeys {
                extendedFunctionKeyRow
            }

            // Function key row (Esc + F1-F12)
            functionKeyRow

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
        }
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
    }

    // MARK: - App Bar Section

    // Fixed width for app bar to ensure proper layout calculation
    // Matches keyboard width, fits ~12 icons per row with 64px icons + padding
    private let appBarWidth: CGFloat = 1025
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
        let isHovered = hoveredAppBarItemId == item.id
        let isPressed = pressedAppBarItemId == item.id
        let iconSize: CGFloat = 64

        return Button {
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
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize, height: iconSize)

                Text(item.displayName)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: iconSize + 16)
            }
            .padding(8)
            .background(appBarBackground(isHovered: isHovered, isPressed: isPressed))
            .foregroundColor(isPressed ? .white : .primary)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(appBarBorderColor(isHovered: isHovered, isPressed: isPressed), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredAppBarItemId = hovering ? item.id : nil
        }
    }

    private func appIcon(for bundleIdentifier: String) -> Image {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
           let icon = NSWorkspace.shared.icon(forFile: url.path) as NSImage? {
            return Image(nsImage: icon)
        }
        // Fallback icon for apps not installed
        return Image(systemName: "app.fill")
    }

    private func appBarBackground(isHovered: Bool, isPressed: Bool) -> Color {
        if isPressed {
            return .accentColor
        } else if isHovered {
            return Color.accentColor.opacity(0.3)
        } else {
            return Color(nsColor: .controlBackgroundColor)
        }
    }

    private func appBarBorderColor(isHovered: Bool, isPressed: Bool) -> Color {
        if isPressed {
            return .accentColor
        } else if isHovered {
            return Color.accentColor.opacity(0.5)
        } else {
            return .gray.opacity(0.3)
        }
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
        let isHovered = hoveredWebsiteLinkId == link.id
        let isPressed = pressedWebsiteLinkId == link.id
        let iconSize: CGFloat = 64

        return Button {
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

                Text(link.displayName)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: iconSize + 16)
            }
            .padding(8)
            .background(appBarBackground(isHovered: isHovered, isPressed: isPressed))
            .foregroundColor(isPressed ? .white : .primary)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(appBarBorderColor(isHovered: isHovered, isPressed: isPressed), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredWebsiteLinkId = hovering ? link.id : nil
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
            // Fallback globe icon
            Image(systemName: "globe")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Quick Text Section

    private var quickTextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Terminal Commands
            if !terminalCommands.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "terminal")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Commands")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                quickTextButtonRow(terminalCommands)
            }

            // Text Snippets
            if !textSnippets.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "text.quote")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Text")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                quickTextButtonRow(textSnippets)
            }
        }
    }

    private func quickTextButtonRow(_ items: [QuickText]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items) { item in
                    quickTextButton(item)
                }
            }
        }
    }

    private func quickTextButton(_ quickText: QuickText) -> some View {
        let isHovered = hoveredQuickTextId == quickText.id
        let isPressed = pressedQuickTextId == quickText.id

        return Button {
            pressedQuickTextId = quickText.id
            onQuickText?(quickText)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if pressedQuickTextId == quickText.id {
                    pressedQuickTextId = nil
                }
            }
        } label: {
            HStack(spacing: 4) {
                if quickText.isTerminalCommand {
                    Image(systemName: "terminal")
                        .font(.system(size: 10))
                }
                Text(quickText.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
            .frame(maxWidth: 500)
            .background(quickTextBackground(isHovered: isHovered, isPressed: isPressed, isTerminalCommand: quickText.isTerminalCommand))
            .foregroundColor(isPressed ? .white : .primary)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(quickTextBorderColor(isHovered: isHovered, isPressed: isPressed, isTerminalCommand: quickText.isTerminalCommand), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredQuickTextId = hovering ? quickText.id : nil
        }
    }

    private func quickTextBackground(isHovered: Bool, isPressed: Bool, isTerminalCommand: Bool) -> Color {
        if isPressed {
            return isTerminalCommand ? Color.orange : .accentColor
        } else if isHovered {
            return isTerminalCommand ? Color.orange.opacity(0.3) : Color.accentColor.opacity(0.3)
        } else {
            return Color(nsColor: .controlBackgroundColor)
        }
    }

    private func quickTextBorderColor(isHovered: Bool, isPressed: Bool, isTerminalCommand: Bool) -> Color {
        if isPressed {
            return isTerminalCommand ? .orange : .accentColor
        } else if isHovered {
            return isTerminalCommand ? Color.orange.opacity(0.5) : Color.accentColor.opacity(0.5)
        } else {
            return .gray.opacity(0.3)
        }
    }

    // MARK: - Function Keys (F1-F12 and F13-F20)

    private let f1to12Codes: [Int] = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
        kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12
    ]

    private let f13to20Codes: [Int] = [
        kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20
    ]

    // MARK: - Media Controls Row

    private var mediaControlsRow: some View {
        HStack(spacing: keySpacing * 4) {
            // Playback controls
            HStack(spacing: 4) {
                Text("Playback:")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                HStack(spacing: keySpacing) {
                    mediaKey(KeyCodeMapping.mediaPrevious, label: "Previous", symbol: "backward.end.fill")
                    mediaKey(KeyCodeMapping.mediaRewind, label: "Rewind", symbol: "backward.fill")
                    mediaKey(KeyCodeMapping.mediaPlayPause, label: "Play/Pause", symbol: "playpause.fill")
                    mediaKey(KeyCodeMapping.mediaFastForward, label: "Fast", symbol: "forward.fill")
                    mediaKey(KeyCodeMapping.mediaNext, label: "Next", symbol: "forward.end.fill")
                }
            }

            // Volume controls (Mute, Down, Up)
            HStack(spacing: 4) {
                Text("Sound:")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                HStack(spacing: keySpacing) {
                    mediaKey(KeyCodeMapping.volumeMute, label: "Mute", symbol: "speaker.slash.fill")
                    mediaKey(KeyCodeMapping.volumeDown, label: "Down", symbol: "speaker.wave.1.fill")
                    mediaKey(KeyCodeMapping.volumeUp, label: "Up", symbol: "speaker.wave.3.fill")
                }
            }

            // Brightness controls (Down, Up)
            HStack(spacing: 4) {
                Text("Brightness:")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                HStack(spacing: keySpacing) {
                    mediaKey(KeyCodeMapping.brightnessDown, label: "Down", symbol: "sun.min.fill")
                    mediaKey(KeyCodeMapping.brightnessUp, label: "Up", symbol: "sun.max.fill")
                }
            }
        }
    }

    private func mediaKey(_ keyCode: CGKeyCode, label: String, symbol: String) -> some View {
        let isHovered = hoveredKey == keyCode
        let isPressed = pressedKey == keyCode

        return Button {
            pressedKey = keyCode
            onKeyPress(keyCode, activeModifiers)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if pressedKey == keyCode {
                    pressedKey = nil
                }
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 14))
                Text(label)
                    .font(.system(size: 8))
            }
            .frame(width: 60, height: 36)
            .background(keyBackground(isHovered: isHovered, isPressed: isPressed))
            .foregroundColor(isPressed ? .white : .primary)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(keyBorderColor(isHovered: isHovered, isPressed: isPressed), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredKey = hovering ? keyCode : nil
        }
    }

    private var extendedFunctionKeyRow: some View {
        HStack(spacing: keySpacing) {
            // Empty space to align with Esc key
            Spacer().frame(width: 85)

            Spacer().frame(width: 30)

            ForEach(0..<4, id: \.self) { i in
                clickableKey(CGKeyCode(f13to20Codes[i]), label: "F\(i + 13)", width: 75)
            }

            Spacer().frame(width: 19)

            ForEach(4..<8, id: \.self) { i in
                clickableKey(CGKeyCode(f13to20Codes[i]), label: "F\(i + 13)", width: 75)
            }

            Spacer().frame(width: 19)

            // Empty space for alignment (F1-F12 has 4 keys in last group, F13-F20 only has 8 total)
            ForEach(0..<4, id: \.self) { _ in
                Color.clear.frame(width: 75, height: keyHeight)
            }
        }
    }

    private var functionKeyRow: some View {
        HStack(spacing: keySpacing) {
            clickableKey(CGKeyCode(kVK_Escape), label: "Esc", width: 85)

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

    private var numberRow: some View {
        HStack(spacing: keySpacing) {
            clickableKey(CGKeyCode(kVK_ANSI_Grave), label: "`")

            ForEach(0..<10, id: \.self) { i in
                let keyCode = CGKeyCode(i == 9 ? kVK_ANSI_0 : kVK_ANSI_1 + i)
                let displayNum = i == 9 ? "0" : "\(i + 1)"
                clickableKey(keyCode, label: displayNum)
            }

            clickableKey(CGKeyCode(kVK_ANSI_Minus), label: "-")
            clickableKey(CGKeyCode(kVK_ANSI_Equal), label: "=")
            clickableKey(CGKeyCode(kVK_Delete), label: "⌫", width: 107)
        }
    }

    // MARK: - QWERTY Row

    private var qwertyRow: some View {
        HStack(spacing: keySpacing) {
            clickableKey(CGKeyCode(kVK_Tab), label: "Tab", width: 95)

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
            clickableKey(CGKeyCode(kVK_Return), label: "Return", width: 125)
        }
    }

    // MARK: - ZXCV Row

    private var zxcvRow: some View {
        HStack(spacing: keySpacing) {
            modifierKey(label: "⇧ Shift", width: 140, modifier: \.shift)

            let zxcvKeys = ["Z", "X", "C", "V", "B", "N", "M"]
            let zxcvCodes: [Int] = [kVK_ANSI_Z, kVK_ANSI_X, kVK_ANSI_C, kVK_ANSI_V, kVK_ANSI_B, kVK_ANSI_N, kVK_ANSI_M]

            ForEach(0..<zxcvKeys.count, id: \.self) { i in
                clickableKey(CGKeyCode(zxcvCodes[i]), label: zxcvKeys[i])
            }

            clickableKey(CGKeyCode(kVK_ANSI_Comma), label: ",")
            clickableKey(CGKeyCode(kVK_ANSI_Period), label: ".")
            clickableKey(CGKeyCode(kVK_ANSI_Slash), label: "/")
            modifierKey(label: "⇧ Shift", width: 140, modifier: \.shift)
        }
    }

    // MARK: - Bottom Row

    private var bottomRow: some View {
        HStack(spacing: keySpacing) {
            modifierKey(label: "⌃", width: 78, modifier: \.control)
            modifierKey(label: "⌥", width: 78, modifier: \.option)
            modifierKey(label: "⌘", width: 93, modifier: \.command)

            clickableKey(CGKeyCode(kVK_Space), label: "Space", width: 369)

            modifierKey(label: "⌘", width: 93, modifier: \.command)
            modifierKey(label: "⌥", width: 78, modifier: \.option)

            // Arrow keys cluster
            VStack(spacing: 4) {
                clickableKey(CGKeyCode(kVK_UpArrow), label: "↑", width: 60, height: 28)
                HStack(spacing: 4) {
                    clickableKey(CGKeyCode(kVK_LeftArrow), label: "←", width: 60, height: 28)
                    clickableKey(CGKeyCode(kVK_DownArrow), label: "↓", width: 60, height: 28)
                    clickableKey(CGKeyCode(kVK_RightArrow), label: "→", width: 60, height: 28)
                }
            }
        }
    }

    // MARK: - Navigation Keys

    private var navigationKeyColumn: some View {
        VStack(spacing: keySpacing) {
            clickableKey(CGKeyCode(kVK_ForwardDelete), label: "Del")
            clickableKey(CGKeyCode(kVK_Home), label: "Home")
            clickableKey(CGKeyCode(kVK_End), label: "End")
            clickableKey(CGKeyCode(kVK_PageUp), label: "PgUp")
            clickableKey(CGKeyCode(kVK_PageDown), label: "PgDn")
        }
    }

    // MARK: - Key Button

    @ViewBuilder
    private func clickableKey(_ keyCode: CGKeyCode, label: String, width: CGFloat? = nil, height: CGFloat? = nil) -> some View {
        let actualWidth = width ?? keyWidth
        let actualHeight = height ?? keyHeight
        let isHovered = hoveredKey == keyCode
        let isPressed = pressedKey == keyCode
        let secondary = secondaryKeys[label]
        let isShiftActive = activeModifiers.shift

        // Check if this is a single letter key (A-Z)
        let isSingleLetter = label.count == 1 && label.first?.isLetter == true

        Button {
            pressedKey = keyCode
            // When caps lock is active and this is a letter key, add shift to get uppercase
            var modifiersToSend = activeModifiers
            if isCapsLockActive && isSingleLetter {
                modifiersToSend.shift = true
            }
            onKeyPress(keyCode, modifiersToSend)
            // Brief visual feedback then clear
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if pressedKey == keyCode {
                    pressedKey = nil
                }
            }
        } label: {
            VStack(spacing: 1) {
                if let secondary = secondary {
                    // Secondary character (smaller when shift not active, larger when active)
                    Text(secondary)
                        .font(.system(size: isShiftActive ? 14 : 10, weight: .medium))
                        .foregroundColor(isPressed ? .white : (isShiftActive ? .primary : .secondary))
                    // Primary character (larger when shift not active, smaller when active)
                    Text(label)
                        .font(.system(size: isShiftActive ? 12 : 16, weight: .medium))
                        .foregroundColor(isPressed ? .white : (isShiftActive ? .secondary : .primary))
                } else {
                    // No secondary - just show the label (always uppercase for letters)
                    Text(label)
                        .font(.system(size: fontSize(for: label), weight: .medium))
                        .foregroundColor(isPressed ? .white : .primary)
                }
            }
            .frame(width: actualWidth, height: actualHeight)
            .background(keyBackground(isHovered: isHovered, isPressed: isPressed))
            .cornerRadius(5)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(keyBorderColor(isHovered: isHovered, isPressed: isPressed), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredKey = hovering ? keyCode : nil
        }
    }

    // MARK: - Modifier Key

    @ViewBuilder
    private func modifierKey(label: String, width: CGFloat, modifier: WritableKeyPath<ModifierFlags, Bool>) -> some View {
        let isActive = activeModifiers[keyPath: modifier]
        let isHovered = hoveredKey == modifierKeyCode(for: modifier)

        Button {
            activeModifiers[keyPath: modifier].toggle()
        } label: {
            Text(label)
                .font(.system(size: fontSize(for: label), weight: .medium))
                .frame(width: width, height: keyHeight)
                .background(isActive ? Color.accentColor : (isHovered ? Color.accentColor.opacity(0.3) : Color(nsColor: .controlBackgroundColor)))
                .foregroundColor(isActive ? .white : .primary)
                .cornerRadius(5)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isActive ? Color.accentColor : (isHovered ? Color.accentColor.opacity(0.5) : Color.gray.opacity(0.3)), lineWidth: isActive ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredKey = hovering ? modifierKeyCode(for: modifier) : nil
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
        let isHovered = hoveredKey == keyCode

        Button {
            // Only toggle our internal state - don't send caps lock to the system
            // We handle uppercase by adding shift to letter keys when caps lock is active
            isCapsLockActive.toggle()
        } label: {
            Text("Caps")
                .font(.system(size: 14, weight: .medium))
                .frame(width: width, height: keyHeight)
                .background(isCapsLockActive ? Color.accentColor : (isHovered ? Color.accentColor.opacity(0.3) : Color(nsColor: .controlBackgroundColor)))
                .foregroundColor(isCapsLockActive ? .white : .primary)
                .cornerRadius(5)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isCapsLockActive ? Color.accentColor : (isHovered ? Color.accentColor.opacity(0.5) : Color.gray.opacity(0.3)), lineWidth: isCapsLockActive ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredKey = hovering ? keyCode : nil
        }
    }

    // MARK: - Helpers

    private func fontSize(for label: String) -> CGFloat {
        if label.count > 4 { return 13 }
        if label.count > 2 { return 14 }
        return 16
    }

    private func keyBackground(isHovered: Bool, isPressed: Bool) -> Color {
        if isPressed {
            return .accentColor
        } else if isHovered {
            return Color.accentColor.opacity(0.3)
        } else {
            return Color(nsColor: .controlBackgroundColor)
        }
    }

    private func keyBorderColor(isHovered: Bool, isPressed: Bool) -> Color {
        if isPressed {
            return .accentColor
        } else if isHovered {
            return .accentColor.opacity(0.5)
        } else {
            return .gray.opacity(0.3)
        }
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
    .frame(width: 812)
}
