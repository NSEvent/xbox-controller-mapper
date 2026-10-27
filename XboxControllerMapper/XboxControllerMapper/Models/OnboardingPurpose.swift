import Foundation

/// Purpose is a starting point, never permission to replace the user's mappings.
extension TelemetryService.ProductUseCase {
	static let startingChoices: [Self] = [.study, .photoVideo, .macControl, .gaming, .music, .coding, .other]

	var onboardingTitle: String {
		switch self {
		case .study: return String(localized: "Anki / studying")
		case .photoVideo: return String(localized: "Photos / video")
		case .macControl: return String(localized: "Mouse / Mac control")
		case .gaming: return String(localized: "Games")
		case .music: return String(localized: "Music")
		case .coding: return String(localized: "Coding / automation")
		case .other: return String(localized: "Just exploring / other")
		case .presentations: return String(localized: "Presentations")
		case .accessibility: return String(localized: "Accessibility")
		case .couchControl: return String(localized: "Couch / media control")
		case .creativeTools: return String(localized: "Creative tools")
		}
	}

	var onboardingIcon: String {
		switch self {
		case .study: return "rectangle.on.rectangle"
		case .photoVideo, .creativeTools: return "photo.on.rectangle"
		case .macControl, .accessibility: return "cursorarrow"
		case .gaming: return "gamecontroller"
		case .music: return "music.note"
		case .coding: return "terminal"
		case .presentations: return "play.rectangle"
		case .couchControl: return "tv"
		case .other: return "sparkle.magnifyingglass"
		}
	}

	var setupSuggestions: [OnboardingSetupDestination] {
		switch self {
		case .study: return [.guided(.anki), .profiles]
		case .photoVideo: return [.guided(.photoCulling), .guided(.finalCut), .profiles]
		case .macControl, .accessibility: return [.guided(.oneHand), .profiles]
		default: return [.profiles]
		}
	}
}

enum OnboardingSetupDestination: Hashable, Identifiable {
	case guided(GuidedPreset)
	case profiles

	var id: String {
		switch self {
		case .guided(let preset): return preset.rawValue
		case .profiles: return "profiles"
		}
	}
	var title: String {
		switch self {
		case .guided(let preset): return preset.title
		case .profiles: return String(localized: "Browse starter profiles")
		}
	}
}

enum OnboardingPurposePreference {
	static let key = "onboardingStartingPurpose.v1"

	static func load(from defaults: UserDefaults) -> TelemetryService.ProductUseCase? {
		defaults.string(forKey: key).flatMap(TelemetryService.ProductUseCase.init(rawValue:))
	}

	static func save(_ purpose: TelemetryService.ProductUseCase?, to defaults: UserDefaults) {
		if let purpose { defaults.set(purpose.rawValue, forKey: key) }
		else { defaults.removeObject(forKey: key) }
	}
}

/// Optional free-text answer on the welcome screen ("tell me more about what you'll use it for").
///
/// Deliberately separate from telemetry: the typed note is never part of a telemetry
/// milestone. It is sent only when the user types something and presses Get Started, through
/// the same user-initiated feedback backend as Settings → Send Feedback (category
/// `use_case`), so it lands in the existing feedback inbox next to other use-case notes.
enum OnboardingUseCaseNote {
	static let maxLength = 1000
	static let trigger = "onboarding_purpose"
	static let sentKey = "onboardingUseCaseNoteSent.v1"

	/// The message body sent to the feedback backend, or nil when there is nothing to send.
	static func message(purpose: TelemetryService.ProductUseCase?, note: String) -> String? {
		let trimmed = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLength))
		guard !trimmed.isEmpty else { return nil }
		let start = purpose.map { "\($0.rawValue) (\($0.onboardingTitle))" } ?? "none chosen"
		return "[First launch] What I'll use ControllerKeys for\nStarting point: \(start)\n\n\(trimmed)"
	}

	/// Reply address, only when it looks like an email. Anything else is dropped, never guessed.
	static func sanitizedContact(_ contact: String) -> String? {
		let trimmed = contact.trimmingCharacters(in: .whitespacesAndNewlines)
		guard trimmed.count <= 254, !trimmed.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains) else { return nil }
		let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
		guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."),
			  !parts[1].hasPrefix("."), !parts[1].hasSuffix(".") else { return nil }
		return trimmed
	}

	/// Whether a note should be sent now: only once per install, and only with real text.
	static func shouldSend(purpose: TelemetryService.ProductUseCase?, note: String, defaults: UserDefaults) -> Bool {
		!defaults.bool(forKey: sentKey) && message(purpose: purpose, note: note) != nil
	}

	/// Fire-and-forget send; never blocks onboarding. Retries once on failure.
	static func submitIfNeeded(purpose: TelemetryService.ProductUseCase?, note: String, contact: String,
							   defaults: UserDefaults = .standard) {
		guard shouldSend(purpose: purpose, note: note, defaults: defaults),
			  let body = message(purpose: purpose, note: note) else { return }
		defaults.set(true, forKey: sentKey)
		let reply = sanitizedContact(contact)
		let client = FeedbackClient(config: FeedbackConfig(appName: "ControllerKeys"))
		let source = trigger
		// Same pattern as FeedbackFormView: a plain Task; URLSession does the waiting off-main.
		Task {
			for attempt in 0..<2 {
				do {
					try await client.submit(message: body, contact: reply, category: .useCase, trigger: source)
					return
				} catch {
					if attempt == 0 { try? await Task.sleep(nanoseconds: 30_000_000_000) }
				}
			}
		}
	}
}

enum OnboardingEntryPolicy {
	static func initialStep(requested: OnboardingStep, isFirstRun: Bool, permissionsReady: Bool) -> OnboardingStep {
		if requested != .welcome { return requested }
		if isFirstRun { return .welcome }
		return permissionsReady ? .controllerTest : .welcome
	}
}

enum OnboardingInputPreviewPolicy {
	static func shouldMute(step: OnboardingStep) -> Bool {
		switch step {
		case .welcome, .inputMonitoring, .accessibility, .bluetooth: return true
		// ControllerTest owns its preview; Done must allow the guided real-action test.
		case .controllerTest, .done: return false
		}
	}
}
