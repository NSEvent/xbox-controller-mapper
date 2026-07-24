import Foundation
import SwiftUI

@MainActor
extension ProfileManager {
    @discardableResult
    private func mutateActiveCommandWheelActions(
		layerId: UUID?,
        _ mutate: (inout [CommandWheelAction]) -> Bool
    ) -> Bool {
        guard var profile = activeProfile else { return false }

		let didChange: Bool
		if let layerId {
			guard let layerIndex = profile.layers.firstIndex(where: { $0.id == layerId }) else {
				return false
			}
			var actions = profile.layers[layerIndex].commandWheelActions ?? profile.commandWheelActions
			didChange = mutate(&actions)
			if didChange {
				profile.layers[layerIndex].commandWheelActions = actions
			}
		} else {
			didChange = mutate(&profile.commandWheelActions)
		}

        if didChange {
            updateProfile(profile)
        }
        return didChange
    }

    // MARK: - Command Wheel Actions

    func commandWheelActions(layerId: UUID?) -> [CommandWheelAction] {
		guard let profile = activeProfile else { return [] }
		guard let layerId,
			  let layer = profile.layers.first(where: { $0.id == layerId }) else {
			return profile.commandWheelActions
		}
		return layer.commandWheelActions ?? profile.commandWheelActions
    }

    func layerCommandWheelInheritsBase(layerId: UUID) -> Bool {
		activeProfile?.layers.first(where: { $0.id == layerId })?.commandWheelActions == nil
    }

    func setLayerCommandWheelInheritsBase(_ inheritsBase: Bool, layerId: UUID) {
		guard var profile = activeProfile,
			  let layerIndex = profile.layers.firstIndex(where: { $0.id == layerId }) else {
			return
		}

		if inheritsBase {
			profile.layers[layerIndex].commandWheelActions = nil
		} else if profile.layers[layerIndex].commandWheelActions == nil {
			profile.layers[layerIndex].commandWheelActions = profile.commandWheelActions
		} else {
			return
		}
		updateProfile(profile)
    }

    func addCommandWheelAction(_ action: CommandWheelAction, layerId: UUID? = nil) {
		mutateActiveCommandWheelActions(layerId: layerId) { actions in
            actions.append(action)
            return true
        }
    }

    func removeCommandWheelAction(_ action: CommandWheelAction, layerId: UUID? = nil) {
		mutateActiveCommandWheelActions(layerId: layerId) { actions in
            actions.removeAll { $0.id == action.id }
            return true
        }
    }

    func updateCommandWheelAction(_ action: CommandWheelAction, layerId: UUID? = nil) {
		mutateActiveCommandWheelActions(layerId: layerId) { actions in
            guard let index = actions.firstIndex(where: { $0.id == action.id }) else {
                return false
            }
            actions[index] = action
            return true
        }
    }

    func moveCommandWheelActions(from source: IndexSet, to destination: Int, layerId: UUID? = nil) {
		mutateActiveCommandWheelActions(layerId: layerId) { actions in
            actions.move(fromOffsets: source, toOffset: destination)
            return true
        }
    }
}
