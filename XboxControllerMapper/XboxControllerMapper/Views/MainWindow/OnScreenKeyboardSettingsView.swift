import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Settings view for the on-screen keyboard feature.
/// Composes focused sub-components for each settings section.
struct OnScreenKeyboardSettingsView: View {
    @EnvironmentObject var profileManager: ProfileManager

    var body: some View {
        Form {
            // How to show keyboard info + toggle shortcut
            OSKInfoSection()

            // Text snippet management
            TextSnippetsSection()

            // Terminal command management
            TerminalCommandsSection()

            // App bar management
            AppBarSection()

            // Website link management
            WebsiteLinksSection()

            // App switching, command wheel, keyboard layout
            OSKGeneralSettingsSection()

            // Swipe typing settings + custom dictionary
            SwipeTypingSection()
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Quick Text Row View

struct QuickTextRowView<SuggestionsView: View>: View {
    let quickText: QuickText
    let isTerminalCommand: Bool
    let isEditing: Bool
    @Binding var editText: String
    let showEditSuggestions: Bool
    let editSuggestionCount: Int
    @Binding var editSuggestionIndex: Int
    let onSelectSuggestion: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void
    let onStartEdit: () -> Void
    let onDelete: () -> Void
    let onEditTextChange: (String) -> Void
    @ViewBuilder let variableSuggestionsView: () -> SuggestionsView

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Drag handle - not tappable, allows List drag to work
                Image(systemName: "line.3.horizontal")
                    .foregroundColor(.secondary)
                    .frame(width: 20)

                if isEditing {
                    VariableTextField(
                        text: $editText,
                        placeholder: "",
                        showingSuggestions: showEditSuggestions,
                        suggestionCount: editSuggestionCount,
                        selectedSuggestionIndex: $editSuggestionIndex,
                        onSelectSuggestion: onSelectSuggestion,
                        onSubmit: {
                            if !showEditSuggestions {
                                onSave()
                            }
                        }
                    )
                    .onChange(of: editText) { _, newValue in
                        onEditTextChange(newValue)
                    }

                    Button("Save", action: onSave)
                    Button("Cancel", action: onCancel)
                } else {
                    // Tappable content area
                    HStack {
                        Text(quickText.text)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if quickText.containsVariables {
                            Image(systemName: "function")
                                .font(.caption2)
                                .foregroundColor(.blue)
                                .help("Contains variables that will be expanded")
                        }

                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onStartEdit() }

                    Button(action: onStartEdit) {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }

            if isEditing && showEditSuggestions {
                variableSuggestionsView()
                    .padding(.leading, 28)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
        )
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - App Bar Item Row View

struct AppBarItemRowView: View {
    let item: AppBarItem
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack {
            // Drag handle - not tappable, allows drag to work
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)
                .frame(width: 20)

            // Tappable content area
            HStack {
                // App icon
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.bundleIdentifier),
                   let icon = NSWorkspace.shared.icon(forFile: url.path) as NSImage? {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "app.fill")
                        .resizable()
                        .frame(width: 24, height: 24)
                        .foregroundColor(.secondary)
                }

                Text(item.displayName)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture { onEdit() }

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.accentColor.opacity(0.08) : Color.clear)
        )
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Website Link Row View

struct WebsiteLinkRowView: View {
    let link: WebsiteLink
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack {
            // Drag handle - not tappable, allows drag to work
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)
                .frame(width: 20)

            // Tappable content area
            HStack {
                // Favicon
                if let data = link.faviconData,
                   let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .frame(width: 24, height: 24)
                        .cornerRadius(4)
                } else {
                    Image(systemName: "globe")
                        .frame(width: 24, height: 24)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(link.displayName)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(link.domain ?? link.url)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture { onEdit() }

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.accentColor.opacity(0.08) : Color.clear)
        )
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Edit App Bar Item Sheet

struct EditAppBarItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: AppBarItem
    let onSave: (AppBarItem) -> Void

    @State private var displayName: String
    @State private var selectedBundleId: String
    @State private var searchText = ""
    @State private var selectedIndex = 0
    @State private var installedApps: [AppInfo] = []

    init(item: AppBarItem, onSave: @escaping (AppBarItem) -> Void) {
        self.item = item
        self.onSave = onSave
        self._displayName = State(initialValue: item.displayName)
        self._selectedBundleId = State(initialValue: item.bundleIdentifier)
    }

    private var filteredApps: [AppInfo] {
        if searchText.isEmpty {
            return installedApps
        }
        return installedApps.filter { app in
            app.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit App")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Save") { save() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()

            Divider()

            // Display name field
            HStack {
                Text("Display Name:")
                TextField("Display Name", text: $displayName)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal)
            .padding(.top)

            Divider()
                .padding(.top)

            // Search field
            NavigableSearchField(
                text: $searchText,
                placeholder: "Search apps...",
                itemCount: filteredApps.count,
                selectedIndex: $selectedIndex,
                onSelect: {
                    selectApp(at: selectedIndex)
                }
            )
            .padding()

            Divider()

            // App list
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(filteredApps.enumerated()), id: \.element.id) { index, app in
                        let isSelected = index == selectedIndex
                        let isCurrentApp = app.bundleIdentifier == selectedBundleId

                        Button {
                            selectApp(at: index)
                        } label: {
                            HStack(spacing: 12) {
                                if let icon = app.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 32, height: 32)
                                } else {
                                    Image(systemName: "app.fill")
                                        .resizable()
                                        .frame(width: 32, height: 32)
                                }

                                Text(app.name)

                                Spacer()

                                if isCurrentApp {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(isSelected ? .white : .accentColor)
                                }
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(isSelected ? Color.accentColor : Color.clear)
                            .foregroundColor(isSelected ? .white : .primary)
                            .cornerRadius(6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(index)
                    }
                }
                .listStyle(.plain)
                .onChange(of: searchText) { _, _ in
                    selectedIndex = 0
                    proxy.scrollTo(0, anchor: .top)
                }
                .onChange(of: selectedIndex) { _, newIndex in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 450, height: 500)
        .onAppear {
            loadInstalledApps()
        }
    }

    private func loadInstalledApps() {
        DispatchQueue.global(qos: .userInitiated).async {
            let apps = AppMonitor().installedApplications
            DispatchQueue.main.async {
                installedApps = apps
            }
        }
    }

    private func selectApp(at index: Int) {
        guard index >= 0 && index < filteredApps.count else { return }
        let app = filteredApps[index]
        selectedBundleId = app.bundleIdentifier
        // Update display name if it was the original app name
        if displayName == item.displayName {
            displayName = app.name
        }
    }

    private func save() {
        var updatedItem = item
        updatedItem.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedItem.bundleIdentifier = selectedBundleId
        onSave(updatedItem)
        dismiss()
    }
}

// MARK: - Edit Website Link Sheet

struct EditWebsiteLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    let link: WebsiteLink
    let onSave: (WebsiteLink) -> Void

    @State private var displayName: String
    @State private var url: String

    init(link: WebsiteLink, onSave: @escaping (WebsiteLink) -> Void) {
        self.link = link
        self.onSave = onSave
        self._displayName = State(initialValue: link.displayName)
        self._url = State(initialValue: link.url)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Website Link")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Save") { save() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()

            Divider()

            // Content
            Form {
                // Favicon preview
                HStack {
                    if let data = link.faviconData,
                       let nsImage = NSImage(data: data) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .frame(width: 32, height: 32)
                            .cornerRadius(4)
                    } else {
                        Image(systemName: "globe")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .foregroundColor(.secondary)
                    }

                    Text("Favicon will be updated if URL changes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 8)

                // Editable fields
                TextField("Display Name", text: $displayName)
                    .textFieldStyle(.roundedBorder)

                TextField("URL", text: $url)
                    .textFieldStyle(.roundedBorder)
            }
            .formStyle(.grouped)
            .padding()
        }
        .frame(width: 450, height: 280)
    }

    private func save() {
        var updatedLink = link
        updatedLink.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let newURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if newURL != link.url {
            updatedLink.url = newURL
            // Clear favicon if URL changed - it will be re-fetched
            updatedLink.faviconData = nil
        }
        onSave(updatedLink)
        dismiss()
    }
}

// MARK: - Drop Delegates for Reordering

struct AppBarItemDropDelegate: DropDelegate {
    let item: AppBarItem
    let items: [AppBarItem]
    @Binding var draggedItem: AppBarItem?
    let moveItems: (IndexSet, Int) -> Void

    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedItem = draggedItem,
              draggedItem.id != item.id,
              let fromIndex = items.firstIndex(where: { $0.id == draggedItem.id }),
              let toIndex = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            moveItems(IndexSet(integer: fromIndex), toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

struct WebsiteLinkDropDelegate: DropDelegate {
    let item: WebsiteLink
    let items: [WebsiteLink]
    @Binding var draggedItem: WebsiteLink?
    let moveItems: (IndexSet, Int) -> Void

    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedItem = draggedItem,
              draggedItem.id != item.id,
              let fromIndex = items.firstIndex(where: { $0.id == draggedItem.id }),
              let toIndex = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            moveItems(IndexSet(integer: fromIndex), toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

#Preview {
    OnScreenKeyboardSettingsView()
        .environmentObject(ProfileManager())
        .frame(width: 600, height: 500)
}
