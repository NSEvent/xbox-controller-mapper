import Foundation
import AppKit

/// Manages favicon caching for website links
/// Favicons are stored in ~/.controllerkeys/favicons/ using URL hash as filename
class FaviconCache {
    static let shared = FaviconCache()

    private let cacheDirectory: URL
    private let fileManager = FileManager.default

    private init() {
        let homeDir = fileManager.homeDirectoryForCurrentUser
        cacheDirectory = homeDir
            .appendingPathComponent(".controllerkeys", isDirectory: true)
            .appendingPathComponent("favicons", isDirectory: true)

        // Create cache directory if needed
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Cache Operations

    /// Returns the cache file URL for a given website URL
    private func cacheURL(for websiteURL: String) -> URL {
        // Use a hash of the URL as the filename
        let hash = websiteURL.hashValue
        let filename = String(format: "%lx.png", UInt(bitPattern: hash))
        return cacheDirectory.appendingPathComponent(filename)
    }

    /// Load favicon from disk cache
    func loadCachedFavicon(for websiteURL: String) -> Data? {
        let url = cacheURL(for: websiteURL)
        return try? Data(contentsOf: url)
    }

    /// Save favicon to disk cache
    func saveFavicon(_ data: Data, for websiteURL: String) {
        let url = cacheURL(for: websiteURL)
        try? data.write(to: url)
    }

    /// Delete cached favicon
    func deleteCachedFavicon(for websiteURL: String) {
        let url = cacheURL(for: websiteURL)
        try? fileManager.removeItem(at: url)
    }

    // MARK: - Favicon Fetching

    /// Fetch favicon for a website, checking cache first
    /// Returns the favicon data, or nil if fetch failed
    func fetchFavicon(for websiteURL: String, forceRefresh: Bool = false) async -> Data? {
        // Check cache first unless forcing refresh
        if !forceRefresh, let cached = loadCachedFavicon(for: websiteURL) {
            return cached
        }

        // Fetch from network
        guard let url = URL(string: websiteURL),
              let host = url.host else {
            return nil
        }

        // Fetch page HTML for favicon extraction
        var html: String?
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            html = String(data: data, encoding: .utf8)
        } catch {
            // Continue without HTML
        }

        // Try to get favicon from HTML link tags first
        var faviconData = await fetchFaviconFromHTML(html: html, baseURL: url)

        // Fall back to Google's service
        if faviconData == nil {
            faviconData = await fetchFaviconFromGoogle(host: host)
        }

        // Cache the result
        if let data = faviconData {
            saveFavicon(data, for: websiteURL)
        }

        return faviconData
    }

    /// Fetch favicon by parsing HTML link tags
    private func fetchFaviconFromHTML(html: String?, baseURL: URL) async -> Data? {
        guard let html = html else { return nil }

        // Look for favicon in link tags (apple-touch-icon or icon)
        let patterns = [
            "<link[^>]*rel=[\"']apple-touch-icon[\"'][^>]*href=[\"']([^\"']+)[\"']",
            "<link[^>]*href=[\"']([^\"']+)[\"'][^>]*rel=[\"']apple-touch-icon[\"']",
            "<link[^>]*rel=[\"']icon[\"'][^>]*href=[\"']([^\"']+)[\"']",
            "<link[^>]*href=[\"']([^\"']+)[\"'][^>]*rel=[\"']icon[\"']",
            "<link[^>]*rel=[\"']shortcut icon[\"'][^>]*href=[\"']([^\"']+)[\"']"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let urlRange = Range(match.range(at: 1), in: html) {
                let faviconURLString = String(html[urlRange])

                // Resolve relative URLs
                var faviconURL: URL?
                if faviconURLString.hasPrefix("http") {
                    faviconURL = URL(string: faviconURLString)
                } else if faviconURLString.hasPrefix("//") {
                    faviconURL = URL(string: "https:" + faviconURLString)
                } else if faviconURLString.hasPrefix("/") {
                    faviconURL = URL(string: faviconURLString, relativeTo: URL(string: "https://\(baseURL.host ?? "")"))
                } else {
                    faviconURL = URL(string: faviconURLString, relativeTo: baseURL)
                }

                if let url = faviconURL {
                    do {
                        let (data, response) = try await URLSession.shared.data(from: url)
                        if let httpResponse = response as? HTTPURLResponse,
                           httpResponse.statusCode == 200,
                           data.count > 100 {
                            return data
                        }
                    } catch {
                        continue // Try next pattern
                    }
                }
            }
        }

        return nil
    }

    /// Fetch favicon using Google's favicon service
    private func fetchFaviconFromGoogle(host: String) async -> Data? {
        guard let googleURL = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=128") else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: googleURL)
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200,
               data.count > 100 {  // Ensure it's not a placeholder
                return data
            }
        } catch {
            // Fall through to return nil
        }

        return nil
    }
}
