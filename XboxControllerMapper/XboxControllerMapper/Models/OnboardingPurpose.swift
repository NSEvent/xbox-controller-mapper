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
