import AppKit
import SwiftUI
import XCTest
@testable import ControllerKeys

@MainActor
final class ControllerVisualRenderingTests: XCTestCase {
	private static var retainedControllerServices: [ControllerService] = []

	func testAllControllerLayoutsRenderVisibleCanvas() throws {
		for layout in ControllerPreviewLayout.concreteLayouts {
			let image = try renderControllerCanvas(layout)
			let stats = try sampledStats(from: image)

			XCTAssertGreaterThanOrEqual(stats.width, 1100, "\(layout.rawValue) rendered too narrow")
			XCTAssertGreaterThanOrEqual(stats.height, 700, "\(layout.rawValue) rendered too short")
			XCTAssertGreaterThan(stats.distinctColorBuckets, 20, "\(layout.rawValue) rendered mostly blank")
			XCTAssertGreaterThan(stats.foregroundSamples, 250, "\(layout.rawValue) has too little foreground content")
			XCTAssertGreaterThan(stats.foregroundBounds.width, 300, "\(layout.rawValue) foreground is too narrow")
			XCTAssertGreaterThan(stats.foregroundBounds.height, 180, "\(layout.rawValue) foreground is too short")

			try writePNGIfRequested(image, name: "canvas-\(layout.rawValue)")
		}
	}

	func testAllPairingMinimapsRenderVisibleForeground() throws {
		for layout in ControllerPreviewLayout.concreteLayouts {
			let image = try renderPairingMinimap(layout)
			let stats = try sampledStats(from: image)
			let expectations = minimapExpectations(for: layout)

			XCTAssertGreaterThan(stats.distinctColorBuckets, 10, "\(layout.rawValue) minimap rendered mostly blank")
			XCTAssertGreaterThan(
				stats.foregroundSamples,
				expectations.minForegroundSamples,
				"\(layout.rawValue) minimap has too little foreground content"
			)
			XCTAssertGreaterThan(
				stats.foregroundBounds.width,
				expectations.minForegroundWidth,
				"\(layout.rawValue) minimap foreground is too narrow"
			)
			XCTAssertGreaterThan(
				stats.foregroundBounds.height,
				expectations.minForegroundHeight,
				"\(layout.rawValue) minimap foreground is too short"
			)

			try writePNGIfRequested(image, name: "minimap-\(layout.rawValue)")
		}
	}

	private func renderControllerCanvas(_ layout: ControllerPreviewLayout) throws -> NSImage {
		let controllerService = ControllerService(enableHardwareMonitoring: false)
		Self.retainedControllerServices.append(controllerService)
		let profileManager = ProfileManager(configDirectoryOverride: temporaryConfigDirectory(for: layout))
		let content = ControllerVisualView(
			selectedButton: .constant(nil),
			selectedLayerId: nil,
			previewLayout: layout,
			onButtonTap: { _ in }
		)
		.environmentObject(controllerService)
		.environmentObject(profileManager)

		return try render(
			content
				.frame(width: 1120, height: 720)
				.padding(24)
				.background(Color(NSColor.windowBackgroundColor)),
			size: CGSize(width: 1168, height: 768),
			label: layout.rawValue
		)
	}

	private func renderPairingMinimap(_ layout: ControllerPreviewLayout) throws -> NSImage {
		let controllerService = ControllerService(enableHardwareMonitoring: false)
		let pressedButtons = layout.pairingGuide?.pairingButtons ?? []
		controllerService.activeButtons = pressedButtons
		Self.retainedControllerServices.append(controllerService)

		let content = StaticControllerMinimapPreview(
			controllerService: controllerService,
			descriptor: ControllerVisualDescriptor.resolved(previewLayout: layout, using: controllerService),
			pressedButtons: pressedButtons,
			targetWidth: 280,
			remoteTargetHeight: 320
		)

		return try render(
			content
				.frame(width: 420, height: 420)
				.background(Color(NSColor.windowBackgroundColor)),
			size: CGSize(width: 420, height: 420),
			label: "\(layout.rawValue) minimap"
		)
	}

	private func render<Content: View>(_ content: Content, size: CGSize, label: String) throws -> NSImage {
		let renderer = ImageRenderer(content: content)
		renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
		renderer.scale = 1

		return try XCTUnwrap(renderer.nsImage, "\(label) did not produce an NSImage")
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
		let background = try XCTUnwrap(bitmap.colorAt(x: 0, y: 0), "Rendered image has no background sample")
		var foregroundSamples = 0
		var colorBuckets = Set<Int>()
		var minForegroundX = Int.max
		var minForegroundY = Int.max
		var maxForegroundX = Int.min
		var maxForegroundY = Int.min
		let xStride = max(1, bitmap.pixelsWide / 96)
		let yStride = max(1, bitmap.pixelsHigh / 72)

		for y in stride(from: 0, to: bitmap.pixelsHigh, by: yStride) {
			for x in stride(from: 0, to: bitmap.pixelsWide, by: xStride) {
				guard let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.05 else { continue }
				colorBuckets.insert(Self.bucket(color))
				guard Self.colorDistance(color, background) > 0.03 else { continue }

				foregroundSamples += 1
				minForegroundX = min(minForegroundX, x)
				minForegroundY = min(minForegroundY, y)
				maxForegroundX = max(maxForegroundX, x)
				maxForegroundY = max(maxForegroundY, y)
			}
		}

		return RenderStats(
			width: bitmap.pixelsWide,
			height: bitmap.pixelsHigh,
			foregroundSamples: foregroundSamples,
			foregroundBounds: foregroundSamples > 0
				? CGRect(
					x: minForegroundX,
					y: minForegroundY,
					width: maxForegroundX - minForegroundX + 1,
					height: maxForegroundY - minForegroundY + 1
				)
				: .zero,
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

	private static func colorDistance(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
		let left = lhs.usingColorSpace(.deviceRGB) ?? lhs
		let right = rhs.usingColorSpace(.deviceRGB) ?? rhs
		return max(
			abs(left.redComponent - right.redComponent),
			abs(left.greenComponent - right.greenComponent),
			abs(left.blueComponent - right.blueComponent),
			abs(left.alphaComponent - right.alphaComponent)
		)
	}

	private func minimapExpectations(for layout: ControllerPreviewLayout) -> RenderExpectations {
		if layout == .appleTVRemote {
			return RenderExpectations(
				minForegroundSamples: 80,
				minForegroundWidth: 45,
				minForegroundHeight: 220
			)
		}

		return RenderExpectations(
			minForegroundSamples: 120,
			minForegroundWidth: 150,
			minForegroundHeight: 70
		)
	}

	private func writePNGIfRequested(_ image: NSImage, name: String) throws {
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
		try pngData.write(to: directory.appendingPathComponent("\(name).png"))
	}
}

private struct RenderStats {
	let width: Int
	let height: Int
	let foregroundSamples: Int
	let foregroundBounds: CGRect
	let distinctColorBuckets: Int
}

private struct RenderExpectations {
	let minForegroundSamples: Int
	let minForegroundWidth: CGFloat
	let minForegroundHeight: CGFloat
}

private struct StaticControllerMinimapPreview: View {
	let controllerService: ControllerService
	let descriptor: ControllerVisualDescriptor
	let pressedButtons: Set<ControllerButton>
	let targetWidth: CGFloat
	let remoteTargetHeight: CGFloat

	var body: some View {
		Group {
			if descriptor.isAppleTVRemote {
				appleTVRemoteMinimap
			} else {
				gamepadMinimap
			}
		}
		.allowsHitTesting(false)
		.accessibilityHidden(true)
	}

	private var gamepadMinimap: some View {
		let style = descriptor.minimapStyle ?? .xbox
		let size = style.previewSize
		let scale = targetWidth / size.width

		return ZStack {
			ControllerBodyView(style: style)
				.frame(width: size.width, height: size.height)

			ControllerAnalogOverlay(
				controllerService: controllerService,
				isPlayStation: descriptor.isPlayStation,
				isNintendo: descriptor.isNintendo,
				isXboxElite: descriptor.isXboxElite,
				isSteamController: descriptor.isSteamController,
				isDualShock: descriptor.isDualShock,
				isDualSenseEdge: descriptor.isDualSenseEdge,
				eightBitDoModel: descriptor.eightBitDoModel,
				onButtonTap: { _ in },
				overrideColorForButton: { pressedButtons.contains($0) ? Color.accentColor : nil }
			)
			.frame(width: size.width, height: size.height)
		}
		.frame(width: size.width, height: size.height)
		.scaleEffect(scale)
		.frame(width: targetWidth, height: (size.height * scale).rounded())
	}

	private var appleTVRemoteMinimap: some View {
		let size = AppleTVRemoteMinimapView.previewSize
		let scale = remoteTargetHeight / size.height

		return AppleTVRemoteMinimapView(controllerService: controllerService)
			.frame(width: size.width, height: size.height)
			.scaleEffect(scale)
			.frame(width: (size.width * scale).rounded(), height: remoteTargetHeight)
	}
}
