import AppKit
import SwiftUI
import XCTest
@testable import ControllerKeys

@MainActor
final class CommunityProfileSharingRenderingTests: XCTestCase {
	func testPasteAndAttachmentHandoffsRenderAtSheetSize() throws {
		for large in [false, true] {
			var profile = Profile(name: "Photo Mechanic")
			profile.buttonMappings[.a] = KeyMapping(keyCode: 49, hint: large ? String(repeating: "a", count: 65_000) : "Full screen")
			let submission = try CommunityProfileSubmission.prepare(profile: profile,
				details: .init(name: profile.name, summary: "Cull wedding photos", controller: "8BitDo Pro 2"))
			XCTAssertEqual(submission.pasteBody == nil, large)
			let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
			defer { try? FileManager.default.removeItem(at: directory) }
			let packet = try CommunityProfileSubmissionFiles.write(submission, to: directory)
			let view = CommunityProfileSubmissionReadyView(packet: packet, submission: submission,
				browserOpened: true, copied: !large, copySubmission: {}, openDraft: {})
				.padding(24).frame(width: 640, height: 690, alignment: .topLeading)
				.background(Color(NSColor.windowBackgroundColor))
			let renderer = ImageRenderer(content: view)
			renderer.scale = 2
			let image = try XCTUnwrap(renderer.nsImage)
			XCTAssertEqual(image.size, NSSize(width: 640, height: 690))
			if let path = ProcessInfo.processInfo.environment["CONTROLLERKEYS_RENDER_SNAPSHOT_DIR"] {
				let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
				try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
					.write(to: URL(fileURLWithPath: path).appendingPathComponent(large ? "sharing-attachment.png" : "sharing-paste.png"))
				if !large {
					try XCTUnwrap(submission.pasteBody).write(to: URL(fileURLWithPath: path).appendingPathComponent("submission-fixture.txt"), atomically: true, encoding: .utf8)
					try submission.issueURL.absoluteString.write(to: URL(fileURLWithPath: path).appendingPathComponent("draft-fixture-url.txt"), atomically: true, encoding: .utf8)
				}
			}
		}
	}

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
