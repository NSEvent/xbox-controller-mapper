import AppKit
import SwiftUI
import Vision
import XCTest
@testable import ControllerKeys

@MainActor
final class ControllerMappingGroupingRenderingTests: MappingEngineTestCase {
	private func installMappings() {
		var profile = Profile(name: "Mixed controllers")
		profile.controllerPreviewLayout = .footPedal
		profile.chordMappings = [
			ChordMapping(buttons: [.a, .b], keyCode: 12, hint: "Gamepad Alpha"),
			ChordMapping(buttons: [.footPedalLeft, .footPedalMiddle], keyCode: 13, hint: "Pedal Alpha"),
			ChordMapping(buttons: [.x, .y], keyCode: 14, hint: "Gamepad Beta"),
			ChordMapping(buttons: [.footPedalMiddle, .footPedalRight], keyCode: 15, hint: "Pedal Beta")
		]
		profile.sequenceMappings = [
			SequenceMapping(steps: [.a, .b], keyCode: 12, hint: "Gamepad Alpha"),
			SequenceMapping(steps: [.footPedalLeft, .footPedalMiddle], keyCode: 13, hint: "Pedal Alpha"),
			SequenceMapping(steps: [.x, .y], keyCode: 14, hint: "Gamepad Beta"),
			SequenceMapping(steps: [.footPedalMiddle, .footPedalRight], keyCode: 15, hint: "Pedal Beta")
		]
		profileManager.setActiveProfile(profile)
		controllerService.setXiaomiRemoteConnected(true)
	}

	func testActualChordAndSequenceTabsShowCompatibleSectionFirstInBothThemes() async throws {
		installMappings()
		for scheme in [ColorScheme.light, .dark] {
			try await render(ChordsTab(showingChordSheet: .constant(false), editingChord: .constant(nil)),
				scheme: scheme, name: "grouped-chords", expected: ["Pedal Alpha", "Pedal Beta", "Other mappings", "Gamepad Alpha", "Gamepad Beta"])
			try await render(SequencesTab(showingSequenceSheet: .constant(false), editingSequence: .constant(nil)),
				scheme: scheme, name: "grouped-sequences", expected: ["Pedal Alpha", "Pedal Beta", "Other mappings", "Gamepad Alpha", "Gamepad Beta"])
		}
	}

	func testMountedTabRegroupsWhenCanonicalControllerChangesWithoutChangingSavedOrder() async throws {
		installMappings()
		let saved = profileManager.activeProfile!.chordMappings
		try await render(ChordsTab(showingChordSheet: .constant(false), editingChord: .constant(nil)),
			scheme: .dark, name: "grouped-chords-switched", expected: ["Gamepad Alpha", "Gamepad Beta", "Other mappings", "Pedal Alpha", "Pedal Beta"],
			afterMount: { self.profileManager.setControllerPreviewLayout(.xbox) })
		XCTAssertEqual(profileManager.activeProfile?.chordMappings, saved)
	}

	func testStreamOverlayShowsHandsInsteadOfXboxWhenHandsAreSelected() async throws {
		controllerService.setXiaomiRemoteConnected(true)
		profileManager.setControllerPreviewLayout(.beamdeskHands)
		try await render(StreamOverlayView(profileManager: profileManager, controllerService: controllerService,
			inputLogService: InputLogService()).scaleEffect(2), scheme: .dark, name: "stream-hands",
			expected: ["BEAMDESK"])
	}

	func testMixedSequenceEditorAndListRenderPedalChordBoundariesInBothThemes() async throws {
		profileManager.setControllerPreviewLayout(.footPedal)
		let sequence = SequenceMapping(chordSteps: [SequenceStep([.footPedalLeft, .footPedalRight]), SequenceStep([.footPedalMiddle])], keyCode: 12)
		profileManager.addSequence(sequence)
		for scheme in [ColorScheme.light, .dark] {
			try await render(SequenceMappingSheet(editingSequence: sequence), scheme: scheme,
				name: "mixed-sequence-editor", expected: ["Left Pedal + Right Pedal", "Middle Pedal", "Try Sequence"])
			try await render(SequencesTab(showingSequenceSheet: .constant(false), editingSequence: .constant(nil)), scheme: scheme,
				name: "mixed-sequence-list", expected: ["Left Pedal + Right Pedal"])
		}
	}

	private func render<Content: View>(_ content: Content, scheme: ColorScheme, name: String, expected: [String], afterMount: (() -> Void)? = nil) async throws {
		let size = CGSize(width: 900, height: 760)
		let host = NSHostingView(rootView: content
			.environmentObject(controllerService).environmentObject(profileManager).environmentObject(mappingEngine)
			.frame(width: size.width, height: size.height)
			.background(scheme == .dark ? Color(white: 0.12) : Color(white: 0.96))
			.environment(\.colorScheme, scheme))
		let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
		window.isReleasedWhenClosed = false; window.contentView = host
		host.frame = CGRect(origin: .zero, size: size)
		defer { window.close() }
		await waitForTasks(0.2)
		if let afterMount { afterMount(); await waitForTasks(0.2) }
		host.layoutSubtreeIfNeeded()
		let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
		host.cacheDisplay(in: host.bounds, to: bitmap)
		let request = VNRecognizeTextRequest()
		request.recognitionLevel = .accurate
		request.recognitionLanguages = ["en-US"]
		try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
		let observations = (request.results ?? []).sorted { $0.boundingBox.midY > $1.boundingBox.midY }
		let lines = observations.compactMap { $0.topCandidates(1).first?.string }
		var previous = -1
		for label in expected {
			let index = lines.firstIndex(where: { $0.localizedCaseInsensitiveContains(label) })
			XCTAssertNotNil(index, "\(name) missing \(label): \(lines)")
			if let index { XCTAssertGreaterThan(index, previous, "\(name) section/order mismatch: \(lines)"); previous = index }
		}
		if let directory = ProcessInfo.processInfo.environment["CONTROLLERKEYS_AUDIT_SNAPSHOTS"] {
			let folder = URL(fileURLWithPath: directory, isDirectory: true)
			try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
			try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
				.write(to: folder.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png"))
		}
	}
}
