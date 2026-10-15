import CoreGraphics
import Foundation

/// The tap resource is injectable so lifecycle tests can use an owned run-loop
/// source without Accessibility access or intercepting desktop input.
nonisolated protocol HeldModifierEventTap: Sendable {
	var runLoopSource: CFRunLoopSource { get }
	func setEnabled(_ enabled: Bool)
	func invalidate()
}

nonisolated final class QuartzHeldModifierEventTap: HeldModifierEventTap, @unchecked Sendable {
	private let port: CFMachPort
	let runLoopSource: CFRunLoopSource

	init?(mask: CGEventMask, context: UnsafeMutableRawPointer) {
		guard let port = CGEvent.tapCreate(
			tap: .cgSessionEventTap,
			place: .headInsertEventTap,
			options: .defaultTap,
			eventsOfInterest: mask,
			callback: heldModifierPointerEventTapCallback,
			userInfo: context
		) else { return nil }
		guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
			CFMachPortInvalidate(port)
			return nil
		}
		self.port = port
		self.runLoopSource = source
	}

	func setEnabled(_ enabled: Bool) {
		CGEvent.tapEnable(tap: port, enable: enabled)
	}

	func invalidate() {
		CFMachPortInvalidate(port)
	}
}
