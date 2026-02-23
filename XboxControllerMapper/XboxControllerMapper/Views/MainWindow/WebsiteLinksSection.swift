import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Website links management section for the on-screen keyboard settings.
struct WebsiteLinksSection: View {
    @EnvironmentObject var profileManager: ProfileManager

    // Input state
    @State private var newWebsiteURL = ""
    @State private var isFetchingWebsiteMetadata = false
    @State private var websiteURLError: String?

    // Sheet presentation state
    @State private var showingWebsiteBookmarkPicker = false

    // Editing state
    @State private var editingWebsiteLink: WebsiteLink?

    // Drag-to-reorder state
    @State private var draggedWebsiteLink: WebsiteLink?

    private var websiteLinks: [WebsiteLink] {
        profileManager.activeProfile?.onScreenKeyboardSettings.websiteLinks ?? []
    }

    var body: some View {
        Section {
            // Add URL field
            HStack {
                TextField("Enter website URL...", text: $newWebsiteURL)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addWebsiteLink() }

                if isFetchingWebsiteMetadata {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 20)
                } else {
                    Button("Add") { addWebsiteLink() }
                        .disabled(newWebsiteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Button {
                showingWebsiteBookmarkPicker = true
            } label: {
                Label("Browse Bookmarks", systemImage: "book")
            }
            .sheet(isPresented: $showingWebsiteBookmarkPicker) {
                BookmarkPickerSheet { url in
                    newWebsiteURL = url
                    addWebsiteLink()
                }
            }
            .sheet(item: $editingWebsiteLink) { link in
                EditWebsiteLinkSheet(link: link) { updatedLink in
                    profileManager.updateWebsiteLink(updatedLink)
                }
            }

            if let error = websiteURLError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            // List of website links
            if websiteLinks.isEmpty {
                Text("No website links yet")
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                VStack(spacing: 4) {
                    ForEach(websiteLinks) { link in
                        websiteLinkRow(link)
                            .onDrag {
                                draggedWebsiteLink = link
                                return NSItemProvider(object: link.id.uuidString as NSString)
                            }
                            .onDrop(of: [.text], delegate: WebsiteLinkDropDelegate(
                                item: link,
                                items: websiteLinks,
                                draggedItem: $draggedWebsiteLink,
                                moveItems: { from, to in
                                    profileManager.moveWebsiteLinks(from: from, to: to)
                                }
                            ))
                    }
                }
            }
        } header: {
            Text("Website Links")
        } footer: {
            Text("Add websites for quick access from the on-screen keyboard.")
        }
    }

    // MARK: - Row View

    @ViewBuilder
    private func websiteLinkRow(_ link: WebsiteLink) -> some View {
        WebsiteLinkRowView(
            link: link,
            onEdit: {
                editingWebsiteLink = link
            },
            onDelete: {
                profileManager.removeWebsiteLink(link)
            }
        )
    }

    // MARK: - Actions

    private func addWebsiteLink() {
        var urlString = newWebsiteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty else { return }

        // Add https:// if no scheme provided
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "https://" + urlString
        }

        guard URL(string: urlString) != nil else {
            websiteURLError = "Invalid URL"
            return
        }

        websiteURLError = nil
        isFetchingWebsiteMetadata = true

        Task {
            let (faviconData, title) = await fetchWebsiteMetadata(for: urlString)

            let link = WebsiteLink(
                url: urlString,
                displayName: title,
                faviconData: faviconData
            )

            await MainActor.run {
                profileManager.addWebsiteLink(link)
                newWebsiteURL = ""
                isFetchingWebsiteMetadata = false
            }
        }
    }

    private func fetchWebsiteMetadata(for urlString: String) async -> (Data?, String) {
        guard let url = URL(string: urlString),
              let host = url.host else {
            return (nil, urlString)
        }

        // Fetch favicon using cache (handles fetching and caching)
        let faviconData = await FaviconCache.shared.fetchFavicon(for: urlString)

        // Fetch page HTML for title extraction
        var title = host.replacingOccurrences(of: "www.", with: "")
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let html = String(data: data, encoding: .utf8) {
                title = extractTitle(from: html) ?? title
            }
        } catch {
            // Use host as fallback title
        }

        return (faviconData, title)
    }

    private func extractTitle(from html: String?) -> String? {
        guard let html = html else { return nil }

        let pattern = "<title[^>]*>([^<]+)</title>"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let titleRange = Range(match.range(at: 1), in: html) {
            let title = String(html[titleRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return title
                .components(separatedBy: " - ").first?
                .components(separatedBy: " | ").first?
                .components(separatedBy: " \u{2014} ").first
        }

        return nil
    }
}
