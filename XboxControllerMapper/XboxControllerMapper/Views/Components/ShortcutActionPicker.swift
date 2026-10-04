import SwiftUI

struct ShortcutActionPicker: View {
	@Binding var name: String
	@ObservedObject private var shortcuts: NativeShortcutService
	@State private var search = ""

	init(name: Binding<String>, shortcuts: NativeShortcutService = .shared) {
		_name = name
		self.shortcuts = shortcuts
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			if shortcuts.isLoading { ProgressView("Loading installed shortcuts…").controlSize(.small) }
			TextField("Search installed shortcuts", text: $search)
			Picker("Shortcut", selection: $name) {
				Text("Choose a shortcut").tag("")
				if !name.isEmpty, !shortcuts.names.contains(name) {
					Text("\(name) (missing)").tag(name)
				}
				ForEach(shortcuts.names.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) || $0 == name }, id: \.self) {
					Text($0).tag($0)
				}
			}
			HStack {
				Button("Test Shortcut") { Task { await shortcuts.run(name: name) } }
					.disabled(name.isEmpty || !shortcuts.names.contains(name) || shortcuts.isRunning || shortcuts.isLoading)
				Button("Refresh") { Task { await shortcuts.refresh() } }.disabled(shortcuts.isLoading || shortcuts.isRunning)
				Button("Open Shortcuts") { NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Shortcuts.app"), configuration: .init()) }
			}
			if shortcuts.isRunning {
				ProgressView("Running shortcut…").controlSize(.small)
				Text("If macOS is waiting for approval, open Shortcuts and check its prompt. Let this run finish before retrying.").font(.caption).foregroundStyle(.secondary)
			}
			if !shortcuts.status.isEmpty {
				Label(shortcuts.status, systemImage: shortcuts.lastRunSucceeded == true ? "checkmark.circle" : shortcuts.lastRunSucceeded == false ? "exclamationmark.circle" : "info.circle")
					.font(.caption).foregroundStyle(shortcuts.lastRunSucceeded == false ? Color.orange : Color.secondary)
			}
			Text("Test Shortcut runs its actions immediately. Nothing runs just by selecting a shortcut. Tests stop waiting after 60 seconds and never retry automatically. The controller runs this shortcut once per press. macOS may ask for permissions on its first run.")
				.font(.caption).foregroundStyle(.secondary)
		}
		.task { await shortcuts.refresh() }
	}
}
