import SwiftUI

struct PhysicalInputCaptureBar: View {
	@ObservedObject var session: PhysicalInputCaptureSession
	@EnvironmentObject private var controller: ControllerService
	@EnvironmentObject private var engine: MappingEngine
	var mode: ControllerInputCapture.Mode = .button

	var body: some View {
		HStack(spacing: 12) {
			Button {
				session.start(mode: mode, controller: controller, engine: engine)
			} label: {
				Label(mode == .button ? "Press to Edit" : "Capture Chord", systemImage: "hand.tap")
			}
			.disabled(!controller.isConnected || session.isListening)
			.help(mode == .button ? "Press a controller control to open its mapping editor" : "Hold controller buttons together to select a chord")
			if !session.message.isEmpty {
				Text(session.message).font(.caption).foregroundStyle(.secondary)
			}
			if let held = session.capture?.held, !held.isEmpty, mode == .chord {
				Text(held.sorted { $0.rawValue < $1.rawValue }.map(\.shortLabel).joined(separator: " + "))
					.font(.caption.bold())
			}
			Spacer(minLength: 0)
			if session.isActive, session.capture?.phase != .captured {
				Button("Cancel Capture") { session.cancel() }
					.keyboardShortcut(.escape, modifiers: [])
			}
		}
		.padding(10)
		.background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
		.accessibilityElement(children: .contain)
	}
}
