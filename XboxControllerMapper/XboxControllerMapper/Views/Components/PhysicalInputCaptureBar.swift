import SwiftUI

struct PhysicalInputCaptureBar: View {
	@ObservedObject var session: PhysicalInputCaptureSession
	@EnvironmentObject private var controller: ControllerService
	@EnvironmentObject private var engine: MappingEngine
	var mode: ControllerInputCapture.Mode = .button
	private var title: String {
		if session.capture?.phase == .ambiguous || session.sequence?.ambiguous == true || session.interrupted { return "Retry Capture" }
		switch mode {
		case .button: return "Press to Edit"
		case .chord: return "Capture Chord"
		case .sequence: return "Capture Sequence"
		}
	}

	var body: some View {
		HStack(spacing: 12) {
			Button {
				session.start(mode: mode, controller: controller, engine: engine)
			} label: {
				Label(title, systemImage: mode == .sequence ? "record.circle" : "scope")
					.font(.caption.weight(.medium))
					.padding(.horizontal, 10).padding(.vertical, 6)
					.background(Color.primary.opacity(session.isListening ? 0.12 : 0.06), in: Capsule())
			}
			.buttonStyle(.plain)
			.foregroundStyle(session.isListening ? Color.accentColor : Color.secondary)
			.disabled(!controller.isConnected || (session.isListening && session.sequence?.ambiguous != true))
			.help(mode == .button ? "Press a controller control to open its mapping editor" : mode == .chord ? "Hold controller buttons together to select a chord" : "Record controller buttons in press order")
			if !session.message.isEmpty {
				Text(session.message).font(.caption).foregroundStyle(.secondary)
			}
			if let held = session.capture?.held, !held.isEmpty, mode == .chord {
				Text(held.sorted { $0.rawValue < $1.rawValue }.map { button in
						return ControllerVisualDescriptor.inputWorkflow(profile: engine.profileManager.activeProfile, using: controller).buttonLabel(button)
					}.joined(separator: " + "))
					.font(.caption.bold())
			}
			Spacer(minLength: 0)
			if mode == .sequence, session.isListening {
				Button("Use Sequence") { session.finishSequence() }
					.disabled((session.sequence?.steps.count ?? 0) < 2 || session.sequence?.ambiguous == true)
			}
			if session.isActive, session.capture?.phase != .captured {
				Button("Cancel Capture") { session.cancel() }
					.keyboardShortcut(.escape, modifiers: [])
			}
		}
		.accessibilityElement(children: .contain)
	}
}
