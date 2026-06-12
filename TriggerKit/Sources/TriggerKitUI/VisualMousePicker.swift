import SwiftUI
import TriggerKitCore

public struct VisualMousePicker: View {
	@Binding private var click: MouseClick

	public init(click: Binding<MouseClick>) {
		self._click = click
	}

	public var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			MouseButtonPicker(button: buttonBinding)
			Stepper("Clicks: \(click.clickCount)", value: clickCountBinding, in: 1...MouseClick.maximumClickCount)
				.font(.caption.weight(.semibold))
			ModifierSetEditor(modifiers: modifiersBinding)
		}
		.padding(10)
		.background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
		.clipShape(RoundedRectangle(cornerRadius: 8))
	}

	private var buttonBinding: Binding<MouseButton> {
		Binding(
			get: { click.button },
			set: { click.button = $0 }
		)
	}

	private var clickCountBinding: Binding<Int> {
		Binding(
			get: { click.clickCount },
			set: { click.clickCount = $0 }
		)
	}

	private var modifiersBinding: Binding<ModifierSet> {
		Binding(
			get: { click.modifiers },
			set: { click.modifiers = $0 }
		)
	}
}

public struct MouseButtonPicker: View {
	@Binding private var button: MouseButton
	@State private var showingMouse = false

	public init(button: Binding<MouseButton>) {
		self._button = button
	}

	public var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack {
				Text(button.displayName)
					.font(.system(size: 12, weight: .bold, design: .monospaced))
					.lineLimit(1)
				Spacer()
				Button {
					showingMouse = true
				} label: {
					Label("Show Mouse", systemImage: "computermouse")
				}
				.controlSize(.small)
				.popover(isPresented: $showingMouse, arrowEdge: .trailing) {
					ExpandedMouseButtonPicker(button: $button)
						.frame(width: 540)
						.padding(12)
				}
			}

			HStack(spacing: 6) {
				ForEach(MouseButton.allCases, id: \.self) { candidate in
					Button(candidate.displayName) {
						button = candidate
					}
					.font(.caption.weight(.bold))
					.padding(.horizontal, 10)
					.padding(.vertical, 6)
					.background(button == candidate ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
					.foregroundStyle(button == candidate ? .white : .primary)
					.clipShape(RoundedRectangle(cornerRadius: 6))
					.buttonStyle(.plain)
				}
			}
		}
	}
}

public struct ScrollDirectionPicker: View {
	@Binding private var scroll: MouseScroll
	@State private var showingMouse = false

	public init(scroll: Binding<MouseScroll>) {
		self._scroll = scroll
	}

	public var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack {
				Text(scroll.displaySummary)
					.font(.system(size: 12, weight: .bold, design: .monospaced))
					.lineLimit(1)
				Spacer()
				Button {
					showingMouse = true
				} label: {
					Label("Show Mouse", systemImage: "computermouse")
				}
				.controlSize(.small)
				.popover(isPresented: $showingMouse, arrowEdge: .trailing) {
					ExpandedMouseScrollPicker(scroll: $scroll)
						.frame(width: 420)
						.padding(12)
				}
			}

			scrollButton("Up", systemImage: "arrow.up", value: MouseScroll(deltaY: 4))
			HStack(spacing: 6) {
				scrollButton("Left", systemImage: "arrow.left", value: MouseScroll(deltaX: -4))
				scrollButton("Right", systemImage: "arrow.right", value: MouseScroll(deltaX: 4))
			}
			scrollButton("Down", systemImage: "arrow.down", value: MouseScroll(deltaY: -4))
		}
	}

	private func scrollButton(_ title: String, systemImage: String, value: MouseScroll) -> some View {
		Button {
			scroll = value
		} label: {
			Label(title, systemImage: systemImage)
				.labelStyle(.titleAndIcon)
				.font(.caption.weight(.bold))
				.frame(width: 108, height: 30)
				.background(scroll == value ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
				.foregroundStyle(scroll == value ? .white : .primary)
				.clipShape(RoundedRectangle(cornerRadius: 6))
		}
		.buttonStyle(.plain)
	}
}

private struct ExpandedMouseButtonPicker: View {
	@Binding var button: MouseButton
	@State private var hoveredButton: MouseButton?

	var body: some View {
		VStack(spacing: 14) {
			HStack(alignment: .top, spacing: 18) {
				mouseBody
				sideButtons
			}
		}
		.padding()
		.background(Color(nsColor: .windowBackgroundColor))
		.clipShape(RoundedRectangle(cornerRadius: 12))
		.overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.18)))
	}

	private var mouseBody: some View {
		VStack(spacing: 8) {
			HStack(spacing: 6) {
				mouseButton(.left, systemImage: "cursorarrow", label: "Left", width: 90, height: 64)
				mouseButton(.middle, systemImage: "circle.fill", label: "Middle", width: 72, height: 64)
				mouseButton(.right, systemImage: "cursorarrow", label: "Right", width: 90, height: 64)
			}

			RoundedRectangle(cornerRadius: 12)
				.fill(Color(nsColor: .controlBackgroundColor))
				.frame(width: 274, height: 72)
				.overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.25), lineWidth: 1))
		}
	}

	private var sideButtons: some View {
		VStack(spacing: 8) {
			mouseButton(.back, systemImage: "arrow.uturn.backward", label: "Back", width: 104, height: 54)
			mouseButton(.forward, systemImage: "arrow.uturn.forward", label: "Forward", width: 104, height: 54)
		}
	}

	private func mouseButton(_ candidate: MouseButton, systemImage: String, label: String, width: CGFloat, height: CGFloat) -> some View {
		let selected = button == candidate
		let hovered = hoveredButton == candidate
		return Button {
			button = candidate
		} label: {
			VStack(spacing: 5) {
				Image(systemName: systemImage)
					.font(.system(size: 14, weight: .semibold))
				Text(label)
					.font(.system(size: label.count > 8 ? 9 : 11, weight: .medium))
					.lineLimit(1)
					.minimumScaleFactor(0.8)
			}
			.frame(width: width, height: height)
			.background(selected ? Color.accentColor : hovered ? Color.accentColor.opacity(0.3) : Color(nsColor: .controlBackgroundColor))
			.foregroundStyle(selected ? .white : .primary)
			.clipShape(RoundedRectangle(cornerRadius: 6))
			.overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Color.accentColor : hovered ? Color.accentColor.opacity(0.5) : Color.gray.opacity(0.3), lineWidth: selected ? 2 : 1))
		}
		.buttonStyle(.plain)
		.onHover { hovering in
			hoveredButton = hovering ? candidate : nil
		}
	}
}

private struct ExpandedMouseScrollPicker: View {
	@Binding var scroll: MouseScroll
	@State private var hoveredScroll: MouseScroll?

	var body: some View {
		VStack(spacing: 14) {
			VStack(spacing: 6) {
				scrollButton("Scroll Up", systemImage: "arrow.up", value: MouseScroll(deltaY: 4), width: 112, height: 42)
				HStack(spacing: 6) {
					scrollButton("Left", systemImage: "arrow.left", value: MouseScroll(deltaX: -4), width: 72, height: 48)
					scrollButton("Right", systemImage: "arrow.right", value: MouseScroll(deltaX: 4), width: 72, height: 48)
				}
				scrollButton("Scroll Down", systemImage: "arrow.down", value: MouseScroll(deltaY: -4), width: 112, height: 42)
			}
		}
		.padding()
		.background(Color(nsColor: .windowBackgroundColor))
		.clipShape(RoundedRectangle(cornerRadius: 12))
		.overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.18)))
	}

	private func scrollButton(_ title: String, systemImage: String, value: MouseScroll, width: CGFloat, height: CGFloat) -> some View {
		let selected = scroll == value
		let hovered = hoveredScroll == value
		return Button {
			scroll = value
		} label: {
			VStack(spacing: 5) {
				Image(systemName: systemImage)
					.font(.system(size: 14, weight: .semibold))
				Text(title)
					.font(.system(size: title.count > 8 ? 9 : 11, weight: .medium))
					.lineLimit(1)
					.minimumScaleFactor(0.8)
			}
			.frame(width: width, height: height)
			.background(selected ? Color.accentColor : hovered ? Color.accentColor.opacity(0.3) : Color(nsColor: .controlBackgroundColor))
			.foregroundStyle(selected ? .white : .primary)
			.clipShape(RoundedRectangle(cornerRadius: 6))
			.overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Color.accentColor : hovered ? Color.accentColor.opacity(0.5) : Color.gray.opacity(0.3), lineWidth: selected ? 2 : 1))
		}
		.buttonStyle(.plain)
		.onHover { hovering in
			hoveredScroll = hovering ? value : nil
		}
	}
}
