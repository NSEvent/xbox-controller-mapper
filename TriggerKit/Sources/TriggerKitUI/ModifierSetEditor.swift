import SwiftUI
import TriggerKitCore

public struct ModifierSetEditor: View {
	@Binding private var modifiers: ModifierSet

	public init(modifiers: Binding<ModifierSet>) {
		self._modifiers = modifiers
	}

	public var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("Modifiers")
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)

			HStack(spacing: 6) {
				modifierButton("⌘", label: "Cmd", selection: sideBinding(\.command))
				modifierButton("⌥", label: "Opt", selection: sideBinding(\.option))
				modifierButton("⌃", label: "Ctrl", selection: sideBinding(\.control))
				modifierButton("⇧", label: "Shift", selection: sideBinding(\.shift))
				functionButton
			}
		}
	}

	private func modifierButton(
		_ symbol: String,
		label: String,
		selection: Binding<ModifierSidePreference?>
	) -> some View {
		Button {
			selection.wrappedValue = nextSide(after: selection.wrappedValue)
		} label: {
			HStack(spacing: 4) {
				Text(symbol)
					.font(.caption.weight(.bold))
				Text(displayText(for: selection.wrappedValue, label: label))
					.font(.caption.weight(.bold))
			}
			.lineLimit(1)
			.padding(.horizontal, 8)
			.padding(.vertical, 5)
			.background(selection.wrappedValue == nil ? Color(nsColor: .controlBackgroundColor) : Color.accentColor)
			.foregroundStyle(selection.wrappedValue == nil ? Color.primary : Color.white)
			.clipShape(RoundedRectangle(cornerRadius: 6))
		}
		.buttonStyle(.plain)
		.fixedSize(horizontal: true, vertical: false)
		.help("\(label): Click to cycle Off, Any, Left, Right")
		.accessibilityLabel("\(label): Click to cycle Off, Any, Left, Right")
	}

	private var functionButton: some View {
		Button {
			modifiers.function.toggle()
		} label: {
			Text("Fn")
				.font(.caption.weight(.bold))
				.lineLimit(1)
				.padding(.horizontal, 8)
				.padding(.vertical, 5)
				.background(modifiers.function ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
				.foregroundStyle(modifiers.function ? Color.white : Color.primary)
				.clipShape(RoundedRectangle(cornerRadius: 6))
		}
		.buttonStyle(.plain)
	}

	private func sideBinding(_ keyPath: WritableKeyPath<ModifierSet, ModifierSidePreference?>) -> Binding<ModifierSidePreference?> {
		Binding(
			get: { modifiers[keyPath: keyPath] },
			set: { modifiers[keyPath: keyPath] = $0 }
		)
	}

	private func displayText(for side: ModifierSidePreference?, label: String) -> String {
		guard let side else { return label }
		return "\(side.displayPrefix)\(label)"
	}

	private func nextSide(after side: ModifierSidePreference?) -> ModifierSidePreference? {
		switch side {
		case nil: return .any
		case .any: return .left
		case .left: return .right
		case .right: return nil
		}
	}
}
