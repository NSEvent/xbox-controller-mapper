import SwiftUI

/// Keep capture lifecycle out of the main window's already large modifier chain.
struct PhysicalInputCaptureRouting: ViewModifier {
	@ObservedObject var session: PhysicalInputCaptureSession
	@Binding var selectedButton: ControllerButton?
	@Binding var configuringButton: ControllerButton?
	var selectedLayerId: UUID?
	var selectedTab: Int

	func body(content: Content) -> some View {
		content
			.onChange(of: session.result) { _, buttons in
				guard let button = buttons?.first else { return }
				selectedButton = button
				configuringButton = button
			}
			.onChange(of: session.interrupted) { _, interrupted in
				if interrupted { configuringButton = nil }
			}
			.onChange(of: configuringButton) { _, button in
				if button == nil { session.cancel() }
			}
			.onChange(of: selectedLayerId) { _, _ in session.cancel() }
			.onChange(of: selectedTab) { _, _ in session.cancel() }
			.onDisappear { session.cancel() }
	}
}
