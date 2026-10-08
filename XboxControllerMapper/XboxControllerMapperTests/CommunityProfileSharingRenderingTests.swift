import AppKit
import SwiftUI
import XCTest
@testable import ControllerKeys

@MainActor
final class CommunityProfileSharingRenderingTests: XCTestCase {
	func testShareFormRendersAtSheetSize() throws {
		var profile = Profile(name: "Anki on DualSense")
		profile.buttonMappings[.a] = KeyMapping(keyCode: 49, hint: "Show answer")
		let renderer = ImageRenderer(content: ShareCommunityProfileSheet(profile: profile).background(Color(NSColor.windowBackgroundColor)))
		renderer.scale = 2
		let image = try XCTUnwrap(renderer.nsImage)
		XCTAssertEqual(image.size, NSSize(width: 640, height: 690))
		if let path = ProcessInfo.processInfo.environment["CONTROLLERKEYS_RENDER_SNAPSHOT_DIR"] {
			let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
			try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
				.write(to: URL(fileURLWithPath: path).appendingPathComponent("community-profile-sharing.png"))
		}
	}
}
