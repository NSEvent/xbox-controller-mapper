import XCTest
import AppKit
import SwiftUI
@testable import ControllerKeys

/// Holding a layer activator must switch the Buttons editor to that layer's
/// mappings and return to Base on release (regressed 2026-09-03, when the
/// editor stopped following the controller and only showed a banner).
@MainActor
final class RuntimeLayerSelectionTests: MappingEngineTestCase {
	private final class Selection { var layerId: UUID? }

	private func hostEditor(_ selection: Selection) -> NSWindow {
		let binding = Binding(get: { selection.layerId }, set: { selection.layerId = $0 })
		let host = NSHostingView(rootView: Color.clear
			.frame(width: 40, height: 40)
			.modifier(RuntimeLayerSelectionModifier(mappingEngine: mappingEngine, selectedLayerId: binding)))
		let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 40, height: 40),
			styleMask: [.borderless], backing: .buffered, defer: false)
		window.isReleasedWhenClosed = false
		window.contentView = host
		host.layoutSubtreeIfNeeded()
		return window
	}

	func testHoldingLayerActivatorShowsThatLayerAndReleaseReturnsToBase() async throws {
		let layer = Layer(name: "Combat", activatorButton: .leftBumper, buttonMappings: [.a: .key(50)])
		profileManager.setActiveProfile(Profile(name: "LayerFollow", buttonMappings: [.a: .key(10)], layers: [layer]))
		let selection = Selection()
		let window = hostEditor(selection)
		defer { window.close() }
		await waitForTasks(0.1)
		XCTAssertNil(selection.layerId)

		controllerService.buttonPressed(.leftBumper)
		let followed = await waitForCondition { selection.layerId == layer.id }
		XCTAssertTrue(followed, "Holding the activator should show the activated layer's mappings")

		controllerService.buttonReleased(.leftBumper)
		let returned = await waitForCondition { selection.layerId == nil }
		XCTAssertTrue(returned, "Releasing the activator should return the editor to Base")
	}

	func testEditorOpensOnLayerAlreadyHeld() async throws {
		let layer = Layer(name: "Combat", activatorButton: .leftBumper, buttonMappings: [.a: .key(50)])
		profileManager.setActiveProfile(Profile(name: "LayerFollow", buttonMappings: [.a: .key(10)], layers: [layer]))
		await waitForTasks(0.05)
		controllerService.buttonPressed(.leftBumper)
		let active = await waitForCondition { [self] in mappingEngine.activeManualLayerId == layer.id }
		XCTAssertTrue(active)

		let selection = Selection()
		let window = hostEditor(selection)
		defer { window.close() }
		let followed = await waitForCondition { selection.layerId == layer.id }
		XCTAssertTrue(followed, "Opening the editor mid-hold should show the held layer")
		controllerService.buttonReleased(.leftBumper)
	}
}
