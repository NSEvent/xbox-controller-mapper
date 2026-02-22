import SwiftUI

/// Tab content for managing gesture mappings and gyro aiming settings.
struct GesturesTab: View {
    @EnvironmentObject var profileManager: ProfileManager
    @Binding var editingGestureType: MotionGestureType?

    var body: some View {
        Form {
            Section {
                GestureListView(
                    gestureMappings: profileManager.activeProfile?.gestureMappings ?? [],
                    onEdit: { gestureType in
                        editingGestureType = gestureType
                    },
                    onClear: { gestureType in
                        if let mapping = profileManager.gestureMapping(for: gestureType) {
                            profileManager.removeGesture(mapping)
                        }
                    }
                )
            } header: {
                Text("Motion Gestures")
                    .foregroundColor(.secondary)
            } footer: {
                Text("Map quick tilt gestures on your DualSense controller to actions. Snap the controller top toward you (Tilt Back) or away from you (Tilt Forward).")
                    .foregroundColor(.secondary.opacity(0.7))
            }

            Section {
                Toggle("Gyro Aiming (Focus Mode)", isOn: Binding(
                    get: { profileManager.activeProfile?.joystickSettings.gyroAimingEnabled ?? false },
                    set: { newValue in
                        guard var settings = profileManager.activeProfile?.joystickSettings else { return }
                        settings.gyroAimingEnabled = newValue
                        profileManager.updateJoystickSettings(settings)
                    }
                ))

                if profileManager.activeProfile?.joystickSettings.gyroAimingEnabled == true {
                    HStack {
                        Text("Sensitivity")
                        Slider(value: Binding(
                            get: { profileManager.activeProfile?.joystickSettings.gyroAimingSensitivity ?? 0.3 },
                            set: { newValue in
                                guard var settings = profileManager.activeProfile?.joystickSettings else { return }
                                settings.gyroAimingSensitivity = newValue
                                profileManager.updateJoystickSettings(settings)
                            }
                        ), in: 0.0...1.0)
                    }
                }
            } header: {
                Text("Gyro Aiming")
                    .foregroundColor(.secondary)
            } footer: {
                Text("Tilt the controller to move the mouse cursor while in focus mode. Uses the DualSense gyroscope for fine-grained aiming.")
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding()
    }
}
