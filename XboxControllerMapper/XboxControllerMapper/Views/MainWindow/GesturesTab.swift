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
                HStack(spacing: 6) {
                    Text("Motion Gestures")
                    betaBadge
                }
                .foregroundColor(.secondary)
            } footer: {
                Text("Map quick tilt gestures on your DualSense controller to actions. Snap the controller top toward you (Tilt Back) or away from you (Tilt Forward).")
                    .foregroundColor(.secondary.opacity(0.7))
            }

            Section {
                SliderRow(
                    label: "Sensitivity",
                    value: Binding(
                        get: { profileManager.activeProfile?.joystickSettings.gestureSensitivity ?? 0.5 },
                        set: { newValue in
                            guard var settings = profileManager.activeProfile?.joystickSettings else { return }
                            settings.gestureSensitivity = newValue
                            profileManager.updateJoystickSettings(settings)
                        }
                    ),
                    range: 0...1.0,
                    description: "How easily gestures trigger"
                )

                SliderRow(
                    label: "Cooldown",
                    value: Binding(
                        get: { profileManager.activeProfile?.joystickSettings.gestureCooldown ?? 0.5 },
                        set: { newValue in
                            guard var settings = profileManager.activeProfile?.joystickSettings else { return }
                            settings.gestureCooldown = newValue
                            profileManager.updateJoystickSettings(settings)
                        }
                    ),
                    range: 0...1.0,
                    description: "Wait time between gestures"
                )
            } header: {
                Text("Gesture Detection")
                    .foregroundColor(.secondary)
            } footer: {
                Text("Adjust sensitivity to control how hard you need to snap the controller. Adjust cooldown to control the wait time before another gesture can fire.")
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
                    SliderRow(
                        label: "Sensitivity",
                        value: Binding(
                            get: { profileManager.activeProfile?.joystickSettings.gyroAimingSensitivity ?? 0.3 },
                            set: { newValue in
                                guard var settings = profileManager.activeProfile?.joystickSettings else { return }
                                settings.gyroAimingSensitivity = newValue
                                profileManager.updateJoystickSettings(settings)
                            }
                        ),
                        range: 0...1.0,
                        description: "Cursor speed from gyro tilt"
                    )

                    SliderRow(
                        label: "Deadzone",
                        value: Binding(
                            get: { profileManager.activeProfile?.joystickSettings.gyroAimingDeadzone ?? 0.3 },
                            set: { newValue in
                                guard var settings = profileManager.activeProfile?.joystickSettings else { return }
                                settings.gyroAimingDeadzone = newValue
                                profileManager.updateJoystickSettings(settings)
                            }
                        ),
                        range: 0...1.0,
                        description: "Filter hand tremor (rad/s threshold)"
                    )
                }
            } header: {
                HStack(spacing: 6) {
                    Text("Gyro Aiming")
                    betaBadge
                }
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

    private var betaBadge: some View {
        Text("Beta")
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.blue.opacity(0.2))
            .foregroundColor(.blue)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
