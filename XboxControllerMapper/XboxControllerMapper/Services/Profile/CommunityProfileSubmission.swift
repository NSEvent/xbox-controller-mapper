import Foundation
import TriggerKitCore

struct CommunityProfileSubmissionDetails: Equatable {
	var name: String
	var summary = ""
	var controller = ""
	var instructions = ""

	var isValid: Bool {
		!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 80 &&
		!summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && summary.count <= 500 &&
		!controller.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && controller.count <= 120 && instructions.count <= 1500
	}
}

struct CommunityProfileSubmission {
	let profile: Profile
	let json: Data
	let guide: String
	let issueBody: String
	/// Complete reviewed payload for pasting, never placed in a browser URL.
	let pasteBody: String?
	let issueURL: URL
	let filename: String
	let removedItems: [String]
	let reviewFields: [String]

	static func prepare(profile source: Profile, details: CommunityProfileSubmissionDetails,
		includeCustomActions: Bool = false, now: Date = Date(), id: UUID = UUID()) throws -> Self {
		guard details.isValid else { throw SubmissionError.missingDetails }
		var profile = source
		profile.id = id
		profile.name = details.name.trimmingCharacters(in: .whitespacesAndNewlines)
		profile.isDefault = false
		profile.createdAt = now
		profile.modifiedAt = now
		profile.linkedControllers = []
		profile.inheritedOnScreenKeyboardProfileId = nil
		var removed = ["Saved controller identities, default status and keyboard inheritance"]
		if !includeCustomActions {
			var references = SubmissionReferenceCollector()
			profile.walkSurface(&references)
			for id in references.macros.union(profile.macros.map(\.id)).union(profile.sharedMacroSnapshots.keys) {
				profile = ProfileAutomationReferencePolicy.removingReferences(to: id, kind: .macro, from: profile)
			}
			for id in references.scripts.union(profile.scripts.map(\.id)) {
				profile = ProfileAutomationReferencePolicy.removingReferences(to: id, kind: .script, from: profile)
			}
			removed.append("\(source.macros.count + source.sharedMacroSnapshots.count) macros and \(source.scripts.count) scripts, including their bindings")
			profile.macros = []
			profile.scripts = []
			profile.sharedMacroSnapshots = [:]
			profile.onScreenKeyboardSettings = OnScreenKeyboardSettings()
			removed.append("Custom keyboard text, app bar, website links and terminal settings")
		}
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		encoder.userInfo[.omitPrivateCredentials] = true
		removed.append("OBS passwords and Keychain references")
		let original = try JSONSerialization.jsonObject(with: encoder.encode(profile))
		var removedCommands = 0
		let cleaned = clean(original, includeCustomActions: includeCustomActions, removedCommands: &removedCommands)
		let data = try JSONSerialization.data(withJSONObject: cleaned, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
		guard data.count <= 1_000_000 else { throw SubmissionError.tooLarge }
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		profile = try decoder.decode(Profile.self, from: data)
		if removedCommands > 0 { removed.append("\(removedCommands) personal or non-portable actions") }
		let filename = fileStem(profile.name) + ".json"
		let notes = removed.map { "- \($0)" }.joined(separator: "\n")
		let guide = """
		# \(plain(profile.name))

		## What this setup does
		\(plain(details.summary))

		## Controller
		\(plain(details.controller))

		## Setup and first action
		\(plain(details.instructions.isEmpty ? "Import this profile in ControllerKeys, then review its mappings before testing." : details.instructions))

		## Linked apps
		\(profile.linkedApps.isEmpty ? "Choose an app or assign this profile manually after importing." : profile.linkedApps.map { "- \(plain($0))" }.joined(separator: "\n"))

		## Shared-copy changes
		\(notes)

		\(includeCustomActions ? "Custom actions are included. Review their code, text, links and dependencies before importing." : "Custom automations and text are omitted. Review the remaining mappings before testing.")
		"""
		let body = """
		## Community profile submission
		\(guide)

		- [ ] I tested this setup and described any requirements.
		- [ ] I reviewed the shared profile and description for private data.
		- [ ] I agree to publish this profile in the ControllerKeys community library under the repository's PolyForm Noncommercial 1.0.0 license.

		Submitted for maintainer review; this is not yet a community-library entry.
		"""
		// A single paste carries the description AND profile. Keep a conservative
		// budget; larger profiles use the explicit file-attachment flow instead.
		let compactJSON = try JSONSerialization.data(withJSONObject: cleaned, options: [.sortedKeys, .withoutEscapingSlashes])
		let complete = body + "\n\n## Profile data\n\n```json\n" + String(decoding: compactJSON, as: UTF8.self) + "\n```\n"
		let pasteBody = complete.utf8.count <= 60_000 ? complete : nil
		let draftBody: String
		if pasteBody != nil {
			draftBody = """
			## Paste your ControllerKeys submission here

			Click inside this description, select all (⌘A), then paste (⌘V).
			ControllerKeys copied your description AND reviewed profile together.
			Before submitting, check that a **Profile data** section appears below your description.
			If your clipboard changed, return to ControllerKeys and click **Copy Complete Submission**.
			"""
		} else {
			draftBody = """
			## Profile attachment required
			This description does not contain your profile yet. Attach **\(filename)** before submitting.
			In ControllerKeys, click **Show Profile File**, then drag that file into this description.
			Wait until GitHub shows a clickable file link. A description alone cannot be added to the library.

			\(body)
			"""
		}
		var components = URLComponents(string: "https://github.com/NSEvent/xbox-controller-mapper/issues/new")!
		components.queryItems = [URLQueryItem(name: "title", value: "[Community Profile] \(profile.name)"),
			URLQueryItem(name: "body", value: draftBody)]
		guard let url = components.url, url.absoluteString.utf8.count <= 8000 else { throw SubmissionError.detailsTooLong }
		let fields = privateFields(in: cleaned) + privateFields(in: ["name": details.name, "summary": details.summary,
			"controller": details.controller, "instructions": details.instructions], path: "description")
		return Self(profile: profile, json: data, guide: guide, issueBody: draftBody, pasteBody: pasteBody, issueURL: url,
			filename: filename, removedItems: removed, reviewFields: Array(Set(fields)).sorted())
	}

	/// Work only on encoded copies. Removing an effective command clears dormant
	/// sibling actions too, so sharing never turns a hidden binding into a new action.
	private static func clean(_ value: Any, includeCustomActions: Bool, removedCommands: inout Int) -> Any {
		if let array = value as? [Any] { return array.map { clean($0, includeCustomActions: includeCustomActions, removedCommands: &removedCommands) } }
		guard var object = value as? [String: Any] else { return value }
		if !includeCustomActions && (object["macroId"] != nil || object["scriptId"] != nil) {
			if object["systemCommand"] == nil {
				for key in ["keyCode", "midiControlChange", "repeatMapping", "hint", "hapticStyle"] { object.removeValue(forKey: key) }
				object["modifiers"] = ["command": false, "option": false, "shift": false, "control": false]
			}
			object.removeValue(forKey: "macroId")
			object.removeValue(forKey: "scriptId")
		}
		if let command = object["systemCommand"] as? [String: Any] {
			let type = command["type"] as? String
			let localProfile = type == "switchProfile" && command["profileNavigation"] == nil
			let portable = type == "launchApp" || type == "centerOuraRing" || type == "toggleOuraMotion" || (type == "switchProfile" && !localProfile)
			if localProfile || (!includeCustomActions && !portable) {
				for key in ["systemCommand", "keyCode", "macroId", "scriptId", "midiControlChange", "repeatMapping", "hint", "hapticStyle"] { object.removeValue(forKey: key) }
				object["modifiers"] = ["command": false, "option": false, "shift": false, "control": false]
				removedCommands += 1
			}
		}
		return object.mapValues { clean($0, includeCustomActions: includeCustomActions, removedCommands: &removedCommands) }
	}

	private static func privateFields(in value: Any, path: String = "profile") -> [String] {
		if let object = value as? [String: Any] {
			return object.flatMap { key, value -> [String] in
				if ["password", "authorization", "token", "secret", "api_key", "apikey"].contains(key.lowercased()),
					let text = value as? String, !text.isEmpty { return ["\(path).\(key)"] }
				return privateFields(in: value, path: "\(path).\(key)")
			}
		}
		if let array = value as? [Any] { return array.enumerated().flatMap { privateFields(in: $0.element, path: "\(path)[\($0.offset)]") } }
		guard let text = value as? String else { return [] }
		let pattern = #"(?i)(/Users/|/home/|~/|\b(?:localhost|127\.0\.0\.1|192\.168\.|10\.\d+\.)|[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}|\b(?:gh[pousr]_[A-Za-z0-9]+|github_pat_[A-Za-z0-9_]+|sk-[A-Za-z0-9_-]{12,})|(?:token|password|secret|authorization|api[_-]?key)\s*[=:]|https?://[^\s/]+:[^\s/]+@)"#
		return text.range(of: pattern, options: .regularExpression) == nil ? [] : [path]
	}

	private static func fileStem(_ name: String) -> String {
		let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
		let result = String(name.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }).prefix(80)
		let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmed.isEmpty ? "Community Profile" : trimmed
	}

	private static func plain(_ text: String) -> String {
		// Avoid unintended mentions and HTML in drafts.
		text.replacingOccurrences(of: "@", with: "＠").replacingOccurrences(of: "<", with: "‹")
			.replacingOccurrences(of: ">", with: "›").replacingOccurrences(of: "```", with: "'''" )
	}

	enum SubmissionError: LocalizedError {
		case missingDetails, tooLarge, detailsTooLong
		var errorDescription: String? {
			switch self {
			case .missingDetails: return "Add a public name, a short description and the controller you tested. Keep the setup notes under 1,500 characters."
			case .tooLarge: return "This profile is too large to prepare. Remove unused scripts or macros from a duplicate and try again."
			case .detailsTooLong: return "Shorten the setup description before opening the GitHub draft."
			}
		}
	}
}

private struct SubmissionReferenceCollector: ProfileSurfaceVisitor {
	var macros: Set<UUID> = []
	var scripts: Set<UUID> = []
	mutating func visit(action: any ExecutableAction, context: String) {
		if let id = action.macroId { macros.insert(id) }
		if let id = action.scriptId { scripts.insert(id) }
	}
	mutating func visit(systemCommand: SystemCommand, context: String) {}
	mutating func visit(macroStep: MacroStep, context: String) {}
	mutating func visit(script: Script) {}
	mutating func visit(quickText: QuickText) {}
	mutating func visit(automationStep: AutomationStep, context: String) {}
}
