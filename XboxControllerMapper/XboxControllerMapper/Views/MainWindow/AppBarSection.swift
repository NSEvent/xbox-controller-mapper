import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// App bar management section for the on-screen keyboard settings.
struct AppBarSection: View {
    @EnvironmentObject var profileManager: ProfileManager

    // Sheet presentation state
    @State private var showingAppPicker = false
    @State private var appPickerSearchText = ""
    @State private var appPickerSelectedIndex = 0

    // Editing state
    @State private var editingAppBarItem: AppBarItem?

    // Drag-to-reorder state
    @State private var draggedAppBarItem: AppBarItem?

    // Cached installed apps (loaded once on appear)
    @State private var cachedInstalledApps: [AppInfo] = []

    private var appBarItems: [AppBarItem] {
        profileManager.activeProfile?.onScreenKeyboardSettings.appBarItems ?? []
    }

    private var filteredInstalledApps: [AppInfo] {
        cachedInstalledApps.filter { app in
            appPickerSearchText.isEmpty ||
            app.name.localizedCaseInsensitiveContains(appPickerSearchText)
        }
    }

    var body: some View {
        Section {
            // Add app button
            Button {
                showingAppPicker = true
            } label: {
                Label("Add App", systemImage: "plus.app")
            }
            .sheet(isPresented: $showingAppPicker) {
                appPickerSheet
            }
            .sheet(item: $editingAppBarItem) { item in
                EditAppBarItemSheet(item: item) { updatedItem in
                    profileManager.updateAppBarItem(updatedItem)
                }
            }

            // List of app bar items
            if appBarItems.isEmpty {
                Text("No apps added yet")
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                VStack(spacing: 4) {
                    ForEach(appBarItems) { item in
                        appBarListRow(item)
                            .onDrag {
                                draggedAppBarItem = item
                                return NSItemProvider(object: item.id.uuidString as NSString)
                            }
                            .onDrop(of: [.text], delegate: AppBarItemDropDelegate(
                                item: item,
                                items: appBarItems,
                                draggedItem: $draggedAppBarItem,
                                moveItems: { from, to in
                                    profileManager.moveAppBarItems(from: from, to: to)
                                }
                            ))
                    }
                }
            }
        } header: {
            Text("App Bar")
        } footer: {
            Text("Add apps for quick switching from the on-screen keyboard.")
        }
    }

    // MARK: - Row View

    @ViewBuilder
    private func appBarListRow(_ item: AppBarItem) -> some View {
        AppBarItemRowView(
            item: item,
            onEdit: {
                editingAppBarItem = item
            },
            onDelete: {
                profileManager.removeAppBarItem(item)
            }
        )
    }

    // MARK: - App Selection

    private func toggleAppSelection(at index: Int) {
        let apps = filteredInstalledApps
        guard index >= 0 && index < apps.count else { return }
        let app = apps[index]
        let alreadyAdded = appBarItems.contains { $0.bundleIdentifier == app.bundleIdentifier }

        if alreadyAdded {
            if let item = appBarItems.first(where: { $0.bundleIdentifier == app.bundleIdentifier }) {
                profileManager.removeAppBarItem(item)
            }
        } else {
            let item = AppBarItem(
                bundleIdentifier: app.bundleIdentifier,
                displayName: app.name
            )
            profileManager.addAppBarItem(item)
        }
    }

    private func loadInstalledApps() {
        guard cachedInstalledApps.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let apps = AppMonitor().installedApplications
            DispatchQueue.main.async {
                cachedInstalledApps = apps
            }
        }
    }

    // MARK: - App Picker Sheet

    private var appPickerSheet: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add App")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    showingAppPicker = false
                }
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding()

            Divider()

            // Search field with keyboard navigation
            NavigableSearchField(
                text: $appPickerSearchText,
                placeholder: "Search apps...",
                itemCount: filteredInstalledApps.count,
                selectedIndex: $appPickerSelectedIndex,
                onSelect: {
                    toggleAppSelection(at: appPickerSelectedIndex)
                }
            )
            .padding()

            Divider()

            // App list with scroll-to-top
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(filteredInstalledApps.enumerated()), id: \.element.id) { index, app in
                        let alreadyAdded = appBarItems.contains { $0.bundleIdentifier == app.bundleIdentifier }
                        let isSelected = index == appPickerSelectedIndex

                        Button {
                            toggleAppSelection(at: index)
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

                                if alreadyAdded {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(isSelected ? .white : .green)
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
                .onChange(of: appPickerSearchText) { _, _ in
                    appPickerSelectedIndex = 0
                    proxy.scrollTo(0, anchor: .top)
                }
                .onChange(of: appPickerSelectedIndex) { _, newIndex in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 400, height: 500)
        .onAppear {
            loadInstalledApps()
        }
        .onDisappear {
            appPickerSearchText = ""
            appPickerSelectedIndex = 0
        }
    }
}
