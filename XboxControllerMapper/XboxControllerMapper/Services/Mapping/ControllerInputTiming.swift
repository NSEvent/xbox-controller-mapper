import Foundation

/// Internal metadata; the public event callback still sees resolved events only.
nonisolated enum ControllerInputTiming: Sendable {
	case physicalPressBegan(CFAbsoluteTime)
	case resolved(CFAbsoluteTime)
	case chordResolved([ControllerButton: CFAbsoluteTime])

	var resolvedTime: CFAbsoluteTime? {
		if case .resolved(let time) = self { return time }
		return nil
	}
}

nonisolated struct PhysicalTapPress: Sendable {
	let resolvedButton: ControllerButton
	let time: CFAbsoluteTime
}

typealias TimedControllerInputHandler = (ControllerInputEvent, ControllerInputTiming?) -> Void
