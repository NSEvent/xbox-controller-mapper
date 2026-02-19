import SwiftUI

struct StreamDeckImportSheet: View {
    @EnvironmentObject var profileManager: ProfileManager
    @Environment(\.dismiss) private var dismiss

    let fileURL: URL

    @State private var mappedActions: [MappedAction] = []
    @State private var profileName: String = ""
    @State private var selectedActionId: UUID?
    @State private var isParsing = true
    @State private var parseError: String?

    private var supportedCount: Int {
        mappedActions.filter { $0.isSupported && $0.assignedButton != nil }.count
    }

    private var unsupportedCount: Int {
        mappedActions.filter { !$0.isSupported }.count
    }

    private var totalCount: Int {
        mappedActions.count
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if isParsing {
                Spacer()
                ProgressView("Parsing Stream Deck profile...")
                Spacer()
            } else if let error = parseError {
                errorView(error)
            } else {
                content
            }

            Divider()
            footer
        }
        .frame(width: 750, height: 550)
        .onAppear {
            parseFile()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            TextField("Profile Name", text: $profileName)
                .textFieldStyle(.plain)
                .font(.headline)
                .frame(maxWidth: 300)

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .keyboardShortcut(.cancelAction)
        }
        .padding()
    }

    // MARK: - Content

    private var content: some View {
        HSplitView {
            actionList
                .frame(minWidth: 300, idealWidth: 350, maxWidth: 400)

            detailPanel
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Action List

    private var actionList: some View {
        List(selection: $selectedActionId) {
            ForEach(mappedActions) { action in
                ActionRow(action: action)
                    .tag(action.id)
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Detail Panel

    private var detailPanel: some View {
        Group {
            if let selectedId = selectedActionId,
               let actionIndex = mappedActions.firstIndex(where: { $0.id == selectedId }) {
                let action = mappedActions[actionIndex]
                VStack(alignment: .leading, spacing: 16) {
                    // Title
                    Text(action.streamDeckAction.title ?? action.streamDeckAction.name)
                        .font(.title3)
                        .fontWeight(.semibold)

                    // Type
                    HStack {
                        Text("Type:")
                            .foregroundColor(.secondary)
                        Text(actionTypeName(action.streamDeckAction.settings))
                    }

                    // Description
                    HStack(alignment: .top) {
                        Text("Action:")
                            .foregroundColor(.secondary)
                        Text(action.displayDescription)
                            .textSelection(.enabled)
                    }

                    if action.isSupported {
                        // Button assignment picker
                        HStack {
                            Text("Assign to:")
                                .foregroundColor(.secondary)
                            Picker("", selection: buttonBinding(for: actionIndex)) {
                                Text("Unassigned").tag(nil as ControllerButton?)
                                ForEach(availableButtons(for: actionIndex), id: \.self) { button in
                                    Text(button.displayName).tag(button as ControllerButton?)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 200)
                        }
                    } else {
                        // Unsupported explanation
                        HStack(alignment: .top) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            Text("This action cannot be imported because it uses an unsupported Stream Deck plugin.")
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 4)
                    }

                    Spacer()
                }
                .padding()
            } else {
                VStack {
                    Spacer()
                    Text("Select an action to view details")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("\(supportedCount) of \(totalCount) actions will be imported")
                .foregroundColor(.secondary)
                .font(.caption)
            if unsupportedCount > 0 {
                Text("(\(unsupportedCount) unsupported)")
                    .foregroundColor(.orange)
                    .font(.caption)
            }

            Spacer()

            Button("Import") {
                importProfile()
            }
            .buttonStyle(.borderedProminent)
            .disabled(supportedCount == 0)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundColor(.orange)
            Text(error)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    // MARK: - Actions

    private func parseFile() {
        isParsing = true
        parseError = nil

        do {
            let manifest = try StreamDeckProfileParser.parse(fileURL: fileURL)
            profileName = manifest.name
            mappedActions = StreamDeckImportMapper.mapActions(manifest.actions)
            // Auto-select first action
            selectedActionId = mappedActions.first?.id
            isParsing = false
        } catch {
            parseError = error.localizedDescription
            isParsing = false
        }
    }

    private func importProfile() {
        let profile = StreamDeckImportMapper.buildProfile(
            name: profileName,
            mappedActions: mappedActions
        )
        let imported = profileManager.importStreamDeckProfile(profile)
        profileManager.setActiveProfile(imported)
        dismiss()
    }

    // MARK: - Helpers

    private func buttonBinding(for index: Int) -> Binding<ControllerButton?> {
        Binding(
            get: { mappedActions[index].assignedButton },
            set: { newValue in
                // If this button is already assigned to another action, unassign it
                if let button = newValue {
                    for i in mappedActions.indices where i != index {
                        if mappedActions[i].assignedButton == button {
                            mappedActions[i].assignedButton = nil
                        }
                    }
                }
                mappedActions[index].assignedButton = newValue
            }
        )
    }

    private func availableButtons(for index: Int) -> [ControllerButton] {
        let usedButtons = Set(
            mappedActions.enumerated()
                .filter { $0.offset != index }
                .compactMap { $0.element.assignedButton }
        )
        // Include current assignment + all unassigned buttons
        return StreamDeckImportMapper.assignmentOrder.filter { button in
            !usedButtons.contains(button) || mappedActions[index].assignedButton == button
        }
    }

    private func actionTypeName(_ settings: StreamDeckActionSettings) -> String {
        switch settings {
        case .hotkey: return "Hotkey"
        case .openApp: return "Open Application"
        case .website: return "Website"
        case .multiAction: return "Multi-Action"
        case .text: return "Text"
        case .unsupported: return "Unsupported"
        }
    }
}

// MARK: - Action Row

private struct ActionRow: View {
    let action: MappedAction

    var body: some View {
        HStack(spacing: 8) {
            // Type indicator
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(action.streamDeckAction.title ?? action.streamDeckAction.name)
                    .font(.system(size: 13))
                    .lineLimit(1)

                Text(action.displayDescription)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let button = action.assignedButton {
                Text(button.shortLabel)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15))
                    .cornerRadius(4)
            } else if action.isSupported {
                Text("Unassigned")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .opacity(action.isSupported ? 1.0 : 0.5)
    }

    private var dotColor: Color {
        switch action.importResult {
        case .directKey: return .green
        case .macro(let macro):
            if macro.steps.count == 1 {
                switch macro.steps[0] {
                case .openApp, .openLink: return .blue
                case .typeText: return .purple
                default: return .purple
                }
            }
            return .purple
        case .unsupported: return .gray
        }
    }
}
