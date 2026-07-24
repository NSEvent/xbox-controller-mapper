import Foundation

enum CommandWheelActionResolutionPolicy {
	/// The highest-priority active layer owns the wheel. A nil override inherits
	/// the base wheel; an empty override intentionally disables it.
	static func resolve(profile: Profile, activeLayerIds: [UUID]) -> [CommandWheelAction] {
		guard let activeLayerId = activeLayerIds.last,
			  let layer = profile.layers.first(where: { $0.id == activeLayerId }) else {
			return profile.commandWheelActions
		}
		return layer.commandWheelActions ?? profile.commandWheelActions
	}
}
