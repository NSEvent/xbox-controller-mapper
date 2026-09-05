import Foundation

/// A retryable batch, shared by the picker and deterministic failure-path tests.
/// Import successes are reported immediately so retry never duplicates them.
@MainActor
enum CommunityProfileImportBatch {
	struct Failure: Equatable {
		let profileName: String
		let message: String
	}

	struct Result {
		var imported: [Profile] = []
		var failures: [Failure] = []
		var declinedCount = 0
		var wasCancelled = false

		var shouldDismiss: Bool {
			!imported.isEmpty && failures.isEmpty && declinedCount == 0 && !wasCancelled
		}
	}

	static func run(
		_ profiles: [CommunityProfileInfo],
		fetch: (CommunityProfileInfo) async throws -> Profile,
		approve: (Profile, String) async -> Bool,
		persist: (Profile) -> Profile,
		didImport: (CommunityProfileInfo, Profile) -> Void
	) async -> Result {
		var result = Result()
		for info in profiles {
			do {
				try Task.checkCancellation()
				let profile = try await fetch(info)
				try Task.checkCancellation()
				let approved = await approve(profile, info.displayName)
				try Task.checkCancellation()
				guard approved else {
					result.declinedCount += 1
					continue
				}
				let imported = persist(profile)
				result.imported.append(imported)
				didImport(info, imported)
			} catch {
				if Task.isCancelled || error is CancellationError {
					result.wasCancelled = true
					break
				}
				result.failures.append(Failure(
					profileName: info.displayName, message: error.localizedDescription
				))
			}
		}
		return result
	}
}
