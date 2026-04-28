import Foundation
import SwiftUI

@MainActor
extension ProfileManager {
    @discardableResult
    private func mutateActiveCommandWheelActions(
        _ mutate: (inout [CommandWheelAction]) -> Bool
    ) -> Bool {
        guard var profile = activeProfile else { return false }
        let didChange = mutate(&profile.commandWheelActions)
        if didChange {
            updateProfile(profile)
        }
        return didChange
    }

    // MARK: - Command Wheel Actions

    func addCommandWheelAction(_ action: CommandWheelAction) {
        mutateActiveCommandWheelActions { actions in
            actions.append(action)
            return true
        }
    }

    func removeCommandWheelAction(_ action: CommandWheelAction) {
        mutateActiveCommandWheelActions { actions in
            actions.removeAll { $0.id == action.id }
            return true
        }
    }

    func updateCommandWheelAction(_ action: CommandWheelAction) {
        mutateActiveCommandWheelActions { actions in
            guard let index = actions.firstIndex(where: { $0.id == action.id }) else {
                return false
            }
            actions[index] = action
            return true
        }
    }

    func moveCommandWheelActions(from source: IndexSet, to destination: Int) {
        mutateActiveCommandWheelActions { actions in
            actions.move(fromOffsets: source, toOffset: destination)
            return true
        }
    }
}
