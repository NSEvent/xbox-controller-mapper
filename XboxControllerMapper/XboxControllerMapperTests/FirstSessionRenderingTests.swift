import XCTest
import SwiftUI
import AppKit
@testable import ControllerKeys

@MainActor
final class FirstSessionRenderingTests: MappingEngineTestCase {
	func testFreshSidebarAtMinimumWidthInBothThemes() async throws {
		for scheme in [ColorScheme.light, .dark] {
			try await render(
				ProfileSidebar().environmentObject(profileManager).environmentObject(controllerService),
				size: CGSize(width: 200, height: 620), scheme: scheme, label: "starter-sidebar"
			)
		}
	}

	func testAnkiPreviewAndSetupGuideInBothThemes() async throws {
		let root = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
		let profile = try ProfileTransferService.importProfile(
			from: root.appendingPathComponent("community-profiles/Anki Flashcards.json")
		)
		let guide = try String(contentsOf: root.appendingPathComponent("community-profiles/Anki Flashcards.md"))
		for scheme in [ColorScheme.light, .dark] {
			try await render(
				CommunityProfilePreview(profile: profile, profileName: profile.name,
					setupGuide: guide, isLoading: false),
				size: CGSize(width: 480, height: 410), scheme: scheme, label: "anki-guide"
			)
		}
	}

	private func render<Content: View>(
		_ content: Content, size: CGSize, scheme: ColorScheme, label: String
	) async throws {
		// ImageRenderer omits AppKit-backed List/ScrollView content. Host the
		// real view in an unshown window so the preview is actually exercised.
		let host = NSHostingView(rootView: content
			.environmentObject(controllerService)
			.environmentObject(profileManager)
			.frame(width: size.width, height: size.height)
			.background(scheme == .dark ? Color(white: 0.12) : Color(white: 0.96))
			.environment(\.colorScheme, scheme))
		let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
			styleMask: [.borderless], backing: .buffered, defer: false)
		window.isReleasedWhenClosed = false
		window.contentView = host
		host.frame = CGRect(origin: .zero, size: size)
		defer { window.close() }
		await waitForTasks(0.2)
		host.layoutSubtreeIfNeeded()
		let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
		host.cacheDisplay(in: host.bounds, to: bitmap)
		XCTAssertGreaterThanOrEqual(bitmap.pixelsWide, Int(size.width))
		XCTAssertGreaterThanOrEqual(bitmap.pixelsHigh, Int(size.height))
		if let directory = ProcessInfo.processInfo.environment["CONTROLLERKEYS_FIRST_SESSION_SNAPSHOTS"] {
			let url = URL(fileURLWithPath: directory, isDirectory: true)
			try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
			let name = "\(label)-\(scheme == .dark ? "dark" : "light").png"
			try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
				.write(to: url.appendingPathComponent(name))
		}
	}
}
