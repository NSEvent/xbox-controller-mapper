import AppKit
import SwiftUI
import XCTest
@testable import ControllerKeys

@MainActor
final class OnboardingCompletionRenderingTests: XCTestCase {
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
