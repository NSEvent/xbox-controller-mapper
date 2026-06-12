import SwiftUI
import TriggerKitCore

/// Shared body for macro `Picker`s: the active profile's macros followed by
/// shared TriggerKit library macros. Both sections tag by macro UUID, so a
/// binding's `macroId` works identically for either source — resolution at
/// execution time checks the profile first, then the shared library.
struct MacroPickerSections: View {
    let profileMacros: [Macro]
    let sharedMacros: [AutomationMacro]

    var body: some View {
        if !profileMacros.isEmpty && !sharedMacros.isEmpty {
            Section("Profile Macros") {
                profileItems
            }
            Section("Shared Library") {
                sharedItems
            }
        } else {
            profileItems
            sharedItems
        }
    }

    private var profileItems: some View {
        ForEach(profileMacros) { macro in
            Text(macro.name).tag(macro.id as UUID?)
        }
    }

    private var sharedItems: some View {
        ForEach(sharedMacros) { macro in
            Text(macro.name).tag(macro.id as UUID?)
        }
    }
}
