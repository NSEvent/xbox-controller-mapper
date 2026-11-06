import Foundation

@MainActor
extension ProfileManager {
	/// Copies one controller's mappings from `source` into the profile with
	/// `destinationId`. Snapshots the configuration first so the copy can be
	/// rolled back from Settings → Snapshots. Returns the applied plan, or nil
	/// when the destination is missing or nothing would change.
	@discardableResult
	func copyControllerMappings(
		from source: Profile,
		to destinationId: UUID,
		buttons: Set<ControllerButton>,
		controllerName: String,
		options: ControllerMappingTransferOptions
	) -> ControllerMappingTransferPlan? {
		guard destinationId != source.id,
			  let destination = profiles.first(where: { $0.id == destinationId }) else { return nil }

		let plan = ControllerMappingTransfer.plan(from: source, to: destination, buttons: buttons, options: options)
		guard plan.hasChanges else { return nil }

		snapshotCurrentState(reason: "Before copying \(controllerName) mappings from \(source.name) to \(destination.name)")
		updateProfile(plan.result)
		return plan
	}
}
