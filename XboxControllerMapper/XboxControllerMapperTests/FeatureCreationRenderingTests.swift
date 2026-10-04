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
						 size: CGSize(width: 580, height: 350), scheme: scheme, label: "shortcuts")
			try await render(PhysicalInputCaptureBar(session: PhysicalInputCaptureSession()),
						 size: CGSize(width: 650, height: 90), scheme: scheme, label: "press-to-edit")
			try await render(GuidedPresetSheet(), size: CGSize(width: 620, height: 660), scheme: scheme, label: "guided-preset")
			try await render(StickCalibrationSheet(side: .left), size: CGSize(width: 600, height: 720), scheme: scheme, label: "stick-calibration")
			try await render(TriggerMIDIPreviewSheet(), size: CGSize(width: 560, height: 380), scheme: scheme, label: "midi-preview")
			try await render(TriggerMIDIEditor(title: "Left Trigger", configuration: .constant(TriggerMIDIConfiguration())),
							 size: CGSize(width: 650, height: 330), scheme: scheme, label: "trigger-midi")
		}
	}

	func testConnectedCalibrationAndResumedWorkflowRender() async throws {
		let suite = "controllerkeys-render-progress-\(UUID())"
		let defaults = UserDefaults(suiteName: suite)!
		defer { defaults.removePersistentDomain(forName: suite) }
		let progress = GuidedPresetProgressStore(defaults: defaults)
		var profile = GuidedPreset.oneHand.makeProfile(name: "Right hand", targetBundleId: nil, linkApp: false, hand: .right)
		profile.isDefault = true
		profile.controllerPreviewLayout = .dualSense
		profileManager.setActiveProfile(profile)
		controllerService.isConnected = true
		progress.save(.init(preset: .oneHand, hand: .right, targetBundleId: "com.apple.finder"), for: profile.id)
		for scheme in [ColorScheme.light, .dark] {
			try await render(GuidedPresetSheet(resumeProfileId: profile.id, progress: progress), size: CGSize(width: 620, height: 660), scheme: scheme, label: "resume-workflow")
			try await render(StickCalibrationSheet(side: .right), size: CGSize(width: 600, height: 720), scheme: scheme, label: "connected-calibration")
		}
	}

	func testControllerReviewAndSequenceCaptureRenderInBothThemes() async throws {
		let profile = GuidedPreset.anki.makeProfile(name: "Review Anki cards", targetBundleId: nil, linkApp: false)
		profileManager.setActiveProfile(profile); controllerService.isConnected = true
		let lease = mappingEngine.beginInputPreview()
		defer {
			controllerService.buttonReleased(.a); controllerService.buttonReleased(.b)
			mappingEngine.endInputPreview(lease)
		}
		for scheme in [ColorScheme.light, .dark] {
			try await render(GuidedPresetReviewView(profile: profile), size: CGSize(width: 572, height: 390), scheme: scheme, label: "live-preset-review", afterMount: {
				self.controllerService.buttonPressed(.a); self.controllerService.buttonPressed(.b)
			})
			controllerService.buttonReleased(.a); controllerService.buttonReleased(.b)
			await waitForTasks(0.05)
			let capture = PhysicalInputCaptureSession()
			capture.start(mode: .sequence, controller: controllerService, engine: mappingEngine)
			controllerService.buttonPressed(.a); controllerService.buttonReleased(.a)
			controllerService.buttonPressed(.b); controllerService.buttonReleased(.b)
			await waitForTasks(0.05)
			try await render(PhysicalInputCaptureBar(session: capture, mode: .sequence), size: CGSize(width: 780, height: 100), scheme: scheme, label: "capture-sequence")
			capture.cancel()
			try await render(TriggerSettingsView(), size: CGSize(width: 700, height: 500), scheme: scheme, label: "triggers-section")
		}
	}

	private func render<Content: View>(_ content: Content, size: CGSize, scheme: ColorScheme, label: String, afterMount: (@MainActor () -> Void)? = nil) async throws {
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
		if let afterMount { afterMount(); await waitForTasks(0.05) }
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
