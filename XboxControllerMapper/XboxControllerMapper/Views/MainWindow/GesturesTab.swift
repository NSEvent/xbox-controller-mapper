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
                Text("Map quick tilt gestures on a supported controller to actions. Snap the controller top toward you (Tilt Back) or away from you (Tilt Forward).")
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
                Toggle("Gyro Aiming", isOn: Binding(
                    get: { profileManager.activeProfile?.joystickSettings.gyroAimingEnabled ?? false },
                    set: { newValue in
                        guard var settings = profileManager.activeProfile?.joystickSettings else { return }
                        settings.gyroAimingEnabled = newValue
                        profileManager.updateJoystickSettings(settings)
                    }
                ))

                if profileManager.activeProfile?.joystickSettings.gyroAimingEnabled == true {
                    Picker("Activation", selection: Binding(
                        get: { profileManager.activeProfile?.joystickSettings.gyroActivationMode ?? .focusModifier },
                        set: { newValue in
                            guard var settings = profileManager.activeProfile?.joystickSettings else { return }
                            settings.gyroActivationMode = newValue
                            profileManager.updateJoystickSettings(settings)
                        }
                    )) {
                        ForEach(GyroActivationMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(activationModeDescription)
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.8))

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
                }
                .foregroundColor(.secondary)
            } footer: {
                Text("Tilt the controller to move the mouse cursor. Map any button to the Gyro Toggle, Gyro Hold, or Gyro Pause actions (in the button mapping keyboard, next to the special actions) — they control gyro without sending any keystrokes. Tip: on DualSense, the mute button makes a great Gyro Pause for repositioning.")
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding()
    }

    private var activationModeDescription: String {
        switch profileManager.activeProfile?.joystickSettings.gyroActivationMode ?? .focusModifier {
        case .focusModifier:
            return String(localized: "Gyro aims while the focus-mode modifier is held (legacy behavior).")
        case .alwaysOn:
            return String(localized: "Gyro always moves the cursor. Bind Gyro Pause to a button to reposition without moving the cursor (ratcheting).")
        case .gyroButton:
            return String(localized: "Gyro moves the cursor only via Gyro Toggle / Gyro Hold button bindings.")
        }
    }

}
