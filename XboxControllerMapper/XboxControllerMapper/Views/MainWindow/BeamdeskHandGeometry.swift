import Foundation
import SceneKit
import simd

/// Triangle mesh produced by polygonizing a signed-distance field.
struct BeamdeskSurfaceMesh: Equatable {
  let vertices: [SIMD3<Float>]
  let normals: [SIMD3<Float>]
  let indices: [Int32]
}

/// Code-native sculpting for the Beamdesk POV fists.
///
/// Each hand is authored as one signed-distance field: anatomical masses
/// (metacarpal slab, dorsal dome, curled digits, thumb-web mound,
/// hypothenar heel, wrist and forearm) are blended with smooth minimums so
/// the surface polygonizes into a single cohesive shell instead of fused
/// primitives. Surface nets keep the topology coherent and the field
/// gradient supplies smooth normals. Everything is deterministic pure math
/// so it is unit testable without a renderer.
enum BeamdeskHandGeometry {

  // MARK: - Signed-distance primitives

  static func sphere(_ p: SIMD3<Float>, _ center: SIMD3<Float>, _ radius: Float) -> Float {
    simd_length(p - center) - radius
  }

  /// Approximate ellipsoid distance; exact enough for blending and meshing.
  static func ellipsoid(_ p: SIMD3<Float>, _ center: SIMD3<Float>, _ radii: SIMD3<Float>) -> Float {
    let q = (p - center) / radii
    return (simd_length(q) - 1) * radii.min()
  }

  /// Capsule between two points whose radius tapers from `r0` at `a` to `r1` at `b`.
  static func taperedCapsule(
    _ p: SIMD3<Float>, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ r0: Float, _ r1: Float
  ) -> Float {
    let ab = b - a
    let t = min(max(simd_dot(p - a, ab) / simd_dot(ab, ab), 0), 1)
    return simd_length(p - (a + ab * t)) - (r0 + (r1 - r0) * t)
  }

  static func roundedBox(
    _ p: SIMD3<Float>, _ center: SIMD3<Float>, _ halfExtents: SIMD3<Float>, _ corner: Float
  ) -> Float {
    let q = simd_abs(p - center) - halfExtents + SIMD3<Float>(repeating: corner)
    let outside = simd_length(simd_max(q, SIMD3<Float>(repeating: 0)))
    return outside + min(max(q.x, max(q.y, q.z)), 0) - corner
  }

  /// Polynomial smooth minimum; `k` is the blend radius joining two masses.
  static func smoothMin(_ a: Float, _ b: Float, _ k: Float) -> Float {
    let h = max(k - abs(a - b), 0) / k
    return min(a, b) - h * h * k * 0.25
  }

  /// Smooth maximum; `smoothMax(d, -cutter, k)` carves `cutter` out of `d`
  /// with a filleted edge instead of a hard boolean seam.
  static func smoothMax(_ a: Float, _ b: Float, _ k: Float) -> Float {
    -smoothMin(-a, -b, k)
  }

  // MARK: - Authored fields

  /// The unified fist shell, sans thumb, posed as a first-person thumbs-up:
  /// dorsal dome toward the viewer, curled finger lobes stacked down the
  /// inner edge, forearm running off the bottom of frame. `inward` is +1
  /// when screen-center is +x (left hand) and -1 for the right hand.
  static func fistField(inward: Float) -> (SIMD3<Float>) -> Float {
    let s = inward
    return { p in
      // Metacarpal slab and the broad dorsal dome the viewer mostly sees.
      var d = roundedBox(p, SIMD3(-s * 0.02, -0.18, 0.02), SIMD3(0.40, 0.44, 0.20), 0.18)
      d = smoothMin(d, ellipsoid(p, SIMD3(-s * 0.06, -0.16, 0.18), SIMD3(0.44, 0.50, 0.24)), 0.18)
      // Curled index seen side-on forms the top edge; the thumb rises behind it.
      d = smoothMin(
        d, taperedCapsule(p, SIMD3(-s * 0.10, 0.30, 0.06), SIMD3(s * 0.30, 0.27, 0.10), 0.17, 0.145),
        0.12)
      // Thumb-web mound under the animated column keeps its base grounded.
      d = smoothMin(d, ellipsoid(p, SIMD3(s * 0.26, 0.04, 0.22), SIMD3(0.24, 0.24, 0.20)), 0.14)
      // Hypothenar heel rounds out the outer-bottom contour; a smaller pad
      // fills the inner-bottom notch where the pinky lobe meets the wrist.
      d = smoothMin(d, ellipsoid(p, SIMD3(-s * 0.30, -0.46, 0.06), SIMD3(0.22, 0.34, 0.22)), 0.14)
      d = smoothMin(d, ellipsoid(p, SIMD3(s * 0.16, -0.60, 0.00), SIMD3(0.28, 0.24, 0.18)), 0.14)
      // Wrist and forearm taper away to the outer bottom corner, off-frame.
      d = smoothMin(
        d, taperedCapsule(p, SIMD3(-s * 0.02, -0.60, -0.04), SIMD3(-s * 0.16, -1.05, -0.10), 0.30, 0.26),
        0.16)
      d = smoothMin(
        d, taperedCapsule(p, SIMD3(-s * 0.16, -1.05, -0.10), SIMD3(-s * 0.44, -2.35, -0.24), 0.26, 0.32),
        0.10)

      // Curled digits: each is a horizontal hook seen edge-on — the proximal
      // phalanx emerges from the shell toward screen-center, crowns at a PIP
      // knuckle on the leading edge, and the middle phalanx folds away from
      // camera around it, shading darker as it recedes. Tight blends at the
      // bend and between neighbors keep crease lines readable; a softer
      // blend melts the stack into the fist as one shell. Lower digits curl
      // shorter and sit deeper, like a relaxed fist.
      let rows: [Float] = [0.24, -0.01, -0.26, -0.49]
      var fingers = Float.greatestFiniteMagnitude
      for (index, y) in rows.enumerated() {
        let taper = 1 - Float(index) * 0.05
        let reach = 0.025 * Float(index)
        let sink = 0.01 * Float(index)
        let pipX = s * (0.475 - reach)
        var finger = taperedCapsule(
          p, SIMD3(s * 0.25, y, 0.10 - sink), SIMD3(pipX - s * 0.03, y - 0.015, 0.115 - sink),
          0.145 * taper, 0.126 * taper)
        finger = smoothMin(
          finger,
          ellipsoid(
            p, SIMD3(pipX, y - 0.025, 0.075 - sink),
            SIMD3(0.128 * taper, 0.108 * taper, 0.105 * taper)),
          0.045)
        finger = smoothMin(
          finger,
          taperedCapsule(
            p, SIMD3(pipX - s * 0.005, y - 0.03, 0.05 - sink),
            SIMD3(pipX - s * 0.045, y - 0.045, -0.09),
            0.120 * taper, 0.100 * taper),
          0.045)
        fingers = index == 0 ? finger : smoothMin(fingers, finger, 0.028)
      }
      // Crease where the digits press against the dorsal mass: a carved
      // channel running down the emergence line separates the knuckle stack
      // from the back of the hand instead of melting into it. Kept wider
      // than the polygonizer cell so the cut never pinches the shell.
      let groove = taperedCapsule(
        p, SIMD3(s * 0.335, 0.34, 0.27), SIMD3(s * 0.315, -0.58, 0.23), 0.065, 0.065)
      return smoothMax(smoothMin(d, fingers, 0.10), -groove, 0.065)
    }
  }

  /// Thenar skirt that rides the animated thumb root: a low sleeve leaning
  /// back into the fist so the CMC pivot stays buried while the root slides.
  static func thumbBridgeField(inward: Float) -> (SIMD3<Float>) -> Float {
    let s = inward
    return { p in
      var d = taperedCapsule(
        p, SIMD3(0, 0.02, 0.02), SIMD3(-s * 0.10, -0.26, -0.14), 0.13, 0.18)
      d = smoothMin(d, ellipsoid(p, SIMD3(-s * 0.05, -0.22, -0.10), SIMD3(0.19, 0.17, 0.16)), 0.10)
      return d
    }
  }

  /// One articulated thumb segment: a tapered capsule whose lower end cap is
  /// the buried pivot bulb. Segments start below their pivot and overrun the
  /// next one so rotation never opens a seam in the silhouette.
  static func thumbSegmentField(
    baseRadius: Float, tipRadius: Float, length: Float
  ) -> (SIMD3<Float>) -> Float {
    { p in
      taperedCapsule(p, SIMD3(0, -0.12, 0), SIMD3(0, length, 0), baseRadius, tipRadius)
    }
  }

  // MARK: - Surface-nets polygonizer

  /// Polygonizes `field` over an axis-aligned grid using naive surface nets.
  /// Vertices are the mean of a cell's edge crossings, normals come from the
  /// field gradient, and quads are emitted per sign-changing grid edge with
  /// winding chosen so triangles face the positive (outside) side.
  static func surfaceNetsMesh(
    field: (SIMD3<Float>) -> Float,
    lower: SIMD3<Float>,
    upper: SIMD3<Float>,
    cellSize: Float
  ) -> BeamdeskSurfaceMesh {
    let n = SIMD3<Int>(
      Int(ceil((upper.x - lower.x) / cellSize)),
      Int(ceil((upper.y - lower.y) / cellSize)),
      Int(ceil((upper.z - lower.z) / cellSize)))
    func position(_ x: Int, _ y: Int, _ z: Int) -> SIMD3<Float> {
      lower + SIMD3<Float>(Float(x), Float(y), Float(z)) * cellSize
    }
    var samples = [Float](repeating: 0, count: (n.x + 1) * (n.y + 1) * (n.z + 1))
    func sampleIndex(_ x: Int, _ y: Int, _ z: Int) -> Int {
      (x * (n.y + 1) + y) * (n.z + 1) + z
    }
    for x in 0...n.x {
      for y in 0...n.y {
        for z in 0...n.z {
          samples[sampleIndex(x, y, z)] = field(position(x, y, z))
        }
      }
    }

    let corners: [SIMD3<Int>] = [
      SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(1, 1, 0),
      SIMD3(0, 0, 1), SIMD3(1, 0, 1), SIMD3(0, 1, 1), SIMD3(1, 1, 1),
    ]
    let edges: [(Int, Int)] = [
      (0, 1), (2, 3), (4, 5), (6, 7), (0, 2), (1, 3),
      (4, 6), (5, 7), (0, 4), (1, 5), (2, 6), (3, 7),
    ]
    var cellVertex = [Int32](repeating: -1, count: max(n.x * n.y * n.z, 1))
    func cellIndex(_ x: Int, _ y: Int, _ z: Int) -> Int { (x * n.y + y) * n.z + z }

    var vertices: [SIMD3<Float>] = []
    for x in 0..<n.x {
      for y in 0..<n.y {
        for z in 0..<n.z {
          var values = [Float](repeating: 0, count: 8)
          for (i, c) in corners.enumerated() {
            values[i] = samples[sampleIndex(x + c.x, y + c.y, z + c.z)]
          }
          var crossingSum = SIMD3<Float>(repeating: 0)
          var crossingCount: Float = 0
          for (a, b) in edges where (values[a] < 0) != (values[b] < 0) {
            let t = values[a] / (values[a] - values[b])
            let pa = SIMD3<Float>(corners[a]), pb = SIMD3<Float>(corners[b])
            crossingSum += pa + (pb - pa) * t
            crossingCount += 1
          }
          guard crossingCount > 0 else { continue }
          cellVertex[cellIndex(x, y, z)] = Int32(vertices.count)
          vertices.append(position(x, y, z) + crossingSum / crossingCount * cellSize)
        }
      }
    }

    var indices: [Int32] = []
    // One quad per sign-changing grid edge, spanning the four adjacent cells.
    // Cyclic (axis, u, v) keeps the right-handed winding rule uniform.
    for axis in 0..<3 {
      let u = (axis + 1) % 3, v = (axis + 2) % 3
      var coordinate = SIMD3<Int>(repeating: 0)
      for a in 0..<n[axis] {
        for b in 1..<n[u] {
          for c in 1..<n[v] {
            coordinate[axis] = a
            coordinate[u] = b
            coordinate[v] = c
            let near = samples[sampleIndex(coordinate.x, coordinate.y, coordinate.z)]
            var farCoordinate = coordinate
            farCoordinate[axis] += 1
            let far = samples[sampleIndex(farCoordinate.x, farCoordinate.y, farCoordinate.z)]
            guard (near < 0) != (far < 0) else { continue }
            var quad = [Int32]()
            for (du, dv) in [(-1, -1), (0, -1), (0, 0), (-1, 0)] {
              var cell = coordinate
              cell[u] += du
              cell[v] += dv
              quad.append(cellVertex[cellIndex(cell.x, cell.y, cell.z)])
            }
            guard !quad.contains(-1) else { continue }
            if near >= 0 { quad.reverse() }
            indices += [quad[0], quad[1], quad[2], quad[0], quad[2], quad[3]]
          }
        }
      }
    }

    // Sub-cell features (e.g. two creases crossing) can pinch naive surface
    // nets, folding the shell so one directed edge is emitted twice. Weld
    // such edges shut: merge their endpoints and drop the triangles the
    // collapse degenerates. Runs 0 times on a clean field; capped defensively.
    var welds = 0
    while welds < 16 {
      var seen = Set<Int64>()
      var pinched: (Int32, Int32)?
      scan: for t in stride(from: 0, to: indices.count, by: 3) {
        let tri = (indices[t], indices[t + 1], indices[t + 2])
        for (a, b) in [(tri.0, tri.1), (tri.1, tri.2), (tri.2, tri.0)] {
          if !seen.insert(Int64(a) << 32 | Int64(UInt32(bitPattern: b))).inserted {
            pinched = (a, b)
            break scan
          }
        }
      }
      guard let (keep, drop) = pinched else { break }
      vertices[Int(keep)] = (vertices[Int(keep)] + vertices[Int(drop)]) * 0.5
      var healed: [Int32] = []
      healed.reserveCapacity(indices.count)
      for t in stride(from: 0, to: indices.count, by: 3) {
        let tri = (0..<3).map { indices[t + $0] == drop ? keep : indices[t + $0] }
        if tri[0] != tri[1] && tri[1] != tri[2] && tri[2] != tri[0] { healed += tri }
      }
      indices = healed
      welds += 1
    }

    let eps = cellSize * 0.5
    let normals = vertices.map { p -> SIMD3<Float> in
      let g = SIMD3<Float>(
        field(p + SIMD3(eps, 0, 0)) - field(p - SIMD3(eps, 0, 0)),
        field(p + SIMD3(0, eps, 0)) - field(p - SIMD3(0, eps, 0)),
        field(p + SIMD3(0, 0, eps)) - field(p - SIMD3(0, 0, eps)))
      let length = simd_length(g)
      return length > 0 ? g / length : SIMD3(0, 0, 1)
    }
    return BeamdeskSurfaceMesh(vertices: vertices, normals: normals, indices: indices)
  }

  // MARK: - Prebaked meshes and SceneKit bridge

  static func fistMesh(inward: Float) -> BeamdeskSurfaceMesh {
    surfaceNetsMesh(
      field: fistField(inward: inward),
      lower: SIMD3(-1.05, -2.80, -0.65),
      upper: SIMD3(1.05, 0.70, 0.65),
      cellSize: 0.034)
  }

  static func thumbBridgeMesh(inward: Float) -> BeamdeskSurfaceMesh {
    surfaceNetsMesh(
      field: thumbBridgeField(inward: inward),
      lower: SIMD3(-0.55, -0.60, -0.60),
      upper: SIMD3(0.55, 0.34, 0.34),
      cellSize: 0.022)
  }

  static func thumbSegmentMesh(
    baseRadius: Float, tipRadius: Float, length: Float
  ) -> BeamdeskSurfaceMesh {
    surfaceNetsMesh(
      field: thumbSegmentField(baseRadius: baseRadius, tipRadius: tipRadius, length: length),
      lower: SIMD3(-0.30, -0.34, -0.30),
      upper: SIMD3(0.30, length + tipRadius + 0.10, 0.30),
      cellSize: 0.017)
  }

  static func geometry(from mesh: BeamdeskSurfaceMesh, material: SCNMaterial) -> SCNGeometry {
    let stride = MemoryLayout<SIMD3<Float>>.stride
    func source(_ data: [SIMD3<Float>], _ semantic: SCNGeometrySource.Semantic)
      -> SCNGeometrySource
    {
      SCNGeometrySource(
        data: data.withUnsafeBytes { Data($0) },
        semantic: semantic,
        vectorCount: data.count,
        usesFloatComponents: true,
        componentsPerVector: 3,
        bytesPerComponent: MemoryLayout<Float>.size,
        dataOffset: 0,
        dataStride: stride)
    }
    let element = SCNGeometryElement(
      data: mesh.indices.withUnsafeBytes { Data($0) },
      primitiveType: .triangles,
      primitiveCount: mesh.indices.count / 3,
      bytesPerIndex: MemoryLayout<Int32>.size)
    let geometry = SCNGeometry(
      sources: [source(mesh.vertices, .vertex), source(mesh.normals, .normal)],
      elements: [element])
    geometry.materials = [material]
    return geometry
  }
}
