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
