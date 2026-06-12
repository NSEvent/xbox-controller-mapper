import SwiftUI
import TriggerKitCore

public struct VisualKeyboardPicker: View {
	@Binding private var keyStroke: KeyStroke
	private let showsModifiers: Bool
	@State private var hoveredKeyID: String?
	@State private var searchText = ""
	@State private var selectedGroupID = "Common"
	@State private var showingKeyboard = false

	public init(keyStroke: Binding<KeyStroke>, showsModifiers: Bool = true) {
		self._keyStroke = keyStroke
		self.showsModifiers = showsModifiers
	}

	public var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack {
				Text(keyStroke.displaySummary)
					.font(.system(size: 12, weight: .bold, design: .monospaced))
					.lineLimit(1)
				Spacer()
				Button {
					showingKeyboard = true
				} label: {
					Label("Show Keyboard", systemImage: "keyboard")
				}
				.controlSize(.small)
				.popover(isPresented: $showingKeyboard, arrowEdge: .trailing) {
					ScrollView {
						ExpandedKeyboardPicker(keyStroke: $keyStroke, showsModifiers: showsModifiers)
							.frame(width: 720, alignment: .leading)
							.padding(12)
					}
					.frame(width: 760, height: showsModifiers ? 500 : 430)
				}
				Button("Clear") {
					keyStroke = KeyStroke(key: .return)
				}
				.font(.caption)
				.foregroundStyle(.red)
			}

			catalogPicker
			if showsModifiers {
				ModifierSetEditor(modifiers: modifiersBinding)
			}
		}
		.padding(10)
		.background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
		.clipShape(RoundedRectangle(cornerRadius: 8))
	}

	private var catalogPicker: some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack {
				TextField("Search all keys", text: $searchText)
					.textFieldStyle(.roundedBorder)
				if searchText.isEmpty {
					Picker("", selection: $selectedGroupID) {
						ForEach(TriggerKey.catalogGroups) { group in
							Text(group.title).tag(group.id)
						}
					}
					.pickerStyle(.menu)
					.frame(width: 132)
				}
			}

			ScrollView {
				LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 5)], spacing: 5) {
					ForEach(catalogKeys, id: \.id) { key in
						keyButton(key, width: 84)
					}
				}
				.padding(.vertical, 1)
			}
			.frame(maxHeight: 118)
		}
	}

	private var catalogKeys: [TriggerKey] {
		let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
		if query.isEmpty {
			return TriggerKey.catalogGroups.first { $0.id == selectedGroupID }?.keys ?? TriggerKey.catalogGroups.first?.keys ?? []
		}
		return TriggerKey.allCatalogKeys.filter { key in
			key.displayName.localizedCaseInsensitiveContains(query) ||
				key.id.localizedCaseInsensitiveContains(query) ||
				String(key.keyCode).contains(query)
		}
	}

	private var modifiersBinding: Binding<ModifierSet> {
		Binding(
			get: { keyStroke.modifiers },
			set: { keyStroke.modifiers = $0 }
		)
	}

	private func keyButton(_ key: TriggerKey, label: String? = nil, width: CGFloat = 32) -> some View {
		let selected = keyStroke.key.id == key.id
		let hovered = hoveredKeyID == key.id

		return Button {
			keyStroke.key = key
		} label: {
			Text(label ?? key.displayName)
				.font(.system(size: (label ?? key.displayName).count > 5 ? 9 : 11, weight: .semibold))
				.lineLimit(1)
				.minimumScaleFactor(0.7)
				.frame(width: width, height: 28)
				.background(selected ? Color.accentColor : hovered ? Color.accentColor.opacity(0.22) : Color(nsColor: .windowBackgroundColor))
				.foregroundStyle(selected ? .white : .primary)
				.clipShape(RoundedRectangle(cornerRadius: 5))
				.overlay(
					RoundedRectangle(cornerRadius: 5)
						.stroke(selected ? Color.accentColor : Color.gray.opacity(0.25), lineWidth: selected ? 2 : 1)
				)
		}
		.buttonStyle(.plain)
		.onHover { hovering in
			hoveredKeyID = hovering ? key.id : nil
		}
	}

}
