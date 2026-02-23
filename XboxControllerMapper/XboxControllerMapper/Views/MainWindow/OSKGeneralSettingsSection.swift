import SwiftUI

/// Info section shown at the top of on-screen keyboard settings:
/// explains how to show the keyboard and provides the toggle shortcut setting.
struct OSKInfoSection: View {
    @EnvironmentObject var profileManager: ProfileManager

    var body: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 4) {
                    Text("To show the on-screen keyboard widget, assign a button to toggle it.")
                        .fontWeight(.medium)
                    Text("Go to the Buttons tab, add a command, select \"Show Keyboard\", then choose \"Keyboard\".")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)

            HStack {
                Text("Toggle Shortcut")
                Spacer()
                KeyCaptureField(
                    keyCode: Binding<CGKeyCode?>(
                        get: { profileManager.onScreenKeyboardSettings.toggleShortcutKeyCode.map { CGKeyCode($0) } },
                        set: { newValue in
                            var settings = profileManager.onScreenKeyboardSettings
                            settings.toggleShortcutKeyCode = newValue.map { UInt16($0) }
                            profileManager.updateOnScreenKeyboardSettings(settings)
                        }
                    ),
                    modifiers: Binding<ModifierFlags>(
                        get: { profileManager.onScreenKeyboardSettings.toggleShortcutModifiers },
                        set: { newValue in
                            var settings = profileManager.onScreenKeyboardSettings
                            settings.toggleShortcutModifiers = newValue
                            profileManager.updateOnScreenKeyboardSettings(settings)
                        }
                    )
                )
                .frame(width: 200)
            }
        }
    }
}

/// General settings sections for the on-screen keyboard: app switching,
/// command wheel, and keyboard layout. Placed after the content sections.
struct OSKGeneralSettingsSection: View {
    @EnvironmentObject var profileManager: ProfileManager

    var body: some View {
        // App Switching Section
        appSwitchingSection

        // Command Wheel Section
        commandWheelSection

        // Keyboard Layout Section
        keyboardLayoutSection
    }

    // MARK: - App Switching Section

    private var appSwitchingSection: some View {
        Section("App Switching") {
            Toggle(isOn: Binding(
                get: { profileManager.onScreenKeyboardSettings.activateAllWindows },
                set: { newValue in
                    var settings = profileManager.onScreenKeyboardSettings
                    settings.activateAllWindows = newValue
                    profileManager.updateOnScreenKeyboardSettings(settings)
                }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Activate All Windows")
                    Text("When switching to an app, bring all of its windows to the front.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Command Wheel Section

    private var commandWheelSection: some View {
        Section("Command Wheel") {
            Toggle(isOn: Binding(
                get: { profileManager.onScreenKeyboardSettings.wheelShowsWebsites },
                set: { newValue in
                    var settings = profileManager.onScreenKeyboardSettings
                    settings.wheelShowsWebsites = newValue
                    profileManager.updateOnScreenKeyboardSettings(settings)
                }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Show Websites in Wheel")
                    Text("Command wheel shows website links instead of apps.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Picker(selection: Binding(
                get: { wheelAlternateModifierSelection },
                set: { newValue in
                    var settings = profileManager.onScreenKeyboardSettings
                    settings.wheelAlternateModifiers = modifierFlagsForSelection(newValue)
                    profileManager.updateOnScreenKeyboardSettings(settings)
                }
            )) {
                Text("None").tag("none")
                Text("\u{2318} Command").tag("command")
                Text("\u{2325} Option").tag("option")
                Text("\u{21E7} Shift").tag("shift")
                Text("\u{2303} Control").tag("control")
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Alternate Modifier")
                    Text("Hold this key to show \(profileManager.onScreenKeyboardSettings.wheelShowsWebsites ? "apps" : "websites") instead on the command wheel.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var wheelAlternateModifierSelection: String {
        let mods = profileManager.onScreenKeyboardSettings.wheelAlternateModifiers
        if mods.command { return "command" }
        if mods.option { return "option" }
        if mods.shift { return "shift" }
        if mods.control { return "control" }
        return "none"
    }

    private func modifierFlagsForSelection(_ selection: String) -> ModifierFlags {
        switch selection {
        case "command": return ModifierFlags(command: true)
        case "option": return ModifierFlags(option: true)
        case "shift": return ModifierFlags(shift: true)
        case "control": return ModifierFlags(control: true)
        default: return ModifierFlags()
        }
    }

    // MARK: - Keyboard Layout Section

    private var keyboardLayoutSection: some View {
        Section("Keyboard Layout") {
            Toggle(isOn: Binding(
                get: { profileManager.onScreenKeyboardSettings.showExtendedFunctionKeys },
                set: { newValue in
                    var settings = profileManager.onScreenKeyboardSettings
                    settings.showExtendedFunctionKeys = newValue
                    profileManager.updateOnScreenKeyboardSettings(settings)
                }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Show F13-F20 Keys")
                    Text("Display extended function keys (F13-F20) in a row above F1-F12.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
