import Carbon.HIToolbox
import SwiftUI
import TriggerKitCore

struct ExpandedKeyboardPicker: View {
	@Binding var keyStroke: KeyStroke
	let showsModifiers: Bool
	@State private var hoveredID: String?

	private let f1to12Codes = [
		kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
		kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12
	]

	private let numberKeyCodes = [
		kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
		kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9, kVK_ANSI_0
	]

	var body: some View {
		VStack(spacing: 12) {
			mediaKeysRow
			extendedFunctionKeyRow
			functionKeyRow

			VStack(spacing: 4) {
				numberRow
				qwertyRow
				asdfRow
				zxcvRow
				bottomRow
			}

			navigationKeyRow

			if showsModifiers {
				modifierRow
			}
		}
		.padding()
		.background(Color(nsColor: .windowBackgroundColor))
		.clipShape(RoundedRectangle(cornerRadius: 12))
		.overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.18)))
	}

	private var mediaKeysRow: some View {
		VStack(alignment: .leading, spacing: 4) {
			Text("Media Controls")
				.font(.caption)
				.foregroundStyle(.secondary)

			HStack(spacing: 20) {
				HStack(spacing: 4) {
					mediaKeyButton(.mediaPrevious, symbol: "backward.end.fill", label: "Prev")
					mediaKeyButton(.mediaRewind, symbol: "backward.fill", label: "Rew")
					mediaKeyButton(.mediaPlayPause, symbol: "playpause.fill", label: "Play")
					mediaKeyButton(.mediaFastForward, symbol: "forward.fill", label: "FF")
					mediaKeyButton(.mediaNext, symbol: "forward.end.fill", label: "Next")
				}

				HStack(spacing: 4) {
					mediaKeyButton(.volumeMute, symbol: "speaker.slash.fill", label: "Mute")
					mediaKeyButton(.volumeDown, symbol: "speaker.wave.1.fill", label: "Vol-")
					mediaKeyButton(.volumeUp, symbol: "speaker.wave.3.fill", label: "Vol+")
				}

				HStack(spacing: 4) {
					mediaKeyButton(.brightnessDown, symbol: "sun.min.fill", label: "Dim")
					mediaKeyButton(.brightnessUp, symbol: "sun.max.fill", label: "Bright")
				}
			}
		}
	}

	private var extendedFunctionKeyRow: some View {
		VStack(alignment: .leading, spacing: 4) {
			Text("Extended Function Keys (F13-F20)")
				.font(.caption)
				.foregroundStyle(.secondary)

			HStack(spacing: 4) {
				ForEach(13...20, id: \.self) { number in
					keyButton(functionKey(number), width: 42)
				}
			}
		}
	}

	private var functionKeyRow: some View {
		HStack(spacing: 4) {
			keyButton(.escape, label: "Esc", width: 45)

			Spacer().frame(width: 20)

			ForEach(0..<4, id: \.self) { index in
				keyButton(key("F\(index + 1)", f1to12Codes[index]), width: 40)
			}

			Spacer().frame(width: 10)

			ForEach(4..<8, id: \.self) { index in
				keyButton(key("F\(index + 1)", f1to12Codes[index]), width: 40)
			}

			Spacer().frame(width: 10)

			ForEach(8..<12, id: \.self) { index in
				keyButton(key("F\(index + 1)", f1to12Codes[index]), width: 40)
			}
		}
	}

	private var numberRow: some View {
		HStack(spacing: 4) {
			keyButton(key("`", kVK_ANSI_Grave, id: "grave"))

			ForEach(0..<10, id: \.self) { index in
				let display = index == 9 ? "0" : "\(index + 1)"
				keyButton(key(display, numberKeyCodes[index]))
			}

			keyButton(key("-", kVK_ANSI_Minus, id: "minus"))
			keyButton(key("=", kVK_ANSI_Equal, id: "equal"))
			keyButton(.delete, label: "Delete", width: 60)
		}
	}

	private var qwertyRow: some View {
		HStack(spacing: 4) {
			keyButton(.tab, width: 50)
			let keys = [
				("Q", kVK_ANSI_Q), ("W", kVK_ANSI_W), ("E", kVK_ANSI_E), ("R", kVK_ANSI_R), ("T", kVK_ANSI_T),
				("Y", kVK_ANSI_Y), ("U", kVK_ANSI_U), ("I", kVK_ANSI_I), ("O", kVK_ANSI_O), ("P", kVK_ANSI_P)
			]
			ForEach(keys, id: \.0) { item in
				keyButton(key(item.0, item.1))
			}
			keyButton(key("[", kVK_ANSI_LeftBracket, id: "left-bracket"))
			keyButton(key("]", kVK_ANSI_RightBracket, id: "right-bracket"))
			keyButton(key("\\", kVK_ANSI_Backslash, id: "backslash"), width: 50)
		}
	}

	private var asdfRow: some View {
		HStack(spacing: 4) {
			keyButton(.capsLock, label: "Caps", width: 60)
			let keys = [
				("A", kVK_ANSI_A), ("S", kVK_ANSI_S), ("D", kVK_ANSI_D), ("F", kVK_ANSI_F), ("G", kVK_ANSI_G),
				("H", kVK_ANSI_H), ("J", kVK_ANSI_J), ("K", kVK_ANSI_K), ("L", kVK_ANSI_L)
			]
			ForEach(keys, id: \.0) { item in
				keyButton(key(item.0, item.1))
			}
			keyButton(key(";", kVK_ANSI_Semicolon, id: "semicolon"))
			keyButton(key("'", kVK_ANSI_Quote, id: "quote"))
			keyButton(.return, width: 70)
		}
	}

	private var zxcvRow: some View {
		HStack(spacing: 4) {
			modifierKeyButton("⇧ Shift", kind: .shift, side: .left, fallback: leftModifier(.shift), width: 80)
			let keys = [
				("Z", kVK_ANSI_Z), ("X", kVK_ANSI_X), ("C", kVK_ANSI_C), ("V", kVK_ANSI_V),
				("B", kVK_ANSI_B), ("N", kVK_ANSI_N), ("M", kVK_ANSI_M)
			]
			ForEach(keys, id: \.0) { item in
				keyButton(key(item.0, item.1))
			}
			keyButton(key(",", kVK_ANSI_Comma, id: "comma"))
			keyButton(key(".", kVK_ANSI_Period, id: "period"))
			keyButton(key("/", kVK_ANSI_Slash, id: "slash"))
			modifierKeyButton("⇧ Shift", kind: .shift, side: .right, fallback: rightModifier(.shift), width: 80)
		}
	}

	private var bottomRow: some View {
		HStack(spacing: 4) {
			functionModifierButton(width: 40)
			modifierKeyButton("⌃", kind: .control, side: .left, fallback: leftModifier(.control), width: 40)
			modifierKeyButton("⌥", kind: .option, side: .left, fallback: leftModifier(.option), width: 40)
			modifierKeyButton("⌘", kind: .command, side: .left, fallback: leftModifier(.command), width: 50)

			keyButton(.space, width: 200)

			modifierKeyButton("⌘", kind: .command, side: .right, fallback: rightModifier(.command), width: 50)
			modifierKeyButton("⌥", kind: .option, side: .right, fallback: rightModifier(.option), width: 40)

			VStack(spacing: 2) {
				keyButton(arrow("Up", kVK_UpArrow, id: "up"), label: "↑", width: 30, height: 15)
				HStack(spacing: 2) {
					keyButton(arrow("Left", kVK_LeftArrow, id: "left"), label: "←", width: 30, height: 15)
					keyButton(arrow("Down", kVK_DownArrow, id: "down"), label: "↓", width: 30, height: 15)
					keyButton(arrow("Right", kVK_RightArrow, id: "right"), label: "→", width: 30, height: 15)
				}
			}
		}
	}

	private var navigationKeyRow: some View {
		VStack(spacing: 4) {
			HStack(spacing: 4) {
				Spacer()
				VStack(alignment: .leading, spacing: 4) {
					Text("Navigation & Special Keys")
						.font(.caption)
						.foregroundStyle(.secondary)

					HStack(spacing: 4) {
						keyButton(.help, width: 45)
						keyButton(key("Home", kVK_Home, id: "home"), width: 45)
						keyButton(key("End", kVK_End, id: "end"), width: 45)
						keyButton(key("Page Up", kVK_PageUp, id: "page-up"), label: "PgUp", width: 45)
						keyButton(key("Page Down", kVK_PageDown, id: "page-down"), label: "PgDn", width: 45)
						keyButton(.forwardDelete, label: "Del", width: 45)
					}
				}
				Spacer()
			}
		}
	}

	private var modifierRow: some View {
		HStack(spacing: 16) {
			modifierToggle("⌘ Command", kind: .command)
			modifierToggle("⌥ Option", kind: .option)
			modifierToggle("⇧ Shift", kind: .shift)
			modifierToggle("⌃ Control", kind: .control)
			functionToggle
			Spacer()
		}
		.padding(.top, 8)
	}

	private func keyButton(_ key: TriggerKey, label: String? = nil, width: CGFloat = 35, height: CGFloat = 32) -> some View {
		let id = "key-\(key.id)"
		let selected = keyStroke.key.keyCode == key.keyCode
		return keyboardButton(
			id: id,
			label: label ?? key.displayName,
			width: width,
			height: height,
			selected: selected
		) {
			keyStroke.key = key
		}
	}

	private func mediaKeyButton(_ key: TriggerKey, symbol: String, label: String) -> some View {
		let id = "key-\(key.id)"
		let selected = keyStroke.key.keyCode == key.keyCode
		return Button {
			keyStroke.key = key
		} label: {
			VStack(spacing: 1) {
				Image(systemName: symbol)
					.font(.system(size: 12))
				Text(label)
					.font(.system(size: 8))
			}
			.frame(width: 45, height: 32)
			.background(backgroundColor(selected: selected, hovered: hoveredID == id))
			.foregroundStyle(selected ? .white : .primary)
			.clipShape(RoundedRectangle(cornerRadius: 4))
			.overlay(RoundedRectangle(cornerRadius: 4).stroke(borderColor(selected: selected, hovered: hoveredID == id), lineWidth: selected ? 2 : 1))
		}
		.buttonStyle(.plain)
		.onHover { hovering in
			hoveredID = hovering ? id : nil
		}
	}

	private func modifierKeyButton(
		_ label: String,
		kind: KeyboardModifierKind,
		side: ModifierSidePreference,
		fallback: TriggerKey,
		width: CGFloat
	) -> some View {
		let id = "modifier-\(kind.rawValue)-\(side.rawValue)"
		let selected = showsModifiers ? modifierIsHighlighted(kind, side: side) : keyStroke.key.keyCode == fallback.keyCode
		return keyboardButton(
			id: id,
			label: label,
			width: width,
			height: 32,
			selected: selected
		) {
			if showsModifiers {
				toggleModifier(kind, side: side)
			} else {
				keyStroke.key = fallback
			}
		}
	}

	private func functionModifierButton(width: CGFloat) -> some View {
		let selected = showsModifiers ? keyStroke.modifiers.function : keyStroke.key.keyCode == TriggerKey.function.keyCode
		return keyboardButton(
			id: "modifier-function",
			label: "Fn",
			width: width,
			height: 32,
			selected: selected
		) {
			if showsModifiers {
				keyStroke.modifiers.function.toggle()
			} else {
				keyStroke.key = .function
			}
		}
	}

	private func keyboardButton(
		id: String,
		label: String,
		width: CGFloat,
		height: CGFloat,
		selected: Bool,
		action: @escaping () -> Void
	) -> some View {
		Button(action: action) {
			Text(label)
				.font(.system(size: fontSize(for: label), weight: .medium))
				.lineLimit(1)
				.minimumScaleFactor(0.65)
				.frame(width: width, height: height)
				.background(backgroundColor(selected: selected, hovered: hoveredID == id))
				.foregroundStyle(selected ? .white : .primary)
				.clipShape(RoundedRectangle(cornerRadius: 4))
				.overlay(RoundedRectangle(cornerRadius: 4).stroke(borderColor(selected: selected, hovered: hoveredID == id), lineWidth: selected ? 2 : 1))
		}
		.buttonStyle(.plain)
		.onHover { hovering in
			hoveredID = hovering ? id : nil
		}
	}

	private func modifierToggle(_ label: String, kind: KeyboardModifierKind) -> some View {
		let selection = modifierSelection(kind)
		return HStack(spacing: 8) {
			Button {
				setModifier(kind, to: selection == nil ? .any : nil)
			} label: {
				HStack(spacing: 4) {
					Image(systemName: selection == nil ? "square" : "checkmark.square.fill")
						.foregroundStyle(selection == nil ? .secondary : Color.accentColor)
					Text(label)
						.font(.caption)
						.lineLimit(1)
				}
			}
			.buttonStyle(.plain)

			if selection != nil {
				HStack(spacing: 2) {
					sideChip("Any", value: .any, kind: kind)
					sideChip("L", value: .left, kind: kind)
					sideChip("R", value: .right, kind: kind)
				}
			}
		}
		.fixedSize(horizontal: true, vertical: false)
	}

	private var functionToggle: some View {
		Button {
			keyStroke.modifiers.function.toggle()
		} label: {
			HStack(spacing: 4) {
				Image(systemName: keyStroke.modifiers.function ? "checkmark.square.fill" : "square")
					.foregroundStyle(keyStroke.modifiers.function ? Color.accentColor : .secondary)
				Text("Fn")
					.font(.caption)
			}
		}
		.buttonStyle(.plain)
	}

	private func sideChip(_ label: String, value: ModifierSidePreference, kind: KeyboardModifierKind) -> some View {
		let selected = modifierSelection(kind) == value
		return Button {
			setModifier(kind, to: value)
		} label: {
			Text(label)
				.font(.system(size: 9, weight: .semibold))
				.lineLimit(1)
				.padding(.horizontal, 5)
				.padding(.vertical, 2)
				.background(selected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
				.foregroundStyle(selected ? .white : .secondary)
				.clipShape(RoundedRectangle(cornerRadius: 3))
				.overlay(RoundedRectangle(cornerRadius: 3).stroke(selected ? Color.accentColor : Color.gray.opacity(0.4), lineWidth: 1))
		}
		.buttonStyle(.plain)
	}

	private func toggleModifier(_ kind: KeyboardModifierKind, side: ModifierSidePreference) {
		if modifierSelection(kind) == side {
			setModifier(kind, to: nil)
		} else {
			setModifier(kind, to: side)
		}
	}

	private func modifierSelection(_ kind: KeyboardModifierKind) -> ModifierSidePreference? {
		switch kind {
		case .command: return keyStroke.modifiers.command
		case .option: return keyStroke.modifiers.option
		case .control: return keyStroke.modifiers.control
		case .shift: return keyStroke.modifiers.shift
		}
	}

	private func setModifier(_ kind: KeyboardModifierKind, to value: ModifierSidePreference?) {
		switch kind {
		case .command: keyStroke.modifiers.command = value
		case .option: keyStroke.modifiers.option = value
		case .control: keyStroke.modifiers.control = value
		case .shift: keyStroke.modifiers.shift = value
		}
	}

	private func modifierIsHighlighted(_ kind: KeyboardModifierKind, side: ModifierSidePreference) -> Bool {
		let selection = modifierSelection(kind)
		return selection == .any || selection == side
	}

	private func functionKey(_ number: Int) -> TriggerKey {
		let codes = [
			13: kVK_F13, 14: kVK_F14, 15: kVK_F15, 16: kVK_F16,
			17: kVK_F17, 18: kVK_F18, 19: kVK_F19, 20: kVK_F20
		]
		return key("F\(number)", codes[number] ?? kVK_F13)
	}

	private func arrow(_ name: String, _ code: Int, id: String) -> TriggerKey {
		key("\(name) Arrow", code, id: id)
	}

	private func leftModifier(_ kind: KeyboardModifierKind) -> TriggerKey {
		switch kind {
		case .command: return TriggerKey(id: "left-command", keyCode: UInt16(kVK_Command), displayName: "Left Command")
		case .option: return TriggerKey(id: "left-option", keyCode: UInt16(kVK_Option), displayName: "Left Option")
		case .control: return TriggerKey(id: "left-control", keyCode: UInt16(kVK_Control), displayName: "Left Control")
		case .shift: return TriggerKey(id: "left-shift", keyCode: UInt16(kVK_Shift), displayName: "Left Shift")
		}
	}

	private func rightModifier(_ kind: KeyboardModifierKind) -> TriggerKey {
		switch kind {
		case .command: return TriggerKey(id: "right-command", keyCode: UInt16(kVK_RightCommand), displayName: "Right Command")
		case .option: return TriggerKey(id: "right-option", keyCode: UInt16(kVK_RightOption), displayName: "Right Option")
		case .control: return TriggerKey(id: "right-control", keyCode: UInt16(kVK_RightControl), displayName: "Right Control")
		case .shift: return TriggerKey(id: "right-shift", keyCode: UInt16(kVK_RightShift), displayName: "Right Shift")
		}
	}

	private func key(_ label: String, _ code: Int, id: String? = nil) -> TriggerKey {
		TriggerKey.catalogKey(keyCode: UInt16(code)) ??
			TriggerKey(id: id ?? label.lowercased(), keyCode: UInt16(code), displayName: label)
	}

	private func fontSize(for label: String) -> CGFloat {
		if label.count > 4 { return 9 }
		if label.count > 2 { return 10 }
		return 12
	}

	private func backgroundColor(selected: Bool, hovered: Bool) -> Color {
		if selected { return .accentColor }
		if hovered { return Color.accentColor.opacity(0.3) }
		return Color(nsColor: .controlBackgroundColor)
	}

	private func borderColor(selected: Bool, hovered: Bool) -> Color {
		if selected { return .accentColor }
		if hovered { return Color.accentColor.opacity(0.5) }
		return Color.gray.opacity(0.3)
	}
}

private enum KeyboardModifierKind: String {
	case command
	case option
	case control
	case shift
}
