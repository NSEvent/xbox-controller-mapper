import SwiftUI
import TriggerKitCore
import TriggerKitUI

struct MacroListView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @State private var editingMacro: Macro?
    @State private var showingAddSheet = false
    @State private var showingSharedLibrarySheet = false

    var body: some View {
        Form {
            Section {
                Button(action: { showingAddSheet = true }) {
                    Label("Add New Macro", systemImage: "plus")
                        .fontWeight(.medium)
                }
                .padding(.vertical, 4)

                if let profile = profileManager.activeProfile {
                    if profile.macros.isEmpty {
                        Text("No macros defined")
                            .foregroundColor(.secondary)
                            .italic()
                            .padding()
                    } else {
                        List {
                            ForEach(profile.macros) { macro in
                                MacroRow(macro: macro, onEdit: {
                                    editingMacro = macro
                                }, onDelete: {
                                    profileManager.removeMacro(macro)
                                })
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                                .background(GlassCardBackground())
                            }
                            .onMove { source, dest in
                                profileManager.moveMacros(from: source, to: dest)
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            } header: {
                Text("Macros")
                    .foregroundColor(.secondary)
            } footer: {
                Text("Macros allow you to execute a sequence of actions (keys, text, delays) with a single button press.")
                    .foregroundColor(.secondary.opacity(0.7))
            }

            Section {
                Button(action: { showingSharedLibrarySheet = true }) {
                    Label("Manage Shared Library...", systemImage: "books.vertical")
                        .fontWeight(.medium)
                }
                .padding(.vertical, 4)

                if profileManager.sharedLibraryMacros.isEmpty {
                    Text("No shared macros yet")
                        .foregroundColor(.secondary)
                        .italic()
                        .padding()
                } else {
                    List {
                        ForEach(profileManager.sharedLibraryMacros) { macro in
                            SharedMacroRow(macro: macro, onEdit: {
                                showingSharedLibrarySheet = true
                            })
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                            .background(GlassCardBackground())
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            } header: {
                Text("Shared Library")
                    .foregroundColor(.secondary)
            } footer: {
                Text("Shared macros live in the TriggerKit library and are usable from ControllerKeys, TriggerKit.app, and other TriggerKit apps. Assign one to a button from any macro picker — profiles keep a snapshot so bindings survive library edits.")
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding()
        .sheet(isPresented: $showingAddSheet) {
            MacroEditorSheet(macro: nil)
        }
        .sheet(item: $editingMacro) { macro in
            MacroEditorSheet(macro: macro)
        }
        .sheet(isPresented: $showingSharedLibrarySheet) {
            SharedMacroLibrarySheet()
                .environmentObject(profileManager)
        }
    }
}

/// Hosts TriggerKitUI's shared macro library editor in a sheet.
struct SharedMacroLibrarySheet: View {
    @EnvironmentObject var profileManager: ProfileManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Shared Macro Library")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            AutomationMacroLibraryView(store: profileManager.sharedMacroStore)
        }
        .frame(minWidth: 760, minHeight: 480)
    }
}

struct SharedMacroRow: View {
    let macro: TriggerKitCore.AutomationMacro
    var onEdit: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "books.vertical")
                .foregroundColor(.white.opacity(0.3))
                .font(.caption)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(macro.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))

                Text(macro.program.steps.count == 1 ? "1 step" : "\(macro.program.steps.count) steps")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.borderless)
            .help("Edit in shared library")
            .accessibilityLabel("Edit in shared library")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .hoverableRow()
    }
}

struct MacroRow: View {
    let macro: Macro
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack {
            // Drag handle - not tappable, allows List drag to work
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.white.opacity(0.3))
                .font(.caption)
                .frame(width: 20)
                .accessibilityHidden(true)

            // Tappable content area
            HStack {
                Image(systemName: "checklist")
                    .foregroundColor(.white.opacity(0.3))
                    .font(.caption)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(macro.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))

                    Text("\(macro.steps.count) steps")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                }

                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture { onEdit() }

            HStack(spacing: 12) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.borderless)
                .help("Edit")
                .accessibilityLabel("Edit")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.borderless)
                .help("Delete")
                .accessibilityLabel("Delete")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .hoverableRow()
    }
}
