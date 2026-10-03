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
				Button("Refresh") { Task { await shortcuts.refresh() } }.disabled(shortcuts.isLoading)
				Button("Open Shortcuts") { NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Shortcuts.app"), configuration: .init()) }
			}
			if !shortcuts.status.isEmpty { Text(shortcuts.status).font(.caption).foregroundStyle(.secondary) }
			Text("The controller runs this shortcut once per press. macOS may ask for permissions on its first run.")
				.font(.caption).foregroundStyle(.secondary)
		}
		.task { await shortcuts.refresh() }
	}
}
