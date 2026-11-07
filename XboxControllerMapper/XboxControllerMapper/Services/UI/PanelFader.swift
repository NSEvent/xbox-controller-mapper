import AppKit

/// Fades an overlay panel in and out. NSAnimationContext still runs a fade-out's
/// completion handler when a newer fade-in interrupts it, so ordering the panel
/// out unconditionally there hides a panel that was just shown again while its
/// owner still believes it is visible. Each fade bumps a generation, and a
/// fade-out only orders out if no later fade started.
///
/// One fader per panel. Instant shows (no fade-in) call `cancelFadeOut()`.
@MainActor
final class PanelFader {
	private var generation = 0

	func fadeIn(_ panel: NSWindow?, duration: TimeInterval) {
		generation &+= 1
		guard let panel else { return }
		NSAnimationContext.runAnimationGroup { context in
			context.duration = duration
			panel.animator().alphaValue = 1
		}
	}

	func cancelFadeOut() {
		generation &+= 1
	}

	/// `completion` runs after the panel is ordered out, and not at all if the
	/// panel was shown again during the fade.
	func fadeOut(_ panel: NSWindow?, duration: TimeInterval, completion: (() -> Void)? = nil) {
		generation &+= 1
		let fade = generation
		guard let panel else { return }
		NSAnimationContext.runAnimationGroup({ context in
			context.duration = duration
			panel.animator().alphaValue = 0
		}, completionHandler: { [weak self] in
			MainActor.assumeIsolated {
				guard let self, self.generation == fade else { return }
				panel.orderOut(nil)
				completion?()
			}
		})
	}
}
