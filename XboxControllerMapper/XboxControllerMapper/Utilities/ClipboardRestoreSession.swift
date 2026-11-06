import AppKit

/// Puts text on the clipboard for a synthetic Cmd+V and later puts the user's
/// clipboard back. Pastes can overlap (a second quick-text fires before the
/// first one's restore), so the snapshot is taken once per burst: snapshotting
/// on every paste would save the previous snippet as "the user's clipboard".
/// The restore runs when the last outstanding paste ends, and only if nothing
/// else wrote to the clipboard after our last write.
///
/// Main-thread only.
final class ClipboardRestoreSession {
	private let pasteboard: NSPasteboard
	private var outstandingPastes = 0
	private var snapshot: String?
	private var lastWrittenChangeCount: Int?

	init(pasteboard: NSPasteboard = .general) {
		self.pasteboard = pasteboard
	}

	/// Writes `text` for pasting. Pair every call with `endPaste()`.
	func beginPaste(_ text: String) {
		// First paste of a burst, or someone copied something mid-burst: that
		// content is what the user expects back.
		if outstandingPastes == 0 || pasteboard.changeCount != lastWrittenChangeCount {
			snapshot = pasteboard.string(forType: .string)
		}
		outstandingPastes += 1
		pasteboard.clearContents()
		pasteboard.setString(text, forType: .string)
		lastWrittenChangeCount = pasteboard.changeCount
	}

	/// Call once the target app has had time to consume the paste.
	func endPaste() {
		guard outstandingPastes > 0 else { return }
		outstandingPastes -= 1
		guard outstandingPastes == 0 else { return }
		defer {
			snapshot = nil
			lastWrittenChangeCount = nil
		}
		guard pasteboard.changeCount == lastWrittenChangeCount, let snapshot else { return }
		pasteboard.clearContents()
		pasteboard.setString(snapshot, forType: .string)
	}
}
