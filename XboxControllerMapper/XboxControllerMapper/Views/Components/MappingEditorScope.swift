import SwiftUI

/// A draft belongs to the profile that opened it. A controller-layout change
/// is presentation only; a profile switch invalidates the draft's destination.
struct MappingEditorScope {
	private(set) var profileId: UUID?
	private var started = false
	private var invalidated = false

	mutating func begin(profileId: UUID?) {
		guard !started else { return }
		started = true
		self.profileId = profileId
	}

	mutating func profileChanged(to id: UUID?) {
		if started, id != profileId { invalidated = true }
	}

	func canSave(to id: UUID?) -> Bool {
		started && !invalidated && profileId != nil && profileId == id
	}
}

private struct MappingEditorScopeModifier: ViewModifier {
	@Binding var scope: MappingEditorScope
	let profileId: UUID?
	@Environment(\.dismiss) private var dismiss

	func body(content: Content) -> some View {
		content
			.disabled(!scope.canSave(to: profileId))
			.onAppear { scope.begin(profileId: profileId) }
			.onChange(of: profileId) { _, id in
				scope.profileChanged(to: id)
				if !scope.canSave(to: id) { dismiss() }
			}
	}
}

extension View {
	func mappingEditorScope(_ scope: Binding<MappingEditorScope>, profileId: UUID?) -> some View {
		modifier(MappingEditorScopeModifier(scope: scope, profileId: profileId))
	}
}
