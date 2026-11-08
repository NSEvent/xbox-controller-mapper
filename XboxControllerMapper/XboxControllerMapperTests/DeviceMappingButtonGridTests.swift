import AppKit
import SwiftUI
import Vision
import XCTest
@testable import ControllerKeys

@MainActor
final class DeviceMappingButtonGridTests: MappingEngineTestCase {
	func testFootPedalPickerContainsExactlyThreePedals() {
		let descriptor = ControllerVisualDescriptor(family: .footPedal)
		XCTAssertTrue(descriptor.usesCompactMappingButtonGrid)
		let buttons = descriptor.mappingPickerButtons(joystickSettings: .default)
		XCTAssertEqual(buttons, [.footPedalLeft, .footPedalMiddle, .footPedalRight])
		XCTAssertEqual(buttons.map(descriptor.buttonLabel), ["Left Pedal", "Middle Pedal", "Right Pedal"])
	}

	func testNonGamepadPickersUseTheirActualControls() {
		for layout: ControllerPreviewLayout in [.footPedal, .ouraRing, .s29Ring, .beamdeskHands, .xiaomiRemote, .appleTVRemote, .wiimote, .eightBitDoZero2, .eightBitDoMicro] {
			let descriptor = ControllerVisualDescriptor.concrete(for: layout)!
			XCTAssertTrue(descriptor.usesCompactMappingButtonGrid, "\(layout)")
			let buttons = Set(descriptor.mappingPickerButtons(joystickSettings: .default))
			XCTAssertEqual(buttons, descriptor.supportedButtons.filter { !$0.isJoystickDirection && !$0.isGestureButton }, "\(layout)")
		}
	}

	func testAddChordAndSequenceActuallyRenderPedalLabelsInBothThemes() async throws {
		profileManager.setControllerPreviewLayout(.footPedal)
		// Deliberately retain an Xbox hardware identity: the selected pedal
		// preview must drive the real sheets, not only the descriptor resolver.
		controllerService.storage.lock.withLock { controllerService.storage.applyControllerTypeLocked(.xbox) }
		for scheme in [ColorScheme.light, .dark] {
			try await assertPedalLabels(ChordMappingSheet(), scheme: scheme, name: "add-chord")
			try await assertPedalLabels(SequenceMappingSheet(), scheme: scheme, name: "add-sequence")
		}
	}

	func testEditChordAndSequenceActuallyRenderPedalLabels() async throws {
		profileManager.setControllerPreviewLayout(.footPedal)
		let chord = ChordMapping(buttons: [.footPedalLeft, .footPedalRight], keyCode: 0)
		let sequence = SequenceMapping(steps: [.footPedalLeft, .footPedalMiddle, .footPedalRight], keyCode: 0)
		try await assertPedalLabels(ChordMappingSheet(editingChord: chord), scheme: .light, name: "edit-chord")
		try await assertPedalLabels(SequenceMappingSheet(editingSequence: sequence), scheme: .light, name: "edit-sequence")
	}

	private func assertPedalLabels<Content: View>(_ content: Content, scheme: ColorScheme, name: String) async throws {
		let size = CGSize(width: 850, height: 820)
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
		host.layoutSubtreeIfNeeded()
		let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
		host.cacheDisplay(in: host.bounds, to: bitmap)
		let image = try XCTUnwrap(bitmap.cgImage)
		let request = VNRecognizeTextRequest()
		request.recognitionLevel = .accurate
		request.recognitionLanguages = ["en-US"]
		try VNImageRequestHandler(cgImage: image).perform([request])
		let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
		for label in ["Left Pedal", "Middle Pedal", "Right Pedal"] {
			XCTAssertTrue(text.contains(label), "\(name) must visibly render \(label). Actual text:\n\(text)")
		}
		if let directory = ProcessInfo.processInfo.environment["CONTROLLERKEYS_PEDAL_SNAPSHOTS"] {
			let folder = URL(fileURLWithPath: directory, isDirectory: true)
			try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
			try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
				.write(to: folder.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png"))
		}
	}
}
