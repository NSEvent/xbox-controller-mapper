import XCTest
import AppKit
import SwiftUI
@testable import ControllerKeys

/// The hover Copy/Paste actions must never cover a mapping row's label: a long
/// custom hint ("Last Window") used to run underneath the side-by-side capsule.
@MainActor
final class MappingQuickActionLayoutTests: XCTestCase {
	private final class Frames {
		var label: CGRect = .zero
		var actions: CGRect = .zero
	}

	private struct FrameReader: View {
		let space: String
		let write: (CGRect) -> Void
		var body: some View {
			GeometryReader { proxy in
				Color.clear
					.onAppear { write(proxy.frame(in: .named(space))) }
					.onChange(of: proxy.frame(in: .named(space))) { _, frame in write(frame) }
			}
		}
	}

	/// Mirrors a reference row's label container, using the production column modifier.
	private func layOutRow(hint: String, width: CGFloat) async -> Frames {
		let frames = Frames()
		var mapping = KeyMapping.key(KeyCodeMapping.tab)
		mapping.hint = hint
		let row = HStack {
			MappingLabelView(mapping: mapping, font: .system(size: 15, weight: .semibold, design: .rounded))
				.background(FrameReader(space: "row") { frames.label = $0 })
			Spacer()
		}
		.padding(.vertical, 8)
		.padding(.leading, 12)
		.mappingQuickActionColumn {
			MappingQuickActionsStack(onCopy: {}, onPaste: {})
				.background(FrameReader(space: "row") { frames.actions = $0 })
		}
		.frame(width: width)
		.coordinateSpace(name: "row")

		let host = NSHostingView(rootView: row)
		let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: 80),
			styleMask: [.borderless], backing: .buffered, defer: false)
		window.isReleasedWhenClosed = false
		window.contentView = host
		host.layoutSubtreeIfNeeded()
		_ = await waitForCondition(timeout: 1) { frames.label != .zero && frames.actions != .zero }
		window.close()
		return frames
	}

	func testLongHintStopsShortOfStackedCopyPasteColumn() async {
		for width: CGFloat in [150, 200, 260] {
			let frames = await layOutRow(hint: "Last Window Last Window Last Window", width: width)
			XCTAssertNotEqual(frames.label, .zero)
			XCTAssertNotEqual(frames.actions, .zero)
			XCTAssertLessThanOrEqual(frames.label.maxX, frames.actions.minX,
				"Label \(frames.label) must not run under the Copy/Paste column \(frames.actions) at width \(width)")
		}
	}

	func testCopyAndPasteStackVerticallyWithinReservedColumn() async {
		let frames = await layOutRow(hint: "Last Window", width: 200)
		XCTAssertGreaterThan(frames.actions.height, frames.actions.width, "Copy and Paste should be stacked")
		XCTAssertLessThanOrEqual(frames.actions.width,
			MappingQuickActionLayout.reservedTrailingWidth - MappingQuickActionLayout.edgeInset)
		XCTAssertGreaterThanOrEqual(frames.actions.minY, 0, "Column should stay inside a one-line row")
	}
}
