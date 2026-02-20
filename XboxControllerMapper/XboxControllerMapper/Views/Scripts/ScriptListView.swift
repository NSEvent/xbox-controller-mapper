import SwiftUI

struct ScriptListView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @State private var editingScript: Script?
    @State private var showingAddSheet = false

    var body: some View {
        Form {
            Section {
                Button(action: { showingAddSheet = true }) {
                    Label("Add New Script", systemImage: "plus")
                        .fontWeight(.medium)
                }
                .padding(.vertical, 4)

                if let profile = profileManager.activeProfile {
                    if profile.scripts.isEmpty {
                        Text("No scripts defined")
                            .foregroundColor(.secondary)
                            .italic()
                            .padding()
                    } else {
                        List {
                            ForEach(profile.scripts) { script in
                                ScriptRow(script: script, onEdit: {
                                    editingScript = script
                                }, onDelete: {
                                    profileManager.removeScript(script)
                                })
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                                .background(GlassCardBackground())
                            }
                            .onMove { source, dest in
                                profileManager.moveScripts(from: source, to: dest)
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            } header: {
                Text("Scripts")
                    .foregroundColor(.secondary)
            } footer: {
                Text("Scripts let you write JavaScript logic for conditional actions, state tracking, and app-aware behavior. Powered by JavaScriptCore.")
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding()
        .sheet(isPresented: $showingAddSheet) {
            ScriptEditorSheet(script: nil)
        }
        .sheet(item: $editingScript) { script in
            ScriptEditorSheet(script: script)
        }
    }
}

struct ScriptRow: View {
    let script: Script
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.white.opacity(0.3))
                .font(.caption)
                .frame(width: 20)

            // Tappable content area
            HStack {
                Image(systemName: "applescript.fill")
                    .foregroundColor(.orange.opacity(0.6))
                    .font(.caption)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(script.name.isEmpty ? "Untitled Script" : script.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))

                    if let description = script.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(1)
                    } else {
                        Text("\(script.source.count) chars")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }
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

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .hoverableRow()
    }
}
