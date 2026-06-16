import SwiftUI
import TriggerKitCore
import TriggerKitLibrary

public struct AutomationMacroLibraryView: View {
	private let store: AutomationMacroStore
	private let capabilities: AutomationCapabilities
	private let runMacro: ((AutomationMacro) -> Void)?

	@State private var macros: [AutomationMacro] = []
	@State private var selectedID: UUID?
	@State private var selectedName: String = ""
	@State private var selectedProgram: AutomationProgram = AutomationProgram(name: "New Macro")
	@State private var isLoadingSelection = false
	@State private var showDeleteConfirm = false

	public init(
		store: AutomationMacroStore = .shared,
		capabilities: AutomationCapabilities = .all,
		runMacro: ((AutomationMacro) -> Void)? = nil
	) {
		self.store = store
		self.capabilities = capabilities
		self.runMacro = runMacro
	}

	public var body: some View {
		HStack(spacing: 0) {
			sidebar
				.frame(width: 230)

			Divider()

			detail
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		.onAppear {
			refreshMacros(selectFirstIfNeeded: true)
		}
		.onReceive(NotificationCenter.default.publisher(for: .triggerKitMacrosChanged)) { _ in
			refreshMacros(selectFirstIfNeeded: false)
		}
		.onChange(of: selectedID) { _, _ in
			loadSelectedMacro()
		}
	}

	private var sidebar: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack {
				Text("Macros")
					.font(.caption.weight(.bold))
					.textCase(.uppercase)
					.foregroundStyle(.secondary)
				Spacer()
				Button {
					createMacro()
				} label: {
					Image(systemName: "plus")
				}
				.buttonStyle(.plain)
				.help("New macro")
				.accessibilityLabel("New macro")
			}
			.padding(.horizontal, 12)
			.padding(.top, 12)

			List(selection: $selectedID) {
				ForEach(macros) { macro in
					VStack(alignment: .leading, spacing: 2) {
						Text(macro.name)
							.font(.callout.weight(.semibold))
							.lineLimit(1)
						Text(macro.displaySummary)
							.font(.caption)
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
					.tag(Optional(macro.id))
				}
			}
			.listStyle(.sidebar)

			HStack(spacing: 8) {
				Button {
					duplicateSelectedMacro()
				} label: {
					Image(systemName: "plus.square.on.square")
				}
				.disabled(selectedID == nil)
				.help("Duplicate")
				.accessibilityLabel("Duplicate")

				Button(role: .destructive) {
					showDeleteConfirm = true
				} label: {
					Image(systemName: "trash")
				}
				.disabled(selectedID == nil)
				.help("Delete")
				.accessibilityLabel("Delete")
			}
			.buttonStyle(.plain)
			.padding(.horizontal, 12)
			.padding(.bottom, 12)
		}
		.confirmationDialog(
			"Delete macro?",
			isPresented: $showDeleteConfirm,
			titleVisibility: .visible
		) {
			Button("Delete", role: .destructive) {
				deleteSelectedMacro()
			}
			Button("Cancel", role: .cancel) {}
		} message: {
			Text("Apps linked to this macro will keep their last saved snapshot.")
		}
	}

	@ViewBuilder
	private var detail: some View {
		if selectedID == nil {
			VStack(spacing: 10) {
				Image(systemName: "square.stack.3d.up")
					.font(.largeTitle)
					.foregroundStyle(.secondary)
				Text("No macro selected")
					.foregroundStyle(.secondary)
				Button("New Macro") {
					createMacro()
				}
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
		} else {
			ScrollView {
				VStack(alignment: .leading, spacing: 14) {
					HStack {
						TextField("Macro name", text: $selectedName)
							.font(.title3.weight(.semibold))
							.textFieldStyle(.roundedBorder)
							.onChange(of: selectedName) { _, _ in
								persistSelectedMacro()
							}

						if let runMacro {
							Button {
								if let macro = selectedMacro {
									runMacro(macro)
								}
							} label: {
								Label("Run", systemImage: "play.fill")
							}
							.disabled(selectedMacro?.program.steps.isEmpty ?? true)
						}
					}

					AutomationProgramEditor(
						program: $selectedProgram,
						showsNameField: false,
						capabilities: capabilities
					)
					.onChange(of: selectedProgram) { _, _ in
						persistSelectedMacro()
					}
				}
				.padding(16)
			}
		}
	}

	private var selectedMacro: AutomationMacro? {
		guard let selectedID else { return nil }
		return store.macro(id: selectedID)
	}

	private func refreshMacros(selectFirstIfNeeded: Bool) {
		macros = store.all()
		if let selectedID, macros.contains(where: { $0.id == selectedID }) {
			return
		}
		if selectFirstIfNeeded || selectedID != nil {
			selectedID = macros.first?.id
			loadSelectedMacro()
		}
	}

	private func loadSelectedMacro() {
		guard let selectedID, let macro = store.macro(id: selectedID) else {
			selectedName = ""
			selectedProgram = AutomationProgram(name: "New Macro")
			return
		}
		isLoadingSelection = true
		selectedName = macro.name
		selectedProgram = macro.program
		isLoadingSelection = false
	}

	private func createMacro() {
		let macro = store.create(
			name: "New Macro",
			program: AutomationProgram(name: "New Macro")
		)
		refreshMacros(selectFirstIfNeeded: false)
		selectedID = macro.id
		loadSelectedMacro()
	}

	private func duplicateSelectedMacro() {
		guard let selectedID, let macro = store.duplicate(id: selectedID) else { return }
		refreshMacros(selectFirstIfNeeded: false)
		self.selectedID = macro.id
		loadSelectedMacro()
	}

	private func deleteSelectedMacro() {
		guard let selectedID else { return }
		store.remove(id: selectedID)
		let remaining = store.all()
		macros = remaining
		self.selectedID = remaining.first?.id
		loadSelectedMacro()
	}

	private func persistSelectedMacro() {
		guard !isLoadingSelection, let selectedID else { return }
		let name = AutomationMacro.normalizedName(selectedName)
		var program = selectedProgram.normalized(fallbackName: name)
		program.name = name
		let existing = store.macro(id: selectedID)
		let macro = AutomationMacro(
			id: selectedID,
			name: name,
			program: program,
			createdAt: existing?.createdAt ?? Date(),
			updatedAt: Date()
		)
		store.upsert(macro)
	}
}
