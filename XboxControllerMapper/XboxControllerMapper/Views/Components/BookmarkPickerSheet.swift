import SwiftUI

/// A sheet that displays browser bookmarks in a tree/folder view for selection
struct BookmarkPickerSheet: View {
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var bookmarks: [BookmarkItem] = []
    @State private var browserType: BrowserType = .unknown
    @State private var isLoading = true
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Browse Bookmarks")
                        .font(.headline)
                    if browserType != .unknown {
                        Text("From \(browserType.rawValue)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search bookmarks...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Content
            if isLoading {
                Spacer()
                ProgressView("Loading bookmarks...")
                Spacer()
            } else if bookmarks.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "book.closed")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No bookmarks found")
                        .foregroundColor(.secondary)
                    if browserType == .unknown {
                        Text("Could not detect your default browser")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            } else if searchText.isEmpty {
                // Tree view
                List {
                    OutlineGroup(bookmarks, children: \.optionalChildren) { item in
                        BookmarkItemRow(item: item) { url in
                            onSelect(url)
                            dismiss()
                        }
                    }
                }
            } else {
                // Flat filtered list
                let filtered = flattenAndFilter(bookmarks, query: searchText)
                if filtered.isEmpty {
                    Spacer()
                    Text("No matching bookmarks")
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    List(filtered) { item in
                        BookmarkItemRow(item: item) { url in
                            onSelect(url)
                            dismiss()
                        }
                    }
                }
            }
        }
        .frame(width: 450, height: 500)
        .onAppear { loadBookmarks() }
    }

    private func loadBookmarks() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = BookmarkReader.readDefaultBrowserBookmarks()
            DispatchQueue.main.async {
                browserType = result.browser
                bookmarks = result.bookmarks
                isLoading = false
            }
        }
    }

    /// Recursively flatten the tree and filter by search query
    private func flattenAndFilter(_ items: [BookmarkItem], query: String) -> [BookmarkItem] {
        var results: [BookmarkItem] = []
        for item in items {
            if let children = item.children {
                results.append(contentsOf: flattenAndFilter(children, query: query))
            } else if let url = item.url {
                if item.title.localizedCaseInsensitiveContains(query) ||
                   url.localizedCaseInsensitiveContains(query) {
                    results.append(item)
                }
            }
        }
        return results
    }
}

/// A single row in the bookmark list
private struct BookmarkItemRow: View {
    let item: BookmarkItem
    let onSelect: (String) -> Void

    var body: some View {
        if item.isFolder {
            Label(item.title, systemImage: "folder")
                .foregroundColor(.primary)
        } else {
            Button {
                if let url = item.url {
                    onSelect(url)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .foregroundColor(.secondary)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .lineLimit(1)
                            .foregroundColor(.primary)
                        if let url = item.url {
                            Text(url)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}
