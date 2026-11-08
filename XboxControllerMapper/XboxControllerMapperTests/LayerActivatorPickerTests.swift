import AppKit
import SwiftUI
import Vision
import XCTest
@testable import ControllerKeys

@MainActor
final class LayerActivatorPickerTests: MappingEngineTestCase {
	func testPedalOffersOnlyItsThreeButtonsAndExcludesUsedActivators() {
		let descriptor = ControllerVisualDescriptor(family: .footPedal)
		XCTAssertEqual(LayerActivatorOptions.buttons(for: descriptor, excluding: []), ControllerButton.footPedalButtons)
		XCTAssertEqual(LayerActivatorOptions.buttons(for: descriptor, excluding: [.footPedalMiddle]), [.footPedalLeft, .footPedalRight])
		XCTAssertNil(LayerActivatorOptions.buttons(for: descriptor, excluding: Set(ControllerButton.footPedalButtons)).first)
	}

	func testEveryLayoutOffersOnlySupportedPhysicalControls() {
		for layout in ControllerPreviewLayout.concreteLayouts {
			let descriptor = ControllerVisualDescriptor.concrete(for: layout)!
			let options = LayerActivatorOptions.buttons(for: descriptor, excluding: [])
			XCTAssertEqual(Set(options), descriptor.supportedButtons.filter { !$0.isGestureButton && !$0.isJoystickDirection }, "\(layout)")
			XCTAssertEqual(options.count, Set(options).count)
		}
		let xiaomi = LayerActivatorOptions.buttons(for: .init(family: .xiaomiRemote), excluding: [])
		XCTAssertTrue(xiaomi.contains(.xiaomiOK))
		XCTAssertTrue(xiaomi.contains(.dpadUp))
		XCTAssertFalse(xiaomi.contains(.leftBumper))
	}

	func testSwitchingDevicesClearsNewInvalidSelectionButPreservesSavedAssignment() {
		let options = ControllerButton.footPedalButtons
		XCTAssertNil(LayerActivatorOptions.reconciled(.leftBumper, options: options, existing: nil))
		XCTAssertEqual(LayerActivatorOptions.reconciled(.leftBumper, options: options, existing: .leftBumper), .leftBumper)
		XCTAssertEqual(LayerActivatorOptions.reconciled(.footPedalLeft, options: options, existing: nil), .footPedalLeft)
		XCTAssertNil(LayerActivatorOptions.reconciled(nil, options: options, existing: .leftBumper))
	}

	func testAddAndEditSheetsVisiblyUseSelectedPedalWithXiaomiConnected() async throws {
		controllerService.setXiaomiRemoteConnected(true)
		profileManager.setControllerPreviewLayout(.footPedal)
		for scheme in [ColorScheme.light, .dark] {
			try await assertRendered(AddLayerSheet(), scheme: scheme, name: "add-layer", expected: ["VEC", "Pedal", "Left Pedal"])
			try await assertRendered(EditLayerSheet(layer: Layer(name: "Pedal layer", activatorButton: .footPedalRight)),
				scheme: scheme, name: "edit-layer", expected: ["VEC", "Pedal", "Right Pedal"])
		}
	}

	func testOpenAddSheetUpdatesWhenPedalBecomesActive() async throws {
		profileManager.bindControllerPreview(to: controllerService)
		controllerService.setXiaomiRemoteConnected(true)
		try await assertRendered(AddLayerSheet(), scheme: .light, name: "switch-open-layer",
			expected: ["VEC", "Pedal", "None (assign later)"], afterMount: {
				self.controllerService.setFootPedalConnected(true)
			})
	}

	private func assertRendered<Content: View>(_ content: Content, scheme: ColorScheme, name: String,
		expected: [String], afterMount: (() -> Void)? = nil) async throws {
		let size = CGSize(width: 450, height: 650)
		let host = NSHostingView(rootView: content
			.environmentObject(controllerService).environmentObject(profileManager).environmentObject(mappingEngine)
			.frame(width: size.width, height: size.height)
			.background(scheme == .dark ? Color(white: 0.12) : Color(white: 0.96))
			.environment(\.colorScheme, scheme))
		let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
		window.isReleasedWhenClosed = false
		window.contentView = host
		host.frame = CGRect(origin: .zero, size: size)
		defer { window.close() }
		await waitForTasks(0.15)
		if let afterMount { afterMount(); await waitForTasks(0.15) }
		host.layoutSubtreeIfNeeded()
		let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
		host.cacheDisplay(in: host.bounds, to: bitmap)
		let request = VNRecognizeTextRequest()
		request.recognitionLevel = .accurate
		request.recognitionLanguages = ["en-US"]
		try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
		let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
		// Check device identity and selected controls without depending on OCR
		// distinguishing every letter of the small model-name caption.
		for label in expected { XCTAssertTrue(text.contains(label), "\(name) must show \(label). Actual:\n\(text)") }
		if let directory = ProcessInfo.processInfo.environment["CONTROLLERKEYS_LAYER_SNAPSHOTS"] {
			let folder = URL(fileURLWithPath: directory, isDirectory: true)
			try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
			try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
				.write(to: folder.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png"))
		}
	}
}
