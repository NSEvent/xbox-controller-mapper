import Foundation

enum ProfileTransferService {
    static func export(_ profile: Profile, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        let data = try encoder.encode(profile)
        // .atomic writes via temp-file-then-rename so a crash or power loss
        // mid-write can never leave a half-written profile on disk.
        try AtomicFileWriter.write(data, to: url)
    }

    static func importProfile(from url: URL) throws -> Profile {
        let data = try Data(contentsOf: url)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let profile = try decoder.decode(Profile.self, from: data)
        return prepareForImport(profile)
    }

    static func prepareForImport(_ profile: Profile) -> Profile {
        var importedProfile = profile
        importedProfile.id = UUID()
        importedProfile.isDefault = false
        return importedProfile
    }
}
