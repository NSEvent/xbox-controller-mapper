import XCTest
import simd

@testable import ControllerKeys

@MainActor
final class BeamdeskHandGeometryTests: XCTestCase {

	// MARK: - Field authoring

	func testFistFieldIsInsideTheDorsalMassAndOutsideFarAway() {
		for inward: Float in [1, -1] {
			let field = BeamdeskHandGeometry.fistField(inward: inward)
			XCTAssertLessThan(field(SIMD3(0, -0.2, 0.1)), 0, "dorsal mass center must be inside")
			XCTAssertLessThan(field(SIMD3(inward * 0.4, -0.01, 0.14)), 0, "curled finger must be solid")
			XCTAssertGreaterThan(field(SIMD3(0, 2, 0)), 0)
			XCTAssertGreaterThan(field(SIMD3(0, 0, 3)), 0)
		}
	}

	func testCurledFingersStackOnTheInnerEdgeOnly() {
		// POV thumbs-up: the knuckle stack faces screen-center, the outer edge
		// stays a smooth dorsal contour (reference-photo orientation).
		for inward: Float in [1, -1] {
			let field = BeamdeskHandGeometry.fistField(inward: inward)
			XCTAssertLessThan(field(SIMD3(inward * 0.50, 0.22, 0.10)), 0, "index lobe missing inward")
			XCTAssertGreaterThan(field(SIMD3(-inward * 0.50, 0.22, 0.10)), 0, "outer edge must stay clean")
		}
	}

	func testThumbSkirtLeansBackTowardTheFist() {
		let bridge = BeamdeskHandGeometry.thumbBridgeField(inward: 1)
		XCTAssertLessThan(bridge(SIMD3(-0.25, -0.26, -0.16)), 0, "skirt must lean back into the fist")
		XCTAssertGreaterThan(bridge(SIMD3(0.25, -0.26, -0.16)), 0, "skirt must not flare inward")
	}

	func testFieldsMirrorExactlyBetweenHands() {
		let leftFist = BeamdeskHandGeometry.fistField(inward: 1)
		let rightFist = BeamdeskHandGeometry.fistField(inward: -1)
		let leftBridge = BeamdeskHandGeometry.thumbBridgeField(inward: 1)
		let rightBridge = BeamdeskHandGeometry.thumbBridgeField(inward: -1)
		for probe in probePoints() {
			let mirrored = SIMD3(-probe.x, probe.y, probe.z)
			XCTAssertEqual(leftFist(probe), rightFist(mirrored), accuracy: 1e-5)
			XCTAssertEqual(leftBridge(probe), rightBridge(mirrored), accuracy: 1e-5)
		}
	}

	func testSmoothMinBlendsWithoutOvershoot() {
		XCTAssertEqual(BeamdeskHandGeometry.smoothMin(0.5, 3.0, 0.2), 0.5, accuracy: 1e-6)
		XCTAssertLessThan(BeamdeskHandGeometry.smoothMin(0.5, 0.5, 0.2), 0.5)
		XCTAssertGreaterThanOrEqual(
			BeamdeskHandGeometry.smoothMin(0.5, 0.5, 0.2), 0.5 - 0.2)
	}

	// MARK: - Surface-nets mesher

	func testSphereMeshIsClosedConsistentlyWoundAndOutwardFacing() {
		let mesh = BeamdeskHandGeometry.surfaceNetsMesh(
			field: { BeamdeskHandGeometry.sphere($0, SIMD3(0, 0, 0), 0.5) },
			lower: SIMD3(repeating: -0.8),
			upper: SIMD3(repeating: 0.8),
			cellSize: 0.1)

		XCTAssertFalse(mesh.vertices.isEmpty)
		XCTAssertEqual(mesh.indices.count % 3, 0)
		XCTAssertEqual(mesh.vertices.count, mesh.normals.count)

		// Closed manifold with consistent winding: every directed edge occurs once.
		var directedEdges = Set<[Int32]>()
		for t in stride(from: 0, to: mesh.indices.count, by: 3) {
			let (a, b, c) = (mesh.indices[t], mesh.indices[t + 1], mesh.indices[t + 2])
			for edge in [[a, b], [b, c], [c, a]] {
				XCTAssertTrue(directedEdges.insert(edge).inserted, "duplicate directed edge \(edge)")
				XCTAssertNotEqual(edge[0], edge[1], "degenerate edge")
			}
		}
		for edge in directedEdges {
			XCTAssertTrue(directedEdges.contains([edge[1], edge[0]]), "boundary edge \(edge)")
		}

		for (vertex, normal) in zip(mesh.vertices, mesh.normals) {
			XCTAssertEqual(simd_length(normal), 1, accuracy: 1e-3)
			XCTAssertEqual(simd_length(vertex), 0.5, accuracy: 0.05, "vertex should sit on the sphere")
			XCTAssertGreaterThan(
				simd_dot(normal, simd_normalize(vertex)), 0.9, "normal should point outward")
		}
	}

	func testMeshGenerationIsDeterministic() {
		let first = BeamdeskHandGeometry.thumbSegmentMesh(
			baseRadius: 0.15, tipRadius: 0.12, length: 0.42)
		let second = BeamdeskHandGeometry.thumbSegmentMesh(
			baseRadius: 0.15, tipRadius: 0.12, length: 0.42)
		XCTAssertEqual(first, second)
	}

	// MARK: - Authored meshes

	func testFistMeshCoversFingersThenarKnucklesAndWrist() {
		for inward: Float in [1, -1] {
			let mesh = BeamdeskHandGeometry.fistMesh(inward: inward)
			XCTAssertGreaterThan(mesh.vertices.count, 500, "shell should be densely sculpted")
			XCTAssertEqual(mesh.indices.count % 3, 0)

			let xs = mesh.vertices.map { $0.x * inward }
			let ys = mesh.vertices.map(\.y)
			XCTAssertGreaterThan(xs.max() ?? 0, 0.55, "curled fingers missing from silhouette")
			XCTAssertLessThan(xs.min() ?? 0, -0.35, "outer dorsal/hypothenar side missing")
			XCTAssertGreaterThan(ys.max() ?? 0, 0.3, "index-over-the-top edge missing")
			XCTAssertLessThan(ys.min() ?? 0, -1.5, "forearm missing")

			for (vertex, normal) in zip(mesh.vertices, mesh.normals) {
				XCTAssertEqual(simd_length(normal), 1, accuracy: 1e-3)
				XCTAssertTrue(vertex.x.isFinite && vertex.y.isFinite && vertex.z.isFinite)
			}

			// The full fist must stay a closed, consistently wound shell even
			// where creases cross (the weld pass guards against pinches).
			var directed = Set<[Int32]>()
			for t in stride(from: 0, to: mesh.indices.count, by: 3) {
				let (a, b, c) = (mesh.indices[t], mesh.indices[t + 1], mesh.indices[t + 2])
				for edge in [[a, b], [b, c], [c, a]] {
					XCTAssertTrue(directed.insert(edge).inserted, "pinched shell at edge \(edge)")
				}
			}
			for edge in directed {
				XCTAssertTrue(directed.contains([edge[1], edge[0]]), "open shell at edge \(edge)")
			}
		}
	}

	func testThumbSegmentMeshBuriesItsPivotAndClosesAtTheTip() {
		let length: Float = 0.44
		let mesh = BeamdeskHandGeometry.thumbSegmentMesh(
			baseRadius: 0.152, tipRadius: 0.116, length: length)
		XCTAssertFalse(mesh.vertices.isEmpty)

		let ys = mesh.vertices.map(\.y)
		XCTAssertLessThan(ys.min() ?? 0, -0.1, "segment must extend below its pivot")
		XCTAssertGreaterThan(ys.max() ?? 0, length, "rounded tip must overrun the shaft end")
		for vertex in mesh.vertices {
			let radial = sqrt(vertex.x * vertex.x + vertex.z * vertex.z)
			XCTAssertLessThan(radial, 0.152 + 0.06, "segment silhouette must stay slender")
		}
	}

	private func probePoints() -> [SIMD3<Float>] {
		var points: [SIMD3<Float>] = []
		for x in stride(from: Float(-0.9), through: 0.9, by: 0.3) {
			for y in stride(from: Float(-1.9), through: 0.5, by: 0.4) {
				for z in stride(from: Float(-0.5), through: 0.7, by: 0.3) {
					points.append(SIMD3(x, y, z))
				}
			}
		}
		return points
	}
}
