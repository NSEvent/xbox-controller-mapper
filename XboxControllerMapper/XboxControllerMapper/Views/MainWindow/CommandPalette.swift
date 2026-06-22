import SwiftUI
import Combine

// MARK: - Destination model

/// A single jump-target in the ⌘K command palette. Plain value type so the
/// matching logic (`CommandPaletteFilter`) stays pure and unit-testable without
/// any SwiftUI / app-state dependencies.
struct CommandPaletteDestination: Identifiable, Equatable {
    /// What selecting this row does. Resolved by the host (`ContentView`).
    enum Target: Equatable {
        /// Switch the main window to a section tab (`MainWindowSection.rawValue`).
        case section(Int)
        /// Jump to the Buttons tab and open the mapping editor for this button.
        case button(ControllerButton)
        /// Open the Settings sheet.
        case settings
    }

    let id: String
    let title: String
    /// Secondary line — e.g. the current binding ("⌘ C") or the nav group.
    let subtitle: String?
    /// Trailing chip text grouping the row ("Map", "Automate", "Button"…).
    let groupLabel: String
    let systemImage: String
    /// Extra search terms not shown in the title (synonyms, raw button name,
    /// the bound shortcut) so typing "copy" can find a button bound to ⌘C.
    let keywords: [String]
    let target: Target

    /// Face / d-pad / bumper / trigger / stick / menu buttons present on
    /// essentially every controller — always offered even when unmapped so the
    /// palette can take you straight to binding them.
    static let coreButtons: [ControllerButton] = [
        .a, .b, .x, .y,
        .leftBumper, .rightBumper, .leftTrigger, .rightTrigger,
        .dpadUp, .dpadDown, .dpadLeft, .dpadRight,
        .leftThumbstick, .rightThumbstick,
        .menu, .view
    ]
}

struct CommandPaletteDestinationProvider {
	static func destinations(
		visibleTabs: [CustomTabItem],
		mappings: [ControllerButton: KeyMapping],
		descriptor: ControllerVisualDescriptor
	) -> [CommandPaletteDestination] {
		var destinations: [CommandPaletteDestination] = []

		for tab in visibleTabs {
			guard let section = MainWindowSection(rawValue: tab.tag) else { continue }
			destinations.append(CommandPaletteDestination(
				id: "section-\(tab.tag)",
				title: tab.label,
				subtitle: section.navGroup.rawValue,
				groupLabel: section.navGroup.rawValue,
				systemImage: tab.systemImage,
				keywords: section.searchKeywords,
				target: .section(tab.tag)
			))
		}

		var seenButtons = Set<ControllerButton>()
		func addButton(_ button: ControllerButton) {
			guard !seenButtons.contains(button) else { return }
			seenButtons.insert(button)
			let binding = mappings[button]?.displayString
			destinations.append(CommandPaletteDestination(
				id: "button-\(button.rawValue)",
				title: button.displayName(
					forDualSense: descriptor.isPlayStation,
					forNintendo: descriptor.isNintendo,
					forAppleTVRemote: descriptor.isAppleTVRemote,
					forEightBitDo: descriptor.eightBitDoModel != nil
				),
				subtitle: binding ?? "Not mapped",
				groupLabel: "Button",
				systemImage: "gamecontroller",
				keywords: [button.rawValue, binding].compactMap { $0 },
				target: .button(button)
			))
		}

		for button in ControllerButton.allCases where mappings[button] != nil { addButton(button) }
		for button in CommandPaletteDestination.coreButtons { addButton(button) }

		destinations.append(CommandPaletteDestination(
			id: "settings",
			title: "Settings",
			subtitle: "Preferences, license, permissions",
			groupLabel: "App",
			systemImage: "gearshape",
			keywords: ["preferences", "license", "permissions", "options"],
			target: .settings
		))

		return destinations
	}
}

// MARK: - Pure matching/ranking (unit-tested)

/// Ranking for the palette. Pure and deterministic — no SwiftUI, no globals — so
/// it can be exercised directly in tests. Lower score = better match.
enum CommandPaletteFilter {
    /// Filtered + ranked results for `query`. An empty/whitespace query returns
    /// every destination in its original order (the curated default list).
    static func filter(_ items: [CommandPaletteDestination], query: String) -> [CommandPaletteDestination] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return items }

        return items.enumerated()
            .compactMap { index, item -> (item: CommandPaletteDestination, score: Int, index: Int)? in
                guard let score = score(for: item, query: q) else { return nil }
                return (item, score, index)
            }
            // Rank by score, then keep the original order as a stable tiebreak.
            .sorted { lhs, rhs in
                lhs.score != rhs.score ? lhs.score < rhs.score : lhs.index < rhs.index
            }
            .map(\.item)
    }

    /// Best (lowest) score across an item's searchable fields, or `nil` if none
    /// match. `query` must already be lowercased/trimmed.
    static func score(for item: CommandPaletteDestination, query: String) -> Int? {
        // (text, fieldWeight) — title matches outrank keyword/subtitle matches.
        var fields: [(String, Int)] = [(item.title.lowercased(), 0)]
        fields.append(contentsOf: item.keywords.map { ($0.lowercased(), 4) })
        fields.append((item.groupLabel.lowercased(), 6))
        if let subtitle = item.subtitle { fields.append((subtitle.lowercased(), 6)) }

        var best: Int?
        for (text, weight) in fields {
            guard let match = matchScore(text, query) else { continue }
            let total = match + weight
            if best == nil || total < best! { best = total }
        }
        return best
    }

    /// Score a single field against the query (both lowercased). Tiers:
    /// exact (0) < prefix (1) < substring (3) < subsequence/fuzzy (8).
    static func matchScore(_ text: String, _ query: String) -> Int? {
        if text == query { return 0 }
        if text.hasPrefix(query) { return 1 }
        if text.contains(query) { return 3 }
        if isSubsequence(query, of: text) { return 8 }
        return nil
    }

    /// True if `needle`'s characters appear in `haystack` in order (gaps OK).
    static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        guard !needle.isEmpty else { return true }
        var iterator = haystack.makeIterator()
        var current = iterator.next()
        for target in needle {
            while let c = current, c != target { current = iterator.next() }
            guard current != nil else { return false }
            current = iterator.next()
        }
        return true
    }
}

// MARK: - Palette view

/// Spotlight-style jump bar. Presented as an isolated sheet from `ContentView`;
/// `onSelect` hands the chosen destination back to the host to perform the
/// actual navigation.
struct CommandPaletteView: View {
    let onSelect: (CommandPaletteDestination) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: CommandPaletteViewModel
    @FocusState private var searchFocused: Bool

    init(
        destinations: [CommandPaletteDestination],
        onSelect: @escaping (CommandPaletteDestination) -> Void
    ) {
        self.onSelect = onSelect
        _model = StateObject(wrappedValue: CommandPaletteViewModel(destinations: destinations))
    }

    private var results: [CommandPaletteDestination] { model.results }
    private var selectedIndex: Int { model.selectedIndex }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider().opacity(0.5)
            resultsList
            footer
        }
        .frame(width: 540, height: 460)
        .background(.regularMaterial)
        .onAppear {
            searchFocused = true
            // A focused TextField eats the arrow keys before SwiftUI's
            // `.onKeyPress` can see them, so drive ↑/↓/return/esc from a
            // window-local key monitor instead (same pattern ContentView uses
            // for Home/End/PageUp/PageDown).
            model.startKeyMonitor(
                onActivate: { onSelect($0) },
                onCancel: { dismiss() }
            )
        }
        .onDisappear { model.stopKeyMonitor() }
        .onChange(of: model.query) { _, _ in model.resetSelection() }
    }

    // MARK: Subviews

    private var searchField: some View {
        HStack(spacing: 11) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Jump to a section, button, or shortcut…", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($searchFocused)
                .onSubmit { activateSelection() }
            Text("esc")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(.quaternary))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    if results.isEmpty {
                        Text("No matches")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 36)
                    } else {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, destination in
                            row(destination, index: index)
                                .id(index)
                        }
                    }
                }
                .padding(8)
            }
            .onChange(of: selectedIndex) { _, newValue in
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(newValue, anchor: .center) }
            }
        }
    }

    private func row(_ destination: CommandPaletteDestination, index: Int) -> some View {
        let isSelected = index == selectedIndex
        return HStack(spacing: 12) {
            Image(systemName: destination.systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : .secondary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.85) : Color.white.opacity(0.06))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(destination.title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.primary)
                if let subtitle = destination.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(destination.groupLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.07)))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect(destination); dismiss() }
        .onHover { hovering in if hovering { model.selectedIndex = index } }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            hint("return", "Open")
            hint("↑↓", "Navigate")
            Spacer()
            Text("\(results.count) result\(results.count == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.12))
        .overlay(alignment: .top) { Divider().opacity(0.5) }
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Selection

    /// Fallback path for `onSubmit` when the key monitor isn't active.
    private func activateSelection() {
        if let destination = model.highlighted() { onSelect(destination) }
        dismiss()
    }
}

// MARK: - Palette view model

/// Owns the palette's mutable state (query + highlighted row) and a window-local
/// key monitor. Lives as a class so the monitor closure can mutate selection and
/// SwiftUI still observes the change — a captured `View` struct couldn't.
final class CommandPaletteViewModel: ObservableObject {
    @Published var query = ""
    @Published var selectedIndex = 0

    private let destinations: [CommandPaletteDestination]
    private var keyMonitor: Any?

    init(destinations: [CommandPaletteDestination]) {
        self.destinations = destinations
    }

    var results: [CommandPaletteDestination] {
        CommandPaletteFilter.filter(destinations, query: query)
    }

    func resetSelection() { selectedIndex = 0 }

    func move(_ delta: Int) {
        let count = results.count
        guard count > 0 else { return }
        selectedIndex = ((selectedIndex + delta) % count + count) % count
    }

    /// The currently highlighted destination, if the selection is in range.
    func highlighted() -> CommandPaletteDestination? {
        let current = results
        return current.indices.contains(selectedIndex) ? current[selectedIndex] : nil
    }

    /// Installs a local key monitor so ↑/↓ navigate, return opens, and esc
    /// cancels — even while the search field holds focus. Fires on the main
    /// thread (AppKit local monitors do), so mutating `@Published` here is safe.
    func startKeyMonitor(
        onActivate: @escaping (CommandPaletteDestination) -> Void,
        onCancel: @escaping () -> Void
    ) {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 125: self.move(1); return nil          // down arrow
            case 126: self.move(-1); return nil         // up arrow
            case 36, 76:                                // return / keypad enter
                if let destination = self.highlighted() { onActivate(destination) }
                onCancel()
                return nil
            case 53:                                    // escape
                onCancel()
                return nil
            default:
                return event
            }
        }
    }

    func stopKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}
