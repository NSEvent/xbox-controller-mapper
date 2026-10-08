import SwiftUI

struct OnboardingPurposeView: View {
	let selection: TelemetryService.ProductUseCase?
	let onSelect: (TelemetryService.ProductUseCase) -> Void

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
