import SwiftUI

struct MacroListView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @State private var editingMacro: Macro?
    @State private var showingAddSheet = false

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
    }
}

struct MacroRow: View {
    let macro: Macro
    var onEdit: () -> Void
    var onDelete: () -> Void
    
    var body: some View {
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
        .contentShape(Rectangle())
        .hoverable()
    }
}
