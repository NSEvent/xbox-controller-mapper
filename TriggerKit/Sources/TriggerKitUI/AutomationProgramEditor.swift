import SwiftUI
import TriggerKitCore

public struct AutomationProgramEditor: View {
	@Binding private var program: AutomationProgram
	private let showsNameField: Bool
	private let capabilities: AutomationCapabilities
	/// Optional host hook: when set, the editor shows a "Test" button that runs
	/// the current program now and displays the returned outcome. Execution stays
	/// host-owned (env vars, custom-action handling, target focus). `nil` hides
	/// the button.
	private let onTestRun: (@MainActor (AutomationProgram) async -> ProgramRunOutcome)?
	@State private var expandedStepIndexes: Set<Int> = []
	@State private var isTesting = false
	@State private var testOutcome: ProgramRunOutcome?

	public init(
		program: Binding<AutomationProgram>,
		showsNameField: Bool = true,
		capabilities: AutomationCapabilities = .all,
		onTestRun: (@MainActor (AutomationProgram) async -> ProgramRunOutcome)? = nil
	) {
		self._program = program
		self.showsNameField = showsNameField
		self.capabilities = capabilities
		self.onTestRun = onTestRun
	}

	public var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			if showsNameField {
				TextField("Action name", text: $program.name)
					.textFieldStyle(.roundedBorder)
			}

			stepList

			if let testOutcome {
				testResultLine(testOutcome)
			}
		}
		.onAppear {
			normalizeExpandedSteps()
		}
		.onChange(of: program.steps.count) { _, _ in
			normalizeExpandedSteps()
		}
		.onChange(of: program.steps.map(\.kind)) { _, _ in
			normalizeExpandedSteps()
		}
		.onChange(of: capabilities) { _, _ in
			normalizeExpandedSteps()
		}
	}

	private var stepList: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack {
				Text("Steps")
					.font(.caption.weight(.bold))
					.textCase(.uppercase)
					.foregroundStyle(.secondary)

				Spacer()

				if let onTestRun {
					Button {
						runTest(onTestRun)
					} label: {
						if isTesting {
							ProgressView().controlSize(.small)
						} else {
							Label("Test", systemImage: "play.fill")
						}
					}
					.disabled(isTesting || program.steps.isEmpty)
					.help("Run these steps now")
					.accessibilityLabel("Run these steps now")
				}

				Menu {
					if capabilities.allows(.typeText) {
						addStepButton("Type Text", systemImage: "text.cursor", kind: .typeText)
					}
					if capabilities.allows(.keyPress) {
						addStepButton("Key Shortcut", systemImage: "keyboard", kind: .keyPress)
					}
					if capabilities.allows(.keyDown) {
						addStepButton("Key Down", systemImage: "arrow.down.square", kind: .keyDown)
					}
					if capabilities.allows(.keyUp) {
						addStepButton("Key Up", systemImage: "arrow.up.square", kind: .keyUp)
					}
					if allowsAny([.typeText, .keyPress, .keyDown, .keyUp]), allowsAny([.mouseClick, .mouseDown, .mouseUp, .mouseMove, .mouseScroll]) {
						Divider()
					}
					if capabilities.allows(.mouseClick) {
						addStepButton("Mouse Click", systemImage: "cursorarrow.click", kind: .mouseClick)
					}
					if capabilities.allows(.mouseDown) {
						addStepButton("Mouse Down", systemImage: "cursorarrow", kind: .mouseDown)
					}
					if capabilities.allows(.mouseUp) {
						addStepButton("Mouse Up", systemImage: "cursorarrow.rays", kind: .mouseUp)
					}
					if capabilities.allows(.mouseMove) {
						addStepButton("Mouse Move", systemImage: "move.3d", kind: .mouseMove)
					}
					if capabilities.allows(.mouseScroll) {
						addStepButton("Mouse Scroll", systemImage: "arrow.up.and.down", kind: .mouseScroll)
					}
					if allowsAny([.mouseClick, .mouseDown, .mouseUp, .mouseMove, .mouseScroll]), allowsAny([.delay, .openApp, .openURL, .shellCommand]) {
						Divider()
					}
					if capabilities.allows(.delay) {
						addStepButton("Delay", systemImage: "timer", kind: .delay)
					}
					if capabilities.allows(.openApp) {
						addStepButton("Open App", systemImage: "app", kind: .openApp)
					}
					if capabilities.allows(.openURL) {
						addStepButton("Open URL", systemImage: "safari", kind: .openURL)
					}
					if capabilities.allows(.shellCommand) {
						addStepButton("Shell Command", systemImage: "terminal", kind: .shellCommand)
					}
					if allowsAny([.clipboard, .systemSetting, .condition]) {
						Divider()
					}
					if capabilities.allows(.clipboard) {
						addStepButton("Set Clipboard", systemImage: "doc.on.clipboard", kind: .clipboard)
					}
					if capabilities.allows(.systemSetting) {
						addStepButton("System Setting", systemImage: "slider.horizontal.3", kind: .systemSetting)
					}
					if capabilities.allows(.condition) {
						addStepButton("Condition (Only If…)", systemImage: "arrow.triangle.branch", kind: .condition)
					}
					let customActions = capabilities.allows(.custom) ? CustomActionRegistry.shared.descriptors : []
					if !customActions.isEmpty {
						Divider()
						ForEach(customActionGroups(customActions)) { group in
							if let title = group.title {
								Section(title) {
									ForEach(group.descriptors) { descriptor in
										addCustomActionButton(descriptor)
									}
								}
							} else {
								ForEach(group.descriptors) { descriptor in
									addCustomActionButton(descriptor)
								}
							}
						}
					}
				} label: {
					Label("Add", systemImage: "plus")
				}
				.disabled(capabilities.allowedStepKinds.isEmpty)
			}

			if program.steps.isEmpty {
				Text("No steps")
					.font(.callout)
					.foregroundStyle(.secondary)
					.frame(maxWidth: .infinity, minHeight: 52)
					.background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
					.clipShape(RoundedRectangle(cornerRadius: 8))
			} else {
				VStack(spacing: 6) {
					ForEach(Array(program.steps.enumerated()), id: \.offset) { index, step in
						stepRow(step, at: index)
					}
				}
			}
		}
	}

	private func stepRow(_ step: AutomationStep, at index: Int) -> some View {
		let allowed = capabilities.allows(step.kind)
		let expanded = allowed && expandedStepIndexes.contains(index)

		return VStack(alignment: .leading, spacing: 6) {
			HStack(spacing: 8) {
				Button {
					if allowed {
						toggleExpanded(index)
					}
				} label: {
					Image(systemName: expanded ? "chevron.down" : "chevron.right")
						.frame(width: 16)
				}
				.disabled(!allowed)
				.help(allowed ? (expanded ? "Collapse" : "Expand") : "Unavailable in this host")
				.accessibilityLabel(allowed ? (expanded ? "Collapse" : "Expand") : "Unavailable in this host")

				HStack(spacing: 8) {
					Image(systemName: iconName(for: step))
						.frame(width: 18)
						.foregroundStyle(allowed ? Color.accentColor : Color.secondary)

					Text(step.displaySummary)
						.font(.callout.weight(.semibold))
						.lineLimit(1)
						.frame(maxWidth: .infinity, alignment: .leading)
				}
				.contentShape(Rectangle())
				.onTapGesture {
					if allowed {
						toggleExpanded(index)
					}
				}

				Button {
					moveStep(from: index, by: -1)
				} label: {
					Image(systemName: "chevron.up")
				}
				.disabled(index == 0)
				.help("Move up")
				.accessibilityLabel("Move up")

				Button {
					moveStep(from: index, by: 1)
				} label: {
					Image(systemName: "chevron.down")
				}
				.disabled(index == program.steps.count - 1)
				.help("Move down")
				.accessibilityLabel("Move down")

				Button(role: .destructive) {
					deleteStep(at: index)
				} label: {
					Image(systemName: "trash")
				}
				.help("Delete")
				.accessibilityLabel("Delete")
			}
			.buttonStyle(.plain)

			if !allowed {
				Label("\(step.kind.displayName) is unavailable in this host", systemImage: "exclamationmark.triangle")
					.font(.caption)
					.foregroundStyle(.secondary)
					.padding(.leading, 24)
			}

			if expanded {
				AutomationStepEditor(step: stepBinding(at: index))
					.padding(.leading, 24)
			}
		}
		.padding(.horizontal, 10)
		.padding(.vertical, 8)
		.background(
			expanded ? Color.accentColor.opacity(0.08) :
				allowed ? Color(nsColor: .controlBackgroundColor).opacity(0.55) :
				Color(nsColor: .controlBackgroundColor).opacity(0.3)
		)
		.foregroundStyle(Color.primary)
		.clipShape(RoundedRectangle(cornerRadius: 8))
		.contentShape(RoundedRectangle(cornerRadius: 8))
	}

	private func stepBinding(at index: Int) -> Binding<AutomationStep> {
		Binding(
			get: {
				guard program.steps.indices.contains(index) else {
					return .delay(DelayStep(seconds: 1))
				}
				return program.steps[index]
			},
			set: {
				guard program.steps.indices.contains(index) else { return }
				program.steps[index] = $0
			}
		)
	}

	private func addStepButton(_ title: String, systemImage: String, kind: AutomationStep.Kind) -> some View {
		Button {
			let step = defaultStep(for: kind)
			program.steps.append(step)
			expandedStepIndexes.insert(program.steps.count - 1)
		} label: {
			Label(title, systemImage: systemImage)
		}
	}

	private func addCustomActionButton(_ descriptor: CustomActionDescriptor) -> some View {
		Button {
			program.steps.append(.custom(descriptor.makeStep()))
			expandedStepIndexes.insert(program.steps.count - 1)
		} label: {
			Label(descriptor.title, systemImage: descriptor.systemImage)
		}
	}

	private struct CustomActionGroup: Identifiable {
		let id: String
		let title: String?
		let descriptors: [CustomActionDescriptor]
	}

	/// Buckets descriptors by `category`, preserving first-seen order for both the
	/// groups and the descriptors within each. Uncategorized descriptors form a
	/// trailing headerless group.
	private func customActionGroups(_ descriptors: [CustomActionDescriptor]) -> [CustomActionGroup] {
		var order: [String] = []
		var buckets: [String: [CustomActionDescriptor]] = [:]
		for descriptor in descriptors {
			let key = descriptor.category ?? ""
			if buckets[key] == nil { order.append(key) }
			buckets[key, default: []].append(descriptor)
		}
		return order.map { key in
			CustomActionGroup(
				id: key.isEmpty ? "_uncategorized" : key,
				title: key.isEmpty ? nil : key,
				descriptors: buckets[key] ?? []
			)
		}
	}

	private func runTest(_ runner: @escaping @MainActor (AutomationProgram) async -> ProgramRunOutcome) {
		guard !isTesting, !program.steps.isEmpty else { return }
		isTesting = true
		testOutcome = nil
		let snapshot = program
		Task { @MainActor in
			let outcome = await runner(snapshot)
			testOutcome = outcome
			isTesting = false
		}
	}

	@ViewBuilder
	private func testResultLine(_ outcome: ProgramRunOutcome) -> some View {
		Label(outcome.message, systemImage: outcome.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
			.font(.caption)
			.foregroundStyle(outcome.succeeded ? Color.green : Color.red)
			.lineLimit(3)
			.textSelection(.enabled)
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(.horizontal, 10)
			.padding(.vertical, 6)
			.background(
				(outcome.succeeded ? Color.green : Color.red).opacity(0.10),
				in: RoundedRectangle(cornerRadius: 6)
			)
	}

	private func allowsAny(_ kinds: [AutomationStep.Kind]) -> Bool {
		kinds.contains { capabilities.allows($0) }
	}

	private func toggleExpanded(_ index: Int) {
		guard program.steps.indices.contains(index), capabilities.allows(program.steps[index].kind) else {
			expandedStepIndexes.remove(index)
			return
		}
		if expandedStepIndexes.contains(index) {
			expandedStepIndexes.remove(index)
		} else {
			expandedStepIndexes.insert(index)
		}
	}

	private func moveStep(from index: Int, by offset: Int) {
		let destination = index + offset
		guard program.steps.indices.contains(index), program.steps.indices.contains(destination) else { return }
		program.steps.swapAt(index, destination)
		let sourceWasExpanded = expandedStepIndexes.contains(index)
		let destinationWasExpanded = expandedStepIndexes.contains(destination)
		expandedStepIndexes.remove(index)
		expandedStepIndexes.remove(destination)
		if sourceWasExpanded { expandedStepIndexes.insert(destination) }
		if destinationWasExpanded { expandedStepIndexes.insert(index) }
	}

	private func deleteStep(at index: Int) {
		guard program.steps.indices.contains(index) else { return }
		program.steps.remove(at: index)
		expandedStepIndexes = Set(expandedStepIndexes.compactMap { expandedIndex in
			if expandedIndex == index {
				return nil
			}
			return expandedIndex > index ? expandedIndex - 1 : expandedIndex
		})
	}

	private func normalizeExpandedSteps() {
		expandedStepIndexes = Set(expandedStepIndexes.filter {
			program.steps.indices.contains($0) && capabilities.allows(program.steps[$0].kind)
		})
		if expandedStepIndexes.isEmpty, let firstEditableIndex = program.steps.indices.first(where: { capabilities.allows(program.steps[$0].kind) }) {
			expandedStepIndexes.insert(firstEditableIndex)
		}
	}

	private func defaultStep(for kind: AutomationStep.Kind) -> AutomationStep {
		AutomationStep.defaultValue(for: kind)
	}

	private func iconName(for step: AutomationStep) -> String {
		if case .custom(let custom) = step,
		   let descriptor = CustomActionRegistry.shared.descriptor(for: custom.namespace) {
			return descriptor.systemImage
		}
		return iconName(for: step.kind)
	}

	private func iconName(for kind: AutomationStep.Kind) -> String {
		switch kind {
		case .keyPress: return "keyboard"
		case .keyDown: return "arrow.down.square"
		case .keyUp: return "arrow.up.square"
		case .mouseClick: return "cursorarrow.click"
		case .mouseDown: return "cursorarrow"
		case .mouseUp: return "cursorarrow.rays"
		case .mouseMove: return "move.3d"
		case .mouseScroll: return "arrow.up.and.down"
		case .delay: return "timer"
		case .typeText: return "text.cursor"
		case .openApp: return "app"
		case .openURL: return "safari"
		case .shellCommand: return "terminal"
		case .webhook: return "antenna.radiowaves.left.and.right"
		case .clipboard: return "doc.on.clipboard"
		case .systemSetting: return "slider.horizontal.3"
		case .condition: return "arrow.triangle.branch"
		case .custom: return "puzzlepiece.extension"
		}
	}
}

private struct AutomationStepEditor: View {
	@Binding var step: AutomationStep
	@State private var showingAppPicker = false

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text(editorTitle)
				.font(.caption.weight(.bold))
				.textCase(.uppercase)
				.foregroundStyle(.secondary)

			switch step {
			case .typeText:
				typeTextEditor
			case .keyPress:
				VisualKeyboardPicker(keyStroke: keyStrokeBinding)
			case .keyDown:
				VisualKeyboardPicker(keyStroke: keyDownStrokeBinding)
			case .keyUp:
				VisualKeyboardPicker(keyStroke: keyUpStrokeBinding)
			case .mouseClick:
				VisualMousePicker(click: mouseClickBinding)
			case .mouseDown:
				mouseButtonEditor(binding: mouseDownBinding)
			case .mouseUp:
				mouseButtonEditor(binding: mouseUpBinding)
			case .mouseMove:
				mouseMoveEditor
			case .mouseScroll:
				mouseScrollEditor
			case .delay:
				delayEditor
			case .openApp:
				openAppEditor
			case .openURL:
				openURLEditor
			case .shellCommand:
				shellCommandEditor
			case .webhook:
				webhookEditor
			case .clipboard:
				clipboardEditor
			case .systemSetting:
				systemSettingEditor
			case .condition:
				conditionEditor
			case .custom:
				customStepEditor
			}
		}
		.padding(10)
		.background(Color(nsColor: .windowBackgroundColor).opacity(0.72))
		.clipShape(RoundedRectangle(cornerRadius: 8))
		.overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.18)))
		.sheet(isPresented: $showingAppPicker) {
			InstalledAppPickerSheet(currentBundleIdentifier: openAppBinding.wrappedValue.bundleIdentifier) { app in
				var step = openAppBinding.wrappedValue
				step.bundleIdentifier = app.bundleIdentifier
				openAppBinding.wrappedValue = step
			}
		}
	}

	private var editorTitle: String {
		switch step.kind {
		case .keyPress: return "Key Shortcut"
		case .keyDown: return "Key Down"
		case .keyUp: return "Key Up"
		case .mouseClick: return "Mouse Click"
		case .mouseDown: return "Mouse Down"
		case .mouseUp: return "Mouse Up"
		case .mouseMove: return "Mouse Move"
		case .mouseScroll: return "Mouse Scroll"
		case .delay: return "Delay"
		case .typeText: return "Type Text"
		case .openApp: return "Open App"
		case .openURL: return "Open URL"
		case .shellCommand: return "Shell Command"
		case .webhook: return "Webhook"
		case .clipboard: return "Set Clipboard"
		case .systemSetting: return "System Setting"
		case .condition: return "Condition"
		case .custom: return "App Action"
		}
	}

	private var typeTextEditor: some View {
		VStack(alignment: .leading, spacing: 8) {
			TextEditor(text: typeTextTextBinding)
				.font(.system(.body, design: .monospaced))
				.frame(height: 96)
				.scrollContentBackground(.hidden)
				.background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
				.clipShape(RoundedRectangle(cornerRadius: 7))

			TextEntryModeSelector(selection: typeTextModeBinding)

			if typeTextModeBinding.wrappedValue == .type {
				HStack {
					Text("Speed")
						.font(.caption)
						.foregroundStyle(.secondary)
					TextField("0", value: typeTextPaceBinding, format: .number)
						.textFieldStyle(.roundedBorder)
						.frame(width: 96)
					Text("chars/min (0 = fastest)")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}

			Toggle("Press Return after text", isOn: typeTextReturnBinding)
		}
	}

	private func mouseButtonEditor(binding: Binding<MouseButtonEvent>) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			MouseButtonPicker(
				button: Binding(
					get: { binding.wrappedValue.button },
					set: { binding.wrappedValue.button = $0 }
				)
			)
			ModifierSetEditor(
				modifiers: Binding(
					get: { binding.wrappedValue.modifiers },
					set: { binding.wrappedValue.modifiers = $0 }
				)
			)
		}
	}

	private var mouseMoveEditor: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack {
				Text("X")
					.frame(width: 18, alignment: .leading)
				TextField("0", value: mouseMoveXBinding, format: .number)
					.textFieldStyle(.roundedBorder)
				Text("Y")
					.frame(width: 18, alignment: .leading)
				TextField("0", value: mouseMoveYBinding, format: .number)
					.textFieldStyle(.roundedBorder)
			}
			.font(.callout)

			Text("Positive X moves right. Positive Y follows macOS event coordinates.")
				.font(.caption)
				.foregroundStyle(.secondary)
		}
	}

	private var mouseScrollEditor: some View {
		VStack(alignment: .leading, spacing: 8) {
			ScrollDirectionPicker(scroll: mouseScrollBinding)
			HStack {
				Text("X")
					.frame(width: 18, alignment: .leading)
				TextField("0", value: mouseScrollXBinding, format: .number)
					.textFieldStyle(.roundedBorder)
				Text("Y")
					.frame(width: 18, alignment: .leading)
				TextField("0", value: mouseScrollYBinding, format: .number)
					.textFieldStyle(.roundedBorder)
			}
			.font(.callout)
		}
	}

	private var delayEditor: some View {
		HStack {
			TextField("Seconds", value: delaySecondsBinding, format: .number.precision(.fractionLength(0...2)))
				.textFieldStyle(.roundedBorder)
			Text("seconds")
				.foregroundStyle(.secondary)
		}
	}

	private var clipboardEditor: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("Clipboard text")
				.font(.caption)
				.foregroundStyle(.secondary)
			TextEditor(text: clipboardTextBinding)
				.font(.system(.body, design: .monospaced))
				.frame(height: 72)
				.scrollContentBackground(.hidden)
				.background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
				.clipShape(RoundedRectangle(cornerRadius: 7))
			Text("Sets the clipboard. Add a Key Shortcut ⌘V afterward to paste.")
				.font(.caption)
				.foregroundStyle(.secondary)
		}
	}

	private var systemSettingEditor: some View {
		VStack(alignment: .leading, spacing: 8) {
			Picker("Setting", selection: systemSettingActionBinding) {
				ForEach(SystemSettingAction.allCases, id: \.self) { action in
					Text(action.displayName).tag(action)
				}
			}
			.labelsHidden()
			.pickerStyle(.menu)

			if systemSettingActionBinding.wrappedValue == .setVolume {
				HStack(spacing: 8) {
					Slider(value: systemSettingVolumeBinding, in: 0...100, step: 1)
					Text("\(Int(systemSettingVolumeBinding.wrappedValue.rounded()))")
						.font(.caption)
						.monospacedDigit()
						.foregroundStyle(.secondary)
						.frame(minWidth: 32, alignment: .trailing)
				}
			}

			if systemSettingActionBinding.wrappedValue == .toggleDarkMode {
				Text("First run prompts to allow controlling System Events.")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
	}

	private var conditionEditor: some View {
		VStack(alignment: .leading, spacing: 8) {
			Picker("Test", selection: conditionKindBinding) {
				ForEach(ConditionKind.allCases, id: \.self) { kind in
					Text(kind.displayName).tag(kind)
				}
			}
			.labelsHidden()
			.pickerStyle(.menu)

			Toggle("Invert (skip when the condition is true)", isOn: conditionNegateBinding)
				.font(.callout)

			switch conditionKindBinding.wrappedValue {
			case .online:
				Text("Skips the remaining steps when offline.")
					.font(.caption)
					.foregroundStyle(.secondary)
			case .appRunning:
				VStack(alignment: .leading, spacing: 4) {
					Text("Bundle ID")
						.font(.caption)
						.foregroundStyle(.secondary)
					TextField("com.spotify.client", text: conditionBundleBinding)
						.textFieldStyle(.roundedBorder)
				}
			case .timeWindow:
				HStack(spacing: 8) {
					Text("From")
						.font(.caption)
						.foregroundStyle(.secondary)
					DatePicker("", selection: conditionStartBinding, displayedComponents: .hourAndMinute)
						.labelsHidden()
					Text("to")
						.font(.caption)
						.foregroundStyle(.secondary)
					DatePicker("", selection: conditionEndBinding, displayedComponents: .hourAndMinute)
						.labelsHidden()
				}
			}

			Text(conditionBinding.wrappedValue.displaySummary)
				.font(.caption)
				.foregroundStyle(.secondary)
		}
	}

	private var openAppEditor: some View {
		VStack(alignment: .leading, spacing: 8) {
			InstalledAppPickerButton(bundleIdentifier: openAppBundleBinding.wrappedValue) {
				showingAppPicker = true
			}

			VStack(alignment: .leading, spacing: 4) {
				Text("Bundle ID")
					.font(.caption)
					.foregroundStyle(.secondary)
				TextField("com.apple.TextEdit", text: openAppBundleBinding)
					.textFieldStyle(.roundedBorder)
			}

			Toggle("Open new window when supported", isOn: openAppNewWindowBinding)
		}
	}

	private var openURLEditor: some View {
		TextField("https://example.com", text: openURLBinding)
			.textFieldStyle(.roundedBorder)
	}

	private var shellCommandEditor: some View {
		VStack(alignment: .leading, spacing: 8) {
			TextField("say done", text: shellCommandBinding, axis: .vertical)
				.font(.system(.body, design: .monospaced))
				.lineLimit(3...7)
				.textFieldStyle(.roundedBorder)

			HStack {
				VStack(alignment: .leading, spacing: 4) {
					Text("Shell")
						.font(.caption)
						.foregroundStyle(.secondary)
					TextField("/bin/zsh", text: shellPathBinding)
						.textFieldStyle(.roundedBorder)
				}

				VStack(alignment: .leading, spacing: 4) {
					Text("Timeout (seconds)")
						.font(.caption)
						.foregroundStyle(.secondary)
					TextField("10", value: shellTimeoutBinding, format: .number)
						.textFieldStyle(.roundedBorder)
						.frame(width: 128)
				}
			}
		}
	}

	private var webhookEditor: some View {
		VStack(alignment: .leading, spacing: 8) {
			TextField("https://example.com/hook", text: webhookURLBinding)
				.textFieldStyle(.roundedBorder)

			Picker("Method", selection: webhookMethodBinding) {
				ForEach(WebhookMethod.allCases, id: \.self) { method in
					Text(method.rawValue).tag(method)
				}
			}
			.pickerStyle(.segmented)
			.labelsHidden()

			VStack(alignment: .leading, spacing: 4) {
				Text("Body")
					.font(.caption)
					.foregroundStyle(.secondary)
				TextField("{}", text: webhookBodyBinding, axis: .vertical)
					.font(.system(.body, design: .monospaced))
					.lineLimit(2...6)
					.textFieldStyle(.roundedBorder)
			}

			if !webhookBinding.wrappedValue.headers.isEmpty {
				Text("\(webhookBinding.wrappedValue.headers.count) custom header(s) preserved")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
	}

	@ViewBuilder
	private var customStepEditor: some View {
		if let descriptor = CustomActionRegistry.shared.descriptor(for: customBinding.wrappedValue.namespace) {
			registeredCustomEditor(descriptor)
		} else {
			rawCustomEditor
		}
	}

	private func registeredCustomEditor(_ descriptor: CustomActionDescriptor) -> some View {
		VStack(alignment: .leading, spacing: 10) {
			if descriptor.options.isEmpty {
				Text("This action has no options.")
					.font(.caption)
					.foregroundStyle(.secondary)
			} else {
				ForEach(descriptor.options) { option in
					optionRow(option)
				}
			}
		}
	}

	@ViewBuilder
	private func optionRow(_ option: CustomActionOption) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			switch option.kind {
			case .toggle(let defaultValue):
				Toggle(option.label, isOn: boolOptionBinding(option.key, default: defaultValue))
			case .text(let defaultValue, let placeholder):
				Text(option.label)
					.font(.caption)
					.foregroundStyle(.secondary)
				TextField(placeholder, text: stringOptionBinding(option.key, default: defaultValue))
					.textFieldStyle(.roundedBorder)
			case .number(let defaultValue, let range, let step):
				Text(option.label)
					.font(.caption)
					.foregroundStyle(.secondary)
				HStack(spacing: 8) {
					Slider(value: doubleOptionBinding(option.key, default: defaultValue), in: range, step: step)
					Text(numberDisplay(doubleOptionBinding(option.key, default: defaultValue).wrappedValue, step: step))
						.font(.caption)
						.monospacedDigit()
						.foregroundStyle(.secondary)
						.frame(minWidth: 32, alignment: .trailing)
				}
			case .picker(let defaultValue, let choices):
				Text(option.label)
					.font(.caption)
					.foregroundStyle(.secondary)
				Picker(option.label, selection: stringOptionBinding(option.key, default: defaultValue)) {
					ForEach(choices) { choice in
						Text(choice.label).tag(choice.value)
					}
				}
				.labelsHidden()
				.pickerStyle(.segmented)
			}
			if let help = option.help {
				Text(help)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
	}

	private var rawCustomEditor: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 6) {
				Text("Namespace")
					.font(.caption)
					.foregroundStyle(.secondary)
				Text(customBinding.wrappedValue.namespace.isEmpty ? "—" : customBinding.wrappedValue.namespace)
					.font(.system(.caption, design: .monospaced))
			}

			VStack(alignment: .leading, spacing: 4) {
				Text("Payload (managed by the providing app)")
					.font(.caption)
					.foregroundStyle(.secondary)
				TextField("{}", text: customPayloadBinding, axis: .vertical)
					.font(.system(.body, design: .monospaced))
					.lineLimit(2...6)
					.textFieldStyle(.roundedBorder)
			}
		}
	}

	private func boolOptionBinding(_ key: String, default defaultValue: Bool) -> Binding<Bool> {
		Binding(
			get: {
				CustomActionPayload.bool(key, in: customBinding.wrappedValue.payload, default: defaultValue)
			},
			set: { newValue in
				var custom = customBinding.wrappedValue
				custom.payload = CustomActionPayload.setting(newValue, for: key, in: custom.payload)
				customBinding.wrappedValue = custom
			}
		)
	}

	private func doubleOptionBinding(_ key: String, default defaultValue: Double) -> Binding<Double> {
		Binding(
			get: {
				CustomActionPayload.double(key, in: customBinding.wrappedValue.payload, default: defaultValue)
			},
			set: { newValue in
				var custom = customBinding.wrappedValue
				custom.payload = CustomActionPayload.setting(newValue, for: key, in: custom.payload)
				customBinding.wrappedValue = custom
			}
		)
	}

	/// Formats a numeric option value: whole numbers when the step is integral,
	/// otherwise one decimal place.
	private func numberDisplay(_ value: Double, step: Double) -> String {
		if step >= 1, step.rounded() == step {
			return String(Int(value.rounded()))
		}
		return String(format: "%.1f", value)
	}

	private func stringOptionBinding(_ key: String, default defaultValue: String) -> Binding<String> {
		Binding(
			get: {
				CustomActionPayload.string(key, in: customBinding.wrappedValue.payload, default: defaultValue)
			},
			set: { newValue in
				var custom = customBinding.wrappedValue
				custom.payload = CustomActionPayload.setting(newValue, for: key, in: custom.payload)
				customBinding.wrappedValue = custom
			}
		)
	}

	private var keyStrokeBinding: Binding<KeyStroke> {
		Binding(
			get: {
				if case .keyPress(let stroke) = step { return stroke }
				return KeyStroke(key: .return)
			},
			set: { step = .keyPress($0) }
		)
	}

	private var keyDownStrokeBinding: Binding<KeyStroke> {
		Binding(
			get: {
				if case .keyDown(let event) = step { return KeyStroke(key: event.key, modifiers: event.modifiers) }
				return KeyStroke(key: .return)
			},
			set: { step = .keyDown(KeyEvent(key: $0.key, modifiers: $0.modifiers)) }
		)
	}

	private var keyUpStrokeBinding: Binding<KeyStroke> {
		Binding(
			get: {
				if case .keyUp(let event) = step { return KeyStroke(key: event.key, modifiers: event.modifiers) }
				return KeyStroke(key: .return)
			},
			set: { step = .keyUp(KeyEvent(key: $0.key, modifiers: $0.modifiers)) }
		)
	}

	private var mouseClickBinding: Binding<MouseClick> {
		Binding(
			get: {
				if case .mouseClick(let click) = step { return click }
				return MouseClick(button: .left)
			},
			set: { step = .mouseClick($0) }
		)
	}

	private var mouseDownBinding: Binding<MouseButtonEvent> {
		Binding(
			get: {
				if case .mouseDown(let event) = step { return event }
				return MouseButtonEvent(button: .left)
			},
			set: { step = .mouseDown($0) }
		)
	}

	private var mouseUpBinding: Binding<MouseButtonEvent> {
		Binding(
			get: {
				if case .mouseUp(let event) = step { return event }
				return MouseButtonEvent(button: .left)
			},
			set: { step = .mouseUp($0) }
		)
	}

	private var mouseMoveBinding: Binding<MouseMove> {
		Binding(
			get: {
				if case .mouseMove(let move) = step { return move }
				return MouseMove(deltaX: 0, deltaY: 0)
			},
			set: { step = .mouseMove($0) }
		)
	}

	private var mouseMoveXBinding: Binding<Double> {
		Binding(
			get: { mouseMoveBinding.wrappedValue.deltaX },
			set: {
				var move = mouseMoveBinding.wrappedValue
				move.deltaX = $0
				mouseMoveBinding.wrappedValue = move
			}
		)
	}

	private var mouseMoveYBinding: Binding<Double> {
		Binding(
			get: { mouseMoveBinding.wrappedValue.deltaY },
			set: {
				var move = mouseMoveBinding.wrappedValue
				move.deltaY = $0
				mouseMoveBinding.wrappedValue = move
			}
		)
	}

	private var mouseScrollBinding: Binding<MouseScroll> {
		Binding(
			get: {
				if case .mouseScroll(let scroll) = step { return scroll }
				return MouseScroll(deltaY: -4)
			},
			set: { step = .mouseScroll($0) }
		)
	}

	private var mouseScrollXBinding: Binding<Int32> {
		Binding(
			get: { mouseScrollBinding.wrappedValue.deltaX },
			set: {
				var scroll = mouseScrollBinding.wrappedValue
				scroll.deltaX = $0
				mouseScrollBinding.wrappedValue = scroll
			}
		)
	}

	private var mouseScrollYBinding: Binding<Int32> {
		Binding(
			get: { mouseScrollBinding.wrappedValue.deltaY },
			set: {
				var scroll = mouseScrollBinding.wrappedValue
				scroll.deltaY = $0
				mouseScrollBinding.wrappedValue = scroll
			}
		)
	}

	private var delayBinding: Binding<DelayStep> {
		Binding(
			get: {
				if case .delay(let delay) = step { return delay }
				return DelayStep(seconds: 1)
			},
			set: { step = .delay($0) }
		)
	}

	private var delaySecondsBinding: Binding<Double> {
		Binding(
			get: { delayBinding.wrappedValue.seconds },
			set: { delayBinding.wrappedValue = DelayStep(seconds: $0) }
		)
	}

	private var clipboardBinding: Binding<ClipboardStep> {
		Binding(
			get: {
				if case .clipboard(let clip) = step { return clip }
				return ClipboardStep()
			},
			set: { step = .clipboard($0) }
		)
	}

	private var clipboardTextBinding: Binding<String> {
		Binding(
			get: { clipboardBinding.wrappedValue.text },
			set: { clipboardBinding.wrappedValue = ClipboardStep(text: $0) }
		)
	}

	private var systemSettingBinding: Binding<SystemSettingStep> {
		Binding(
			get: {
				if case .systemSetting(let setting) = step { return setting }
				return SystemSettingStep(action: .setVolume)
			},
			set: { step = .systemSetting($0) }
		)
	}

	private var systemSettingActionBinding: Binding<SystemSettingAction> {
		Binding(
			get: { systemSettingBinding.wrappedValue.action },
			set: {
				var setting = systemSettingBinding.wrappedValue
				setting.action = $0
				systemSettingBinding.wrappedValue = setting
			}
		)
	}

	private var systemSettingVolumeBinding: Binding<Double> {
		Binding(
			get: { Double(systemSettingBinding.wrappedValue.volume) },
			set: {
				var setting = systemSettingBinding.wrappedValue
				setting.volume = Int($0.rounded())
				systemSettingBinding.wrappedValue = setting
			}
		)
	}

	private var conditionBinding: Binding<ConditionStep> {
		Binding(
			get: {
				if case .condition(let cond) = step { return cond }
				return ConditionStep()
			},
			set: { step = .condition($0) }
		)
	}

	private var conditionKindBinding: Binding<ConditionKind> {
		Binding(
			get: { conditionBinding.wrappedValue.kind },
			set: {
				var cond = conditionBinding.wrappedValue
				cond.kind = $0
				conditionBinding.wrappedValue = cond
			}
		)
	}

	private var conditionNegateBinding: Binding<Bool> {
		Binding(
			get: { conditionBinding.wrappedValue.negate },
			set: {
				var cond = conditionBinding.wrappedValue
				cond.negate = $0
				conditionBinding.wrappedValue = cond
			}
		)
	}

	private var conditionBundleBinding: Binding<String> {
		Binding(
			get: { conditionBinding.wrappedValue.bundleIdentifier },
			set: {
				var cond = conditionBinding.wrappedValue
				cond.bundleIdentifier = $0
				conditionBinding.wrappedValue = cond
			}
		)
	}

	private var conditionStartBinding: Binding<Date> {
		Binding(
			get: { Self.dateFromMinutes(conditionBinding.wrappedValue.startMinutes) },
			set: {
				var cond = conditionBinding.wrappedValue
				cond.startMinutes = Self.minutesFromDate($0)
				conditionBinding.wrappedValue = cond
			}
		)
	}

	private var conditionEndBinding: Binding<Date> {
		Binding(
			get: { Self.dateFromMinutes(conditionBinding.wrappedValue.endMinutes) },
			set: {
				var cond = conditionBinding.wrappedValue
				cond.endMinutes = Self.minutesFromDate($0)
				conditionBinding.wrappedValue = cond
			}
		)
	}

	private static func dateFromMinutes(_ minutes: Int) -> Date {
		Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
	}

	private static func minutesFromDate(_ date: Date) -> Int {
		let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
		return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
	}

	private var typeTextBinding: Binding<TypeTextStep> {
		Binding(
			get: {
				if case .typeText(let text) = step { return text }
				return TypeTextStep(text: "", mode: .paste, pressReturn: true)
			},
			set: { step = .typeText($0) }
		)
	}

	private var typeTextTextBinding: Binding<String> {
		Binding(
			get: { typeTextBinding.wrappedValue.text },
			set: {
				var text = typeTextBinding.wrappedValue
				text.text = $0
				typeTextBinding.wrappedValue = text
			}
		)
	}

	private var typeTextModeBinding: Binding<TextEntryMode> {
		Binding(
			get: { typeTextBinding.wrappedValue.mode },
			set: {
				var text = typeTextBinding.wrappedValue
				text.mode = $0
				typeTextBinding.wrappedValue = text
			}
		)
	}

	private var typeTextReturnBinding: Binding<Bool> {
		Binding(
			get: { typeTextBinding.wrappedValue.pressReturn },
			set: {
				var text = typeTextBinding.wrappedValue
				text.pressReturn = $0
				typeTextBinding.wrappedValue = text
			}
		)
	}

	private var openAppBinding: Binding<OpenAppStep> {
		Binding(
			get: {
				if case .openApp(let app) = step { return app }
				return OpenAppStep(bundleIdentifier: "")
			},
			set: { step = .openApp($0) }
		)
	}

	private var openAppBundleBinding: Binding<String> {
		Binding(
			get: { openAppBinding.wrappedValue.bundleIdentifier },
			set: {
				var app = openAppBinding.wrappedValue
				app.bundleIdentifier = $0
				openAppBinding.wrappedValue = app
			}
		)
	}

	private var openAppNewWindowBinding: Binding<Bool> {
		Binding(
			get: { openAppBinding.wrappedValue.openNewWindow },
			set: {
				var app = openAppBinding.wrappedValue
				app.openNewWindow = $0
				openAppBinding.wrappedValue = app
			}
		)
	}

	private var openURLBinding: Binding<String> {
		Binding(
			get: {
				if case .openURL(let url) = step { return url.url }
				return ""
			},
			set: { step = .openURL(OpenURLStep(url: $0)) }
		)
	}

	private var shellBinding: Binding<ShellCommandStep> {
		Binding(
			get: {
				if case .shellCommand(let shell) = step { return shell }
				return ShellCommandStep(command: "")
			},
			set: { step = .shellCommand($0) }
		)
	}

	private var shellCommandBinding: Binding<String> {
		Binding(
			get: { shellBinding.wrappedValue.command },
			set: {
				var shell = shellBinding.wrappedValue
				shell.command = $0
				shellBinding.wrappedValue = shell
			}
		)
	}

	private var shellPathBinding: Binding<String> {
		Binding(
			get: { shellBinding.wrappedValue.shellPath },
			set: {
				var shell = shellBinding.wrappedValue
				shell.shellPath = $0
				shellBinding.wrappedValue = shell
			}
		)
	}

	private var shellTimeoutBinding: Binding<Double> {
		Binding(
			get: { shellBinding.wrappedValue.timeoutSeconds },
			set: {
				var shell = shellBinding.wrappedValue
				shell.timeoutSeconds = max(1, $0)
				shellBinding.wrappedValue = shell
			}
		)
	}

	private var typeTextPaceBinding: Binding<Int> {
		Binding(
			get: {
				if case .typeText(let text) = step { return text.charactersPerMinute ?? 0 }
				return 0
			},
			set: { newValue in
				guard case .typeText(var text) = step else { return }
				text.charactersPerMinute = newValue > 0 ? newValue : nil
				step = .typeText(text)
			}
		)
	}

	private var webhookBinding: Binding<WebhookStep> {
		Binding(
			get: {
				if case .webhook(let webhook) = step { return webhook }
				return WebhookStep(url: "")
			},
			set: { step = .webhook($0) }
		)
	}

	private var webhookURLBinding: Binding<String> {
		Binding(
			get: { webhookBinding.wrappedValue.url },
			set: {
				var webhook = webhookBinding.wrappedValue
				webhook.url = $0
				webhookBinding.wrappedValue = webhook
			}
		)
	}

	private var webhookMethodBinding: Binding<WebhookMethod> {
		Binding(
			get: { webhookBinding.wrappedValue.method },
			set: {
				var webhook = webhookBinding.wrappedValue
				webhook.method = $0
				webhookBinding.wrappedValue = webhook
			}
		)
	}

	private var webhookBodyBinding: Binding<String> {
		Binding(
			get: { webhookBinding.wrappedValue.body ?? "" },
			set: {
				var webhook = webhookBinding.wrappedValue
				webhook.body = $0.isEmpty ? nil : $0
				webhookBinding.wrappedValue = webhook
			}
		)
	}

	private var customBinding: Binding<CustomStep> {
		Binding(
			get: {
				if case .custom(let custom) = step { return custom }
				return CustomStep(namespace: "")
			},
			set: { step = .custom($0) }
		)
	}

	private var customPayloadBinding: Binding<String> {
		Binding(
			get: { customBinding.wrappedValue.payload },
			set: {
				var custom = customBinding.wrappedValue
				custom.payload = $0
				customBinding.wrappedValue = custom
			}
		)
	}
}
