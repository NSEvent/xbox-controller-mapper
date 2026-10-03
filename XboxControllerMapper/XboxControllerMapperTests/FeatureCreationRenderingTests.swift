import AppKit
import SwiftUI
import XCTest
@testable import ControllerKeys

@MainActor
final class FeatureCreationRenderingTests: MappingEngineTestCase {
	private struct ShortcutListRunner: ShortcutProcessRunning {
		func run(arguments: [String], timeout: TimeInterval) async throws -> String { "Morning Routine\nSave Selected Text\n" }
	}
	func testGuidedCreationAndCalibrationRenderInBothThemes() async throws {
		for scheme in [ColorScheme.light, .dark] {
			try await render(ShortcutActionPicker(name: .constant("Missing Workflow"), shortcuts: NativeShortcutService(runner: ShortcutListRunner())),
						 size: CGSize(width: 520, height: 250), scheme: scheme, label: "shortcuts")
			try await render(PhysicalInputCaptureBar(session: PhysicalInputCaptureSession()),
						 size: CGSize(width: 650, height: 90), scheme: scheme, label: "press-to-edit")
			try await render(GuidedPresetSheet(), size: CGSize(width: 570, height: 640), scheme: scheme, label: "guided-preset")
			try await render(StickCalibrationSheet(side: .left), size: CGSize(width: 560, height: 760), scheme: scheme, label: "stick-calibration")
			try await render(TriggerMIDIEditor(title: "Left Trigger", configuration: .constant(TriggerMIDIConfiguration())),
							 size: CGSize(width: 560, height: 260), scheme: scheme, label: "trigger-midi")
		}
	}

	private func render<Content: View>(_ content: Content, size: CGSize, scheme: ColorScheme, label: String) async throws {
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
		XCTAssertGreaterThanOrEqual(bitmap.pixelsWide, Int(size.width))
		if let directory = ProcessInfo.processInfo.environment["CONTROLLERKEYS_FEATURE_SNAPSHOTS"] {
			let folder = URL(fileURLWithPath: directory, isDirectory: true)
			try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
			try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
				.write(to: folder.appendingPathComponent("\(label)-\(scheme == .dark ? "dark" : "light").png"))
		}
	}
}
