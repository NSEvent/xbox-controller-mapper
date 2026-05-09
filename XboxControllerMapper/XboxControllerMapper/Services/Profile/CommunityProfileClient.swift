import Foundation

enum CommunityProfileClient {
    static let communityProfilesURL = "https://api.github.com/repos/NSEvent/xbox-controller-mapper/contents/community-profiles"

    static func fetchCommunityProfiles(session: URLSession = .shared) async throws -> [CommunityProfileInfo] {
        let data = try await fetchData(from: communityProfilesURL, session: session)

        do {
            let allItems = try JSONDecoder().decode([CommunityProfileInfo].self, from: data)
            return allItems.filter { $0.name.hasSuffix(".json") }
        } catch {
            throw CommunityProfileError.decodingError(error)
        }
    }

    static func fetchProfile(from urlString: String, session: URLSession = .shared) async throws -> Profile {
        let data = try await fetchData(from: urlString, session: session)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(Profile.self, from: data)
        } catch {
            throw CommunityProfileError.decodingError(error)
        }
    }

    /// Fetches the setup guide markdown sidecar (same path as the profile, with `.md` instead of `.json`).
    /// Returns nil if no sidecar exists (404). Throws only on network errors.
    static func fetchSetupGuide(forProfileURL profileURLString: String, session: URLSession = .shared) async throws -> String? {
        guard profileURLString.hasSuffix(".json") else { return nil }
        let mdURLString = String(profileURLString.dropLast(".json".count)) + ".md"

        guard let url = URL(string: mdURLString) else { return nil }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw CommunityProfileError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CommunityProfileError.invalidResponse
        }
        if httpResponse.statusCode == 404 { return nil }
        guard httpResponse.statusCode == 200 else {
            throw CommunityProfileError.invalidResponse
        }
        return String(data: data, encoding: .utf8)
    }

    private static func fetchData(from urlString: String, session: URLSession) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw CommunityProfileError.invalidURL
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw CommunityProfileError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw CommunityProfileError.invalidResponse
        }

        return data
    }
}
