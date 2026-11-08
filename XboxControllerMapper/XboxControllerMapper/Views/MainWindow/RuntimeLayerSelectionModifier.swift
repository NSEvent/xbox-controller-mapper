import SwiftUI

/// Keeps the Buttons editor on the layer the controller is using: holding or
/// toggling a layer activator shows that layer's mappings, and releasing it
/// returns to Base. App-activated layers are excluded (activeManualLayerId),
/// so switching apps never moves the editor out from under the user.
struct RuntimeLayerSelectionModifier: ViewModifier {
	@ObservedObject var mappingEngine: MappingEngine
	@Binding var selectedLayerId: UUID?

	func body(content: Content) -> some View {
		content
			.onAppear {
				if let activeManualLayerId = mappingEngine.activeManualLayerId {
					selectedLayerId = activeManualLayerId
				}
			}
			.onChange(of: mappingEngine.activeManualLayerId) { _, layerId in
				selectedLayerId = layerId
			}
	}
}
