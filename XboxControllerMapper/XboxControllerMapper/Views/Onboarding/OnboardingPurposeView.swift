import SwiftUI

struct OnboardingPurposeView: View {
	let selection: TelemetryService.ProductUseCase?
	let onSelect: (TelemetryService.ProductUseCase) -> Void
	/// Optional free-text "tell me more" answer. Sent only if non-empty when the user continues.
	@Binding var note: String
	/// Optional reply email for the note.
	@Binding var contact: String

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("What would you like to do first?").font(.headline)
			Text("Choose a starting point. You can change every mapping later.")
				.font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
			ForEach(TelemetryService.ProductUseCase.startingChoices) { purpose in
				Button { onSelect(purpose) } label: {
					HStack(spacing: 10) {
						Image(systemName: purpose.onboardingIcon).frame(width: 22)
						Text(purpose.onboardingTitle)
						Spacer()
						Image(systemName: selection == purpose ? "checkmark.circle.fill" : "circle")
					}
					.font(.callout).padding(.horizontal, 10).padding(.vertical, 8)
					.contentShape(Rectangle())
					.background(selection == purpose ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.06),
								in: RoundedRectangle(cornerRadius: 8))
				}
				.buttonStyle(.plain)
				.accessibilityAddTraits(selection == purpose ? .isSelected : [])
				.accessibilityIdentifier("onboarding-purpose-\(purpose.rawValue)")
			}
			OnboardingUseCaseNoteField(note: $note, contact: $contact)
				.padding(.top, 8)
		}
	}
}

/// "Tell me more" box under the starting-point choices. Fully optional.
struct OnboardingUseCaseNoteField: View {
	@Binding var note: String
	@Binding var contact: String

	private var hasNote: Bool { !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("Tell me more (optional)").font(.headline)
			Text("Hi, I'm Kevin, the indie creator behind ControllerKeys, and I read every answer myself. "
				 + "Telling me which apps, games or tasks you want to control helps me shape the app around how you use it.")
				.font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
			TextField("e.g. culling photos in Lightroom, Anki from bed, editing in Final Cut…",
					  text: Binding(get: { note }, set: { note = String($0.prefix(OnboardingUseCaseNote.maxLength)) }),
					  axis: .vertical)
				.lineLimit(1...5)
				.textFieldStyle(.roundedBorder)
				.accessibilityIdentifier("onboarding-use-case-note")
			if hasNote {
				TextField("Email (optional, only if you'd like a reply)", text: $contact)
					.textFieldStyle(.roundedBorder)
					.textContentType(.emailAddress)
					.accessibilityIdentifier("onboarding-use-case-contact")
				Text("Sent when you press Get Started, with your app version and Mac model. Email only if you enter one.")
					.font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
			}
		}
	}
}

struct OnboardingSetupSuggestionsView: View {
	let purpose: TelemetryService.ProductUseCase?
	let onOpen: (OnboardingSetupDestination) -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Start with a useful preset").font(.headline)
			Text("Review its buttons and app settings, then try one action. Your existing profiles stay saved.")
				.font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
			ForEach(purpose?.setupSuggestions ?? [.profiles]) { destination in
				Button { onOpen(destination) } label: {
					HStack { Text(destination.title); Spacer(); Image(systemName: "arrow.right") }
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.bordered)
			}
		}
	}
}
