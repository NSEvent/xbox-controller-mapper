import Foundation
import CoreGraphics

extension ControllerService {
	/// After hot-plug, GameController can leave the unused second touch at a
	/// nonzero idle coordinate (observed: -1, 1) without a later zero callback.
	/// That latched contact suppresses every primary mouse delta. Full raw HID
	/// reports keep arriving and tell us whether two fingers really exist.
	///
	/// Use the contact count, not a timeout: a real stationary second finger
	/// also stops producing axis changes. If HID isn't available, retain the
	/// existing GameController behavior rather than guessing a release.
	nonisolated func reconcileDualSenseSecondaryTouch() {
		let endedGesture: TouchpadGesture? = storage.lock.withLock {
			let now = CFAbsoluteTimeGetCurrent()
			guard storage.isDualSense,
			      let count = storage.dualSenseTouchpadContactCount, count < 2,
			      storage.isTouchpadSecondaryTouching,
			      now - storage.touchpadSecondaryLastTouchTime >= Config.touchpadSecondaryStaleInterval,
			      now - storage.dualSenseTouchpadContactTime < Config.touchpadSecondaryStaleInterval else { return nil }
			// GC and HID callbacks arrive on different queues. Only reconcile
			// an old axis state against fresh hardware evidence, never reject a
			// new finger using the previous frame's no-contact report.

			storage.isTouchpadSecondaryTouching = false
			storage.touchpadSecondaryPosition = .zero
			storage.touchpadSecondaryPreviousPosition = .zero
			storage.touchpadSecondaryFramesSinceTouch = 0
			storage.touchpadSecondaryLastUpdate = 0
			storage.touchpadSecondaryLastTouchTime = 0
			storage.touchpadGestureHasCenter = false
			storage.touchpadGesturePreviousCenter = .zero
			storage.touchpadGesturePreviousDistance = 0
			// Preserve two-finger tap/click history: a held click must release
			// the same button even when its second finger has since lifted.
			return TouchpadGesture(
				centerDelta: .zero, distanceDelta: 0,
				isPrimaryTouching: storage.isTouchpadTouching,
				isSecondaryTouching: false
			)
		}
		if let endedGesture {
			// End the engine's gesture latch before enqueueing mouse movement.
			emitInputEvent(.touchpadGesture(endedGesture))
			NSLog("[ControllerKeys] Recovered stale DualSense secondary touch from HID contact count")
		}
	}
}
