import SwiftUI

/// Sheet for configuring a touchpad region mapping (one of the 4 quadrants).
/// Lets the user assign separate actions for touch and click, or the same action for both.
struct TouchpadRegionMappingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var profileManager: ProfileManager

    let region: TouchpadRegion

    /// Existing mappings already saved for this region (may include up to two:
    /// one for touch and one for click, or a single one with .both).
    let existingMappings: [TouchpadRegionMapping]

    @State private var touchSlot = ActionSlot()
    @State private var clickSlot = ActionSlot()
    @State private var showingKeyboard = false
    @State private var keyboardTarget: SlotKind = .click

    enum SlotKind { case touch, click }

    private var canSave: Bool {
        // Can save if at least one slot has a valid action, or if there are existing
        // mappings to clear (saving an all-None form removes the region's mappings).
        touchSlot.isValid || clickSlot.isValid || !existingMappings.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Configure Touchpad Region")
                    .font(.headline)

                HStack(spacing: 8) {
                    Image(systemName: "rectangle.split.2x2")
                        .font(.system(size: 18))
                        .foregroundColor(.accentColor)
                    Text(region.displayName)
                        .font(.title3.weight(.medium))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(8)

                slotEditor("On Touch", slot: $touchSlot, kind: .touch,
                           caption: "Fires the moment your finger lands in this quadrant")

                slotEditor("On Click", slot: $clickSlot, kind: .click,
                           caption: "Fires when you physically press the touchpad here")

                if showingKeyboard {
                    KeyboardVisualView(
                        selectedKeyCode: keyboardBinding.keyCode,
                        modifiers: keyboardBinding.modifiers
                    )
                }

                HStack {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .keyboardShortcut(.return, modifiers: .command)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
        .frame(width: 720, height: showingKeyboard ? 880 : 600)
        .onAppear { loadExisting() }
    }

    // MARK: - Slot editor

    @ViewBuilder
    private func slotEditor(_ title: String, slot: Binding<ActionSlot>, kind: SlotKind, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.bold())
                Spacer()
                Picker("Action type", selection: slot.kind) {
                    Text("None").tag(ActionSlot.Kind.none)
                    Text("Key").tag(ActionSlot.Kind.singleKey)
                    Text("Macro").tag(ActionSlot.Kind.macro)
                    Text("System").tag(ActionSlot.Kind.systemCommand)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 280)
                if slot.wrappedValue.kind == .singleKey {
                    Button {
                        keyboardTarget = kind
                        showingKeyboard.toggle()
                    } label: {
                        Image(systemName: showingKeyboard && keyboardTarget == kind
                              ? "keyboard.chevron.compact.down" : "keyboard")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
            }

            Text(caption)
                .font(.caption)
                .foregroundColor(.secondary)

            switch slot.wrappedValue.kind {
            case .none:
                EmptyView()
            case .singleKey:
                KeyCaptureField(keyCode: slot.keyCode, modifiers: slot.modifiers)
            case .macro:
                macroPicker(slot: slot)
            case .systemCommand:
                systemCommandEditor(slot: slot)
            }

            if slot.wrappedValue.kind != .none {
                HStack {
                    Text("Hint:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Optional label", text: slot.hint)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                }
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(8)
    }

    private var keyboardBinding: (keyCode: Binding<CGKeyCode?>, modifiers: Binding<ModifierFlags>) {
        switch keyboardTarget {
        case .touch: return ($touchSlot.keyCode, $touchSlot.modifiers)
        case .click: return ($clickSlot.keyCode, $clickSlot.modifiers)
        }
    }

    // MARK: - Macro / System command editors

    @ViewBuilder
    private func macroPicker(slot: Binding<ActionSlot>) -> some View {
        if let profile = profileManager.activeProfile,
           !profile.macros.isEmpty || !profileManager.sharedLibraryMacros.isEmpty {
            Picker("Macro", selection: slot.macroId) {
                Text("Select a macro...").tag(nil as UUID?)
                MacroPickerSections(
                    profileMacros: profile.macros,
                    sharedMacros: profileManager.sharedLibraryMacros
                )
            }
            .labelsHidden()
        } else {
            Text("No macros defined in this profile")
                .font(.caption)
                .italic()
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func systemCommandEditor(slot: Binding<ActionSlot>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Category", selection: slot.systemCommandCategory) {
                Text("App").tag(SystemCommandCategory.app)
                Text("Shell").tag(SystemCommandCategory.shell)
                Text("Link").tag(SystemCommandCategory.link)
            }
            .pickerStyle(.segmented)

            switch slot.wrappedValue.systemCommandCategory {
            case .app:
                AppSelectionButton(
                    bundleId: slot.wrappedValue.appBundleIdentifier,
                    showingPicker: slot.showingAppPicker
                )
                .sheet(isPresented: slot.showingAppPicker) {
                    SystemActionAppPickerSheet(
                        currentBundleIdentifier: slot.wrappedValue.appBundleIdentifier.isEmpty
                            ? nil : slot.wrappedValue.appBundleIdentifier
                    ) { app in
                        slot.wrappedValue.appBundleIdentifier = app.bundleIdentifier
                    }
                }
                Toggle("Open in new window (Cmd+N)", isOn: slot.appNewWindow)
                    .font(.caption)
            case .shell:
                TextField("Command", text: slot.shellCommand)
                    .textFieldStyle(.roundedBorder)
                Toggle("Run silently", isOn: Binding(
                    get: { !slot.wrappedValue.shellRunInTerminal },
                    set: { slot.wrappedValue.shellRunInTerminal = !$0 }
                ))
                .font(.caption)
            case .link:
                TextField("URL", text: slot.linkURL)
                    .textFieldStyle(.roundedBorder)
            default:
                Text("Unsupported")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Load / save

    private func loadExisting() {
        if let touch = existingMappings.first(where: { $0.triggerMode == .touch }) {
            touchSlot.load(from: touch)
        }
        if let click = existingMappings.first(where: { $0.triggerMode == .click }) {
            clickSlot.load(from: click)
        }
        if let both = existingMappings.first(where: { $0.triggerMode == .both }) {
            touchSlot.load(from: both)
            clickSlot.load(from: both)
        }
    }

    private func save() {
        guard var profile = profileManager.activeProfile else { return }
        profile.touchpadRegionMappings.removeAll { $0.region == region }

        let touchMapping = touchSlot.buildMapping(region: region, trigger: .touch)
        let clickMapping = clickSlot.buildMapping(region: region, trigger: .click)

        // If both slots produce identical actions, collapse to a single .both mapping.
        if let t = touchMapping, let c = clickMapping, t.matchesAction(c) {
            var merged = t
            merged.triggerMode = .both
            profile.touchpadRegionMappings.append(merged)
        } else {
            if let t = touchMapping { profile.touchpadRegionMappings.append(t) }
            if let c = clickMapping { profile.touchpadRegionMappings.append(c) }
        }

        profileManager.updateTouchpadRegionMappings(profile.touchpadRegionMappings)
        dismiss()
    }
}

// MARK: - Action slot model

/// Edit-time state for one action slot (touch or click).
struct ActionSlot {
    enum Kind: Int { case none, singleKey, macro, systemCommand }

    var kind: Kind = .none
    var keyCode: CGKeyCode?
    var modifiers = ModifierFlags()
    var macroId: UUID?
    var hint: String = ""

    // System command sub-state
    var systemCommandCategory: SystemCommandCategory = .app
    var appBundleIdentifier: String = ""
    var appNewWindow: Bool = false
    var shellCommand: String = ""
    var shellRunInTerminal: Bool = false
    var linkURL: String = ""
    var showingAppPicker: Bool = false

    var isValid: Bool {
        switch kind {
        case .none: return false
        case .singleKey: return keyCode != nil || modifiers.hasAny
        case .macro: return macroId != nil
        case .systemCommand: return buildSystemCommand() != nil
        }
    }

    mutating func load(from mapping: TouchpadRegionMapping) {
        hint = mapping.hint ?? ""
        if let cmd = mapping.systemCommand {
            kind = .systemCommand
            systemCommandCategory = cmd.category
            switch cmd {
            case .launchApp(let id, let newWindow):
                appBundleIdentifier = id
                appNewWindow = newWindow
            case .shellCommand(let c, let inTerm):
                shellCommand = c
                shellRunInTerminal = inTerm
            case .openLink(let url):
                linkURL = url
            default: break
            }
        } else if let id = mapping.macroId {
            kind = .macro
            macroId = id
        } else if mapping.keyCode != nil || mapping.modifiers.hasAny {
            kind = .singleKey
            keyCode = mapping.keyCode
            modifiers = mapping.modifiers
        } else {
            kind = .none
        }
    }

    func buildSystemCommand() -> SystemCommand? {
        switch systemCommandCategory {
        case .app:
            guard !appBundleIdentifier.isEmpty else { return nil }
            return .launchApp(bundleIdentifier: appBundleIdentifier, newWindow: appNewWindow)
        case .shell:
            guard !shellCommand.isEmpty else { return nil }
            return .shellCommand(command: shellCommand, inTerminal: shellRunInTerminal)
        case .link:
            guard !linkURL.isEmpty else { return nil }
            return .openLink(url: linkURL)
        default:
            return nil
        }
    }

    func buildMapping(region: TouchpadRegion, trigger: TouchpadTriggerMode) -> TouchpadRegionMapping? {
        guard isValid else { return nil }
        var mapping = TouchpadRegionMapping(region: region, triggerMode: trigger)
        mapping.hint = hint.isEmpty ? nil : hint
        switch kind {
        case .singleKey:
            mapping.keyCode = keyCode
            mapping.modifiers = modifiers
        case .macro:
            mapping.macroId = macroId
        case .systemCommand:
            mapping.systemCommand = buildSystemCommand()
        case .none:
            return nil
        }
        return mapping
    }
}

private extension TouchpadRegionMapping {
    /// Whether this mapping's action is identical to another's (ignoring trigger mode and hint).
    func matchesAction(_ other: TouchpadRegionMapping) -> Bool {
        return keyCode == other.keyCode
            && modifiers == other.modifiers
            && macroId == other.macroId
            && systemCommand == other.systemCommand
            && hint == other.hint
    }
}
