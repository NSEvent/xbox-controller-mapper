import SwiftUI

/// Keep capture lifecycle out of the main window's already large modifier chain.
struct PhysicalInputCaptureRouting: ViewModifier {
	@ObservedObject var session: PhysicalInputCaptureSession
	@Binding var selectedButton: ControllerButton?
	@Binding var configuringButton: ControllerButton?
	@Binding var isSwapMode: Bool
	@Binding var swapFirstButton: ControllerButton?
	let profileManager: ProfileManager
	var selectedLayerId: UUID?
	var selectedTab: Int

	func body(content: Content) -> some View {
		content
			.onChange(of: session.result) { _, buttons in
				guard let button = buttons?.first else { return }
				// An armed swap takes the press as its next pick, like a click would.
				if isSwapMode {
					if let pair = ButtonSwapSelection.pick(button, first: &swapFirstButton, isSwapMode: &isSwapMode) {
						ButtonSwapSelection.apply(pair, layerId: selectedLayerId, profileManager: profileManager)
					}
					return
				}
				selectedButton = button
				configuringButton = button
			}
			.onChange(of: session.interrupted) { _, interrupted in
				if interrupted { configuringButton = nil }
			}
			.onChange(of: configuringButton) { _, button in
				if button == nil, !session.interrupted { session.cancel() }
			}
			.onChange(of: selectedLayerId) { _, _ in if !session.interrupted { session.cancel() } }
			.onChange(of: selectedTab) { _, _ in if !session.interrupted { session.cancel() } }
			.onDisappear { session.cancel() }
	}
}
