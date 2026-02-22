import SwiftUI

struct ScriptListView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @State private var editingScript: Script?
    @State private var showingAddSheet = false
    @State private var showingExamplesGallery = false
    @State private var showingAIPrompt = false
    @State private var prefilledExample: ScriptExample?

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
                        scriptsEmptyState
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
                scriptsFooter
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding()
        .sheet(isPresented: $showingAddSheet) {
            ScriptEditorSheet(script: nil, prefilledExample: prefilledExample)
                .onDisappear { prefilledExample = nil }
        }
        .sheet(item: $editingScript) { script in
            ScriptEditorSheet(script: script)
        }
        .sheet(isPresented: $showingExamplesGallery, onDismiss: {
            if prefilledExample != nil {
                showingAddSheet = true
            }
        }) {
            ScriptExamplesGalleryView { example in
                prefilledExample = example
            }
        }
        .sheet(isPresented: $showingAIPrompt) {
            ScriptAIPromptSheet()
        }
    }

    // MARK: - Empty State

    private var scriptsEmptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Automate anything with JavaScript. Here are some ideas:")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top, 4)

            ForEach(ScriptExamplesData.featured) { example in
                Button(action: {
                    prefilledExample = example
                    DispatchQueue.main.async {
                        showingAddSheet = true
                    }
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: example.icon)
                            .foregroundColor(.accentColor)
                            .font(.system(size: 13))
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(example.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                            Text(example.description)
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.4))
                                .lineLimit(1)
                        }

                        Spacer()

                        Image(systemName: "plus.circle")
                            .foregroundColor(.accentColor.opacity(0.6))
                            .font(.system(size: 13))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(GlassCardBackground())
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                Button(action: { showingExamplesGallery = true }) {
                    Label("Browse All Examples", systemImage: "square.grid.2x2")
                        .font(.system(size: 12))
                }

                Button(action: { showingAIPrompt = true }) {
                    Label("Generate with AI", systemImage: "sparkles")
                        .font(.system(size: 12))
                }
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Footer

    private var scriptsFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Scripts let you write JavaScript logic for conditional actions, state tracking, and app-aware behavior. Powered by JavaScriptCore.")
                .foregroundColor(.secondary.opacity(0.7))

            if profileManager.activeProfile?.scripts.isEmpty == false {
                HStack(spacing: 10) {
                    Button(action: { showingExamplesGallery = true }) {
                        Text("Browse Examples")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.link)

                    Button(action: { showingAIPrompt = true }) {
                        Text("Generate with AI")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.link)
                }
            }
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
                .accessibilityHidden(true)

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
                .accessibilityLabel("Edit")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .hoverableRow()
    }
}
