import XCTest
import SwiftUI
@testable import ControllerKeys

@MainActor
final class ControllerConnectorAttachmentTests: XCTestCase {
	func testAllRingDirectionsMeetTheirCardinalRimAtEveryCanvasScale() throws {
		let layout = XiaomiRemoteMinimapLayout.self
		let ringCenter = CGPoint(x: layout.ringCenter.x * layout.bodyWidth, y: layout.ringCenter.y * layout.bodyHeight)
		let directions: [(ControllerButton, CGPoint)] = [
			(.dpadUp, CGPoint(x: 0, y: -layout.ringRadius)),
			(.dpadDown, CGPoint(x: 0, y: layout.ringRadius)),
			(.dpadLeft, CGPoint(x: -layout.ringRadius, y: 0)),
			(.dpadRight, CGPoint(x: layout.ringRadius, y: 0)),
		]
		for scale in [CGFloat(0.55), 0.88, 1, 1.7] {
			for (button, delta) in directions {
				let local = layout.arrowGeometry(for: button).bounds.offsetBy(dx: ringCenter.x, dy: ringCenter.y)
				let rect = CGRect(x: 340 + local.minX * scale, y: 70 + local.minY * scale,
					width: local.width * scale, height: local.height * scale)
				let point = try XCTUnwrap(layout.arrowAttachment(for: button).point(in: rect, towards: .zero))
				XCTAssertEqual(point.x, 340 + (ringCenter.x + delta.x) * scale, accuracy: 0.0001, "\(button)")
				XCTAssertEqual(point.y, 70 + (ringCenter.y + delta.y) * scale, accuracy: 0.0001, "\(button)")
			}
		}
	}

	func testRoundKeysMeetTheVisibleHorizontalRimEvenWithFarOffsetLabels() throws {
		let rect = CGRect(x: 400, y: 200, width: 40, height: 40)
		for y in [CGFloat(-500), 220, 1000] {
			let left = try XCTUnwrap(ConnectorAttachment.circle.point(in: rect, towards: CGPoint(x: 100, y: y)))
			let right = try XCTUnwrap(ConnectorAttachment.circle.point(in: rect, towards: CGPoint(x: 800, y: y)))
			XCTAssertEqual(left, CGPoint(x: 400, y: 220))
			XCTAssertEqual(right, CGPoint(x: 440, y: 220))
			XCTAssertEqual(hypot(left.x - rect.midX, left.y - rect.midY), 20)
		}
	}

	func testLabelPortsStayCenteredOnTheFacingSide() throws {
		let rect = CGRect(x: 100, y: 900, width: 250, height: 70)
		XCTAssertEqual(ConnectorAttachment.horizontalEdge.point(in: rect, towards: CGPoint(x: 500, y: 100)),
			CGPoint(x: 350, y: 935))
		XCTAssertEqual(ConnectorAttachment.horizontalEdge.point(in: rect, towards: CGPoint(x: 0, y: 100)),
			CGPoint(x: 100, y: 935))
		XCTAssertNil(ConnectorAttachment.bounds.point(in: rect, towards: .zero), "Existing layouts retain legacy edge projection")
	}
}
