import AppKit
import SwiftUI
import XCTest
@testable import ControllerKeys

@MainActor
final class ControllerVisualRenderingTests: XCTestCase {
	func testRepresentativeControllerLayoutsRenderNonBlank() throws {
		let layouts: [ControllerPreviewLayout] = [
			.xbox,
			.dualSense,
			.dualSenseEdge,
			.dualShock,
			.steam,
			.appleTVRemote,
			.eightBitDoMicro
		]

		for layout in layouts {
			let image = try render(layout)
			let stats = try sampledStats(from: image)

			XCTAssertGreaterThanOrEqual(stats.width, 1100, "\(layout.rawValue) rendered too narrow")
			XCTAssertGreaterThanOrEqual(stats.height, 700, "\(layout.rawValue) rendered too short")
			XCTAssertGreaterThan(stats.nonTransparentSamples, 500, "\(layout.rawValue) rendered mostly transparent")
			XCTAssertGreaterThan(stats.distinctColorBuckets, 20, "\(layout.rawValue) rendered mostly blank")

			try writePNGIfRequested(image, layout: layout)
		}
	}

	private func render(_ layout: ControllerPreviewLayout) throws -> NSImage {
		let controllerService = ControllerService(enableHardwareMonitoring: false)
		let profileManager = ProfileManager(configDirectoryOverride: temporaryConfigDirectory(for: layout))
		let content = ControllerVisualView(
			selectedButton: .constant(nil),
			selectedLayerId: nil,
			previewLayout: layout,
			onButtonTap: { _ in }
		)
		.environmentObject(controllerService)
		.environmentObject(profileManager)
		.frame(width: 1120, height: 720)
		.padding(24)
		.background(Color(NSColor.windowBackgroundColor))

		let renderer = ImageRenderer(content: content)
		renderer.proposedSize = ProposedViewSize(width: 1168, height: 768)
		renderer.scale = 1

		return try XCTUnwrap(renderer.nsImage, "\(layout.rawValue) did not produce an NSImage")
	}

	private func temporaryConfigDirectory(for layout: ControllerPreviewLayout) -> URL {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("ControllerVisualRenderingTests-\(layout.rawValue)-\(UUID().uuidString)", isDirectory: true)
		addTeardownBlock {
			try? FileManager.default.removeItem(at: directory)
		}
		return directory
	}

	private func sampledStats(from image: NSImage) throws -> RenderStats {
		let tiffData = try XCTUnwrap(image.tiffRepresentation, "Rendered image has no TIFF representation")
		let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiffData), "Rendered image could not be decoded")
		var nonTransparentSamples = 0
		var colorBuckets = Set<Int>()
		let xStride = max(1, bitmap.pixelsWide / 80)
		let yStride = max(1, bitmap.pixelsHigh / 60)

		for y in stride(from: 0, to: bitmap.pixelsHigh, by: yStride) {
			for x in stride(from: 0, to: bitmap.pixelsWide, by: xStride) {
				guard let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.05 else { continue }
				nonTransparentSamples += 1
				colorBuckets.insert(Self.bucket(color))
			}
		}

		return RenderStats(
			width: bitmap.pixelsWide,
			height: bitmap.pixelsHigh,
			nonTransparentSamples: nonTransparentSamples,
			distinctColorBuckets: colorBuckets.count
		)
	}

	private static func bucket(_ color: NSColor) -> Int {
		let rgb = color.usingColorSpace(.deviceRGB) ?? color
		let r = Int((rgb.redComponent * 31).rounded())
		let g = Int((rgb.greenComponent * 31).rounded())
		let b = Int((rgb.blueComponent * 31).rounded())
		let a = Int((rgb.alphaComponent * 31).rounded())
		return (r << 15) | (g << 10) | (b << 5) | a
	}

	private func writePNGIfRequested(_ image: NSImage, layout: ControllerPreviewLayout) throws {
		guard let directoryPath = ProcessInfo.processInfo.environment["CONTROLLERKEYS_RENDER_SNAPSHOT_DIR"],
			  !directoryPath.isEmpty else { return }

		let directory = URL(fileURLWithPath: directoryPath, isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

		let tiffData = try XCTUnwrap(image.tiffRepresentation, "Rendered image has no TIFF representation")
		let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiffData), "Rendered image could not be decoded")
		let pngData = try XCTUnwrap(
			bitmap.representation(using: .png, properties: [:]),
			"Rendered image could not be encoded as PNG"
		)
		try pngData.write(to: directory.appendingPathComponent("\(layout.rawValue).png"))
	}
}

private struct RenderStats {
	let width: Int
	let height: Int
	let nonTransparentSamples: Int
	let distinctColorBuckets: Int
}
