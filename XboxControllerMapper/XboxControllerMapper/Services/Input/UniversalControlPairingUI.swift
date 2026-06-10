import AppKit
import SwiftUI

@MainActor
private final class UniversalControlPairingCodePanel: NSPanel {
	override var canBecomeKey: Bool { true }
	override var canBecomeMain: Bool { false }
}

@MainActor
final class UniversalControlPairingCodePresenter {
	static let shared = UniversalControlPairingCodePresenter()

	private var panel: NSPanel?
	private var hostingView: NSHostingView<UniversalControlPairingCodeToast>?
	private var hideWorkItem: DispatchWorkItem?

	private init() {}

	func show(code: String, peerID: String, duration: TimeInterval = 60) {
		hideWorkItem?.cancel()

		let view = UniversalControlPairingCodeToast(code: code, peerID: peerID) { [weak self] in
			self?.hide()
		}
		if panel == nil {
			createPanel(with: view)
		} else {
			hostingView?.rootView = view
		}

		guard let panel, let hostingView else { return }
		let size = hostingView.fittingSize
		hostingView.frame = NSRect(origin: .zero, size: size)
		panel.setContentSize(size)
		position(panel)

		if !panel.isVisible {
			panel.alphaValue = 0
			panel.orderFrontRegardless()
		}

		NSAnimationContext.runAnimationGroup { context in
			context.duration = 0.12
			panel.animator().alphaValue = 1
		}

		let workItem = DispatchWorkItem { [weak self] in
			Task { @MainActor in
				self?.hide()
			}
		}
		hideWorkItem = workItem
		DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
	}

	private func hide() {
		hideWorkItem?.cancel()
		hideWorkItem = nil
		guard let panel, panel.isVisible else { return }
		NSAnimationContext.runAnimationGroup { context in
			context.duration = 0.16
			panel.animator().alphaValue = 0
		} completionHandler: {
			panel.orderOut(nil)
		}
	}

	private func createPanel(with view: UniversalControlPairingCodeToast) {
		let hostingView = NSHostingView(rootView: view)
		let panel = UniversalControlPairingCodePanel(
			contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
			styleMask: [.borderless, .nonactivatingPanel],
			backing: .buffered,
			defer: false
		)
		panel.isOpaque = false
		panel.backgroundColor = .clear
		panel.hasShadow = true
		panel.ignoresMouseEvents = false
		panel.level = .floating
		panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
		panel.hidesOnDeactivate = false
		panel.contentView = hostingView

		self.panel = panel
		self.hostingView = hostingView
	}

	private func position(_ panel: NSPanel) {
		let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
			?? CGRect(x: 0, y: 0, width: 1728, height: 1117)
		let size = panel.frame.size
		panel.setFrameOrigin(NSPoint(
			x: screenFrame.midX - size.width * 0.5,
			y: screenFrame.maxY - size.height - 72
		))
	}
}

private struct UniversalControlPairingCodeToast: View {
	let code: String
	let peerID: String
	let onDismiss: () -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 10) {
				Text("ControllerKeys Pairing Code")
					.font(.headline)

				Spacer(minLength: 8)

				Button {
					onDismiss()
				} label: {
					Image(systemName: "xmark")
						.font(.system(size: 11, weight: .bold))
						.foregroundStyle(.secondary)
						.frame(width: 24, height: 24)
						.contentShape(Circle())
				}
				.buttonStyle(.plain)
				.keyboardShortcut(.cancelAction)
				.accessibilityLabel("Dismiss pairing code")
			}

			Text(code)
				.font(.system(size: 34, weight: .bold, design: .monospaced))
				.monospacedDigit()
				.lineLimit(1)
				.minimumScaleFactor(0.7)

			Text("Enter this code on \(peerID).")
				.font(.caption)
				.foregroundStyle(.secondary)
		}
		.padding(.horizontal, 18)
		.padding(.vertical, 14)
		.frame(width: 320, alignment: .leading)
		.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
		.overlay {
			RoundedRectangle(cornerRadius: 12, style: .continuous)
				.stroke(Color(nsColor: .separatorColor), lineWidth: 1)
		}
		.accessibilityElement(children: .contain)
	}
}
