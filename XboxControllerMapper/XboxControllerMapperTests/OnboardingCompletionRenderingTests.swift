import AppKit
import SwiftUI
import XCTest
@testable import ControllerKeys

@MainActor
final class OnboardingCompletionRenderingTests: XCTestCase {
	func testPurposeAndPhotoRecommendationsFitWizardWidth() throws {
		let welcome = VStack(alignment: .leading, spacing: 18) {
			Text("Welcome to ControllerKeys").font(.title2.bold())
			OnboardingPurposeView(selection: .photoVideo, onSelect: { _ in },
								  note: .constant("Culling wedding photos in Lightroom"), contact: .constant(""))
			Text("Next, we'll connect your controller and set up macOS permissions.").font(.caption)
			HStack { Button("Skip") {}; Spacer(); Button("Get Started") {} }
		}.padding(24).frame(width: 480)
		let completion = VStack(alignment: .leading, spacing: 18) {
			Text("Ready to try your mappings").font(.title2.bold())
			OnboardingCompletionView(readiness: .ready, permissions: .init(accessibility: .granted, inputMonitoring: .notDetermined, bluetooth: .notDetermined))
			OnboardingSetupSuggestionsView(purpose: .photoVideo, onOpen: { _ in })
			Button("Start Using ControllerKeys") {}
		}.padding(24).frame(width: 480)
		// Welcome now carries the optional "Tell me more" note (expanded state, email row shown);
		// the wizard window is 760pt tall and its content scrolls, so allow more height here.
		try checkAndSave(welcome, name: "onboarding-purpose-welcome", maxHeight: 760)
		try checkAndSave(completion, name: "onboarding-purpose-photos")
	}

	private func checkAndSave<V: View>(_ content: V, name: String, maxHeight: CGFloat = 620) throws {
		let renderer = ImageRenderer(content: content.background(Color(NSColor.windowBackgroundColor)))
		renderer.scale = 2
		let image = try XCTUnwrap(renderer.nsImage)
		XCTAssertEqual(image.size.width, 480)
		XCTAssertLessThan(image.size.height, maxHeight, "Purpose and suggestions should fit without clipped actions")
		if let directory = ProcessInfo.processInfo.environment["CONTROLLERKEYS_RENDER_SNAPSHOT_DIR"] {
			let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
			try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
				.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
		}
	}

	func testCompletionStatesRenderAtWizardWidth() throws {
		for (name, readiness) in [("accessibility", OnboardingReadiness.accessibilityMissing),
								  ("controller", .controllerMissing), ("ready", .ready)] {
			let state = OnboardingStepState(accessibility: readiness == .accessibilityMissing ? .denied : .granted,
											inputMonitoring: .notDetermined, bluetooth: .notDetermined)
			let content = VStack(spacing: 18) {
				Text(readiness.title).font(.title2.bold()).multilineTextAlignment(.center)
				Divider()
				OnboardingCompletionView(readiness: readiness, permissions: state)
				HStack {
					if readiness != .ready { Button("Set Up Later") {} }
					Spacer()
					Button(readiness.buttonTitle) {}.buttonStyle(.borderedProminent)
				}
			}
			.padding(24)
			.frame(width: 480)
			.background(Color(NSColor.windowBackgroundColor))
			let renderer = ImageRenderer(content: content)
			renderer.scale = 2
			let image = try XCTUnwrap(renderer.nsImage)
			XCTAssertEqual(image.size.width, 480)
			XCTAssertLessThan(image.size.height, 540, "Completion summary must fit the wizard")
			if let directory = ProcessInfo.processInfo.environment["CONTROLLERKEYS_RENDER_SNAPSHOT_DIR"] {
				let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
				let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
				try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("onboarding-\(name).png"))
			}
		}
	}
}
