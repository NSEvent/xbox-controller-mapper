import Foundation

enum AppLayerActivationPolicy {
	static func resolve(
		bundleId: String?,
		controllerKeysBundleId: String?,
		profile: Profile?
	) -> UUID? {
		guard let bundleId,
			  bundleId != controllerKeysBundleId,
			  let profile,
			  let layerId = profile.appLayerBindings[bundleId],
			  profile.layers.contains(where: { $0.id == layerId }) else {
			return nil
		}
		return layerId
	}
}
