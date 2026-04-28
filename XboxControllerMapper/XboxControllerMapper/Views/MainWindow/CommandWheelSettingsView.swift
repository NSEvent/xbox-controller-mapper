import SwiftUI

/// Settings tab for configuring the standalone command wheel
struct CommandWheelSettingsView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @State private var selectedItemId: UUID?
    @State private var showingAddSheet = false
    @State private var editingAction: CommandWheelAction?

    private var actions: [CommandWheelAction] {
        profileManager.activeProfile?.commandWheelActions ?? []
    }

    private let maxItems = 12

    var body: some View {
        Form {
            // Info Section
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Map any button to **Command Wheel** (with Hold enabled) to activate.")
                            .fontWeight(.medium)
                        Text("Hold the button and use the right stick to select an action.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            // Wheel Preview
            Section {
                HStack {
                    Spacer()
                    CommandWheelEditorView(
                        items: actions,
                        selectedItemId: $selectedItemId,
                        onItemTapped: { action in
                            editingAction = action
                        },
                        onMoveItem: { source, destination in
                            profileManager.moveCommandWheelActions(from: source, to: destination)
                        }
                    )
                    .frame(width: 350, height: 350)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } header: {
                Text("Wheel Preview")
            }

            // Action List
            Section {
                if actions.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "circle.dotted")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("No actions configured")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("Add actions to build your command wheel")
                                .font(.caption)
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                        .padding(.vertical, 16)
                        Spacer()
                    }
                } else {
                    ForEach(actions) { action in
                        CommandWheelActionRow(
                            action: action,
                            isSelected: selectedItemId == action.id,
                            onEdit: { editingAction = action },
                            onDelete: { profileManager.removeCommandWheelAction(action) }
                        )
                        .onTapGesture {
                            selectedItemId = action.id
                            editingAction = action
                        }
                    }
                }

                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add Action", systemImage: "plus.circle")
                }
                .disabled(actions.count >= maxItems)
                .help(actions.count >= maxItems ? "Maximum \(maxItems) actions" : "")
            } header: {
                HStack {
                    Text("Actions")
                    Spacer()
                    Text("\(actions.count)/\(maxItems)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingAddSheet) {
            CommandWheelActionSheet(
                action: nil,
                onSave: { newAction in
                    profileManager.addCommandWheelAction(newAction)
                    selectedItemId = newAction.id
                }
            )
            .environmentObject(profileManager)
        }
        .sheet(item: $editingAction) { action in
            CommandWheelActionSheet(
                action: action,
                onSave: { updatedAction in
                    profileManager.updateCommandWheelAction(updatedAction)
                }
            )
            .environmentObject(profileManager)
        }
    }
}

// MARK: - Action Row

struct CommandWheelActionRow: View {
    let action: CommandWheelAction
    let isSelected: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false
    @State private var cachedIcon: NSImage?

    var body: some View {
        HStack(spacing: 8) {
            // Icon
            actionIcon
                .frame(width: 24, height: 24)
                .foregroundColor(.accentColor)

            // Name and action type
            VStack(alignment: .leading, spacing: 2) {
                Text(action.displayName.isEmpty ? "Unnamed" : action.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(action.actionDisplayString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Action type badge
            actionTypeBadge
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(badgeColor.opacity(0.15))
                .foregroundColor(badgeColor)
                .cornerRadius(4)

            // Edit button
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)

            // Delete button
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : (isHovered ? Color.primary.opacity(0.05) : Color.clear))
        )
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
        .onAppear { cachedIcon = action.resolvedIcon() }
        .onChange(of: action) { cachedIcon = action.resolvedIcon() }
    }

    @ViewBuilder
    private var actionIcon: some View {
        if let icon = cachedIcon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: action.defaultIconName)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }

    @ViewBuilder
    private var actionTypeBadge: some View {
        switch action.effectiveActionType {
        case .keyPress: Text("Key")
        case .macro: Text("Macro")
        case .script: Text("Script")
        case .systemCommand: Text("System")
        case .none: Text("None")
        }
    }

    private var badgeColor: Color {
        switch action.effectiveActionType {
        case .keyPress: return .blue
        case .macro: return .purple
        case .script: return .orange
        case .systemCommand: return .green
        case .none: return .gray
        }
    }
}

#Preview {
    CommandWheelSettingsView()
}
