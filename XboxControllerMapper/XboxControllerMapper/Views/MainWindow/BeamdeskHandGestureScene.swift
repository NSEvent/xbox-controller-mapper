import SceneKit
import SwiftUI

struct BeamdeskHandGestureScene: NSViewRepresentable {
  let presentation: BeamdeskGesturePresentation?
  let activationID: Int

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> SCNView {
    let view = SCNView(frame: .zero)
    context.coordinator.install(in: view)
    return view
  }

  func updateNSView(_ view: SCNView, context: Context) {
    context.coordinator.present(presentation, activationID: activationID)
  }

  static func dismantleNSView(_ view: SCNView, coordinator: Coordinator) {
    view.isPlaying = false
    view.rendersContinuously = false
    view.scene = nil
    coordinator.releaseScene()
  }

  final class Coordinator {
    private var rigs: [BeamdeskHandSide: BeamdeskHandRig] = [:]
    private var lastActivationID = 0

    func install(in view: SCNView) {
      let scene = SCNScene()
      view.scene = scene
      view.backgroundColor = .clear
      view.allowsCameraControl = false
      view.autoenablesDefaultLighting = false
      view.antialiasingMode = .multisampling4X
      view.preferredFramesPerSecond = 30
      view.rendersContinuously = false
      view.isPlaying = true

      let camera = SCNCamera()
      camera.usesOrthographicProjection = true
      camera.orthographicScale = 1.88
      camera.zNear = 0.1
      camera.zFar = 100
      let cameraNode = SCNNode()
      cameraNode.camera = camera
      cameraNode.position = SCNVector3(0, -0.45, 11.5)
      cameraNode.look(at: SCNVector3(0, -0.12, 0))
      scene.rootNode.addChildNode(cameraNode)

      let ambient = SCNLight()
      ambient.type = .ambient
      ambient.intensity = 430
      ambient.color = NSColor(calibratedWhite: 0.72, alpha: 1)
      let ambientNode = SCNNode()
      ambientNode.light = ambient
      scene.rootNode.addChildNode(ambientNode)

      let key = SCNLight()
      key.type = .omni
      key.intensity = 1_250
      key.temperature = 7_800
      let keyNode = SCNNode()
      keyNode.light = key
      keyNode.position = SCNVector3(-1.5, 3.5, 6.5)
      scene.rootNode.addChildNode(keyNode)

      let left = BeamdeskHandRig(side: .left)
      let right = BeamdeskHandRig(side: .right)
      left.root.position = SCNVector3(-0.72, -0.02, 0)
      right.root.position = SCNVector3(0.72, -0.02, 0)
      scene.rootNode.addChildNode(left.root)
      scene.rootNode.addChildNode(right.root)
      rigs = [.left: left, .right: right]
    }

    func releaseScene() {
      rigs.removeAll()
    }

    func present(_ presentation: BeamdeskGesturePresentation?, activationID: Int) {
      guard activationID != lastActivationID, let presentation else { return }
      lastActivationID = activationID
      rigs[presentation.side]?.animate(presentation)
      rigs[presentation.side == .left ? .right : .left]?.setEmphasized(false)
    }
  }
}

private final class BeamdeskHandRig {
  let root = SCNNode()

  private let side: BeamdeskHandSide
  private let thumbRoot = SCNNode()
  private let thumbCMCJoint = SCNNode()
  private let thumbMCPJoint = SCNNode()
  private let thumbIPJoint = SCNNode()
  private let skinMaterial = SCNMaterial()
  private let accentMaterial = SCNMaterial()
  private let motionMaterial = SCNMaterial()
  private let nailMaterial = SCNMaterial()
  private let creaseMaterial = SCNMaterial()
  private var animationToken = 0

  private var restThumbPosition: SCNVector3 {
    SCNVector3(side.profileSign * 0.30, -0.14, 0.50)
  }

  init(side: BeamdeskHandSide) {
    self.side = side
    configureMaterials()
    buildHand()
  }

  func setEmphasized(_ emphasized: Bool) {
    root.enumerateChildNodes { node, _ in
      guard node.name == "skin" else { return }
      node.geometry?.firstMaterial = emphasized ? accentMaterial : skinMaterial
    }
  }

  func animate(_ presentation: BeamdeskGesturePresentation) {
    animationToken += 1
    let token = animationToken
    thumbRoot.removeAllActions()
    thumbCMCJoint.removeAllActions()
    thumbMCPJoint.removeAllActions()
    thumbIPJoint.removeAllActions()
    thumbRoot.position = restThumbPosition
    setArticulation(.rest)
    setEmphasized(true)

    let contact = SCNVector3(
      restThumbPosition.x - side.profileSign * 0.04,
      restThumbPosition.y + 0.06,
      0.34
    )
    let semanticOffset = presentation.thumbSlideOffset
    // Keep the CMC attached to the hand. Joint flex supplies most of the visible
    // travel while a smaller root translation traces the recognized direction.
    let rootMotionScale: CGFloat = 0.38
    let offset = SCNVector3(
      -semanticOffset.x * rootMotionScale,
      semanticOffset.y * rootMotionScale,
      semanticOffset.z * rootMotionScale
    )
    let end = SCNVector3(contact.x + offset.x, contact.y + offset.y, contact.z + offset.z)

    let touch = SCNAction.move(to: contact, duration: 0.20)
    touch.timingMode = SCNActionTimingMode.easeInEaseOut
    let gesture: SCNAction
    if presentation.gesture == .thumbTap {
      gesture = SCNAction.wait(duration: 0.22)
    } else {
      gesture = SCNAction.move(to: end, duration: 0.44)
      gesture.timingMode = SCNActionTimingMode.easeInEaseOut
    }
    let lift = SCNAction.move(to: restThumbPosition, duration: 0.26)
    lift.timingMode = SCNActionTimingMode.easeInEaseOut

    let gestureDuration = presentation.gesture == .thumbTap ? 0.22 : 0.44
    animateArticulation(
      keyPath: \BeamdeskThumbArticulation.cmcFlex,
      on: thumbCMCJoint,
      final: presentation.finalArticulation,
      gestureDuration: gestureDuration
    )
    animateArticulation(
      keyPath: \BeamdeskThumbArticulation.mcpFlex,
      on: thumbMCPJoint,
      final: presentation.finalArticulation,
      gestureDuration: gestureDuration,
      restZ: -side.profileSign * 0.035
    )
    animateArticulation(
      keyPath: \BeamdeskThumbArticulation.ipFlex,
      on: thumbIPJoint,
      final: presentation.finalArticulation,
      gestureDuration: gestureDuration,
      restZ: side.profileSign * 0.025
    )

    showMotionTrail(from: contact, to: end, gesture: presentation.gesture)
    thumbRoot.runAction(.sequence([touch, gesture, .wait(duration: 0.12), lift])) { [weak self] in
      guard let self, self.animationToken == token else { return }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
        guard let self, self.animationToken == token else { return }
        self.setEmphasized(false)
      }
    }
  }

  private func configureMaterials() {
    skinMaterial.diffuse.contents = NSColor(calibratedRed: 0.24, green: 0.72, blue: 0.79, alpha: 1)
    skinMaterial.metalness.contents = 0.04
    skinMaterial.roughness.contents = 0.46
    skinMaterial.lightingModel = .physicallyBased

    accentMaterial.diffuse.contents = NSColor(calibratedRed: 0.42, green: 0.96, blue: 1, alpha: 1)
    accentMaterial.emission.contents = NSColor(
      calibratedRed: 0.03, green: 0.42, blue: 0.50, alpha: 1)
    accentMaterial.metalness.contents = 0.38
    accentMaterial.roughness.contents = 0.24
    accentMaterial.lightingModel = .physicallyBased

    motionMaterial.diffuse.contents = NSColor(
      calibratedRed: 0.42, green: 0.96, blue: 1, alpha: 0.88)
    motionMaterial.emission.contents = NSColor(
      calibratedRed: 0.10, green: 0.72, blue: 0.82, alpha: 1)
    motionMaterial.blendMode = .add

    nailMaterial.diffuse.contents = NSColor(
      calibratedRed: 0.66, green: 0.96, blue: 0.98, alpha: 1)
    nailMaterial.roughness.contents = 0.38
    nailMaterial.metalness.contents = 0.02
    nailMaterial.lightingModel = .physicallyBased

    creaseMaterial.diffuse.contents = NSColor(
      calibratedRed: 0.08, green: 0.40, blue: 0.47, alpha: 0.72)
    creaseMaterial.roughness.contents = 0.72
    creaseMaterial.lightingModel = .physicallyBased
  }

  private func buildHand() {
    // Meta's microgesture pose is a thumb-side profile, not an open palm.
    // Tilt the wrist toward the viewer, hide the curled fingers behind the
    // back-of-hand mass, and leave only their inner silhouettes visible.
    root.eulerAngles.x = -.pi / 8
    root.eulerAngles.y = side.profileSign * .pi / 24
    root.eulerAngles.z = side.profileSign * .pi / 20
    root.scale = SCNVector3(0.98, 0.98, 0.98)

    addBox(width: 0.74, height: 0.96, length: 0.58, chamfer: 0.28, at: SCNVector3(0, -0.20, 0))
    addBackOfHandSurface()
    addCapsule(
      radius: 0.29,
      height: 1.24,
      at: SCNVector3(side.profileSign * 0.10, -1.00, -0.10),
      angle: side.profileSign * 0.14
    )
    addCurledFingers()
    buildThumb()
  }

  private func addBackOfHandSurface() {
    let back = SCNSphere(radius: 0.52)
    back.firstMaterial = skinMaterial
    let backNode = SCNNode(geometry: back)
    backNode.name = "skin"
    backNode.position = SCNVector3(-side.profileSign * 0.03, -0.22, 0.23)
    backNode.scale = SCNVector3(0.69, 1.08, 0.54)
    root.addChildNode(backNode)
  }

  private func addCurledFingers() {
    let inward = -side.profileSign
    let rows: [CGFloat] = [0.24, -0.01, -0.26, -0.49]

    for (index, y) in rows.enumerated() {
      let taper = 1 - CGFloat(index) * 0.045

      let middle = capsuleNode(radius: 0.125 * taper, height: 0.39 * taper)
      middle.position = SCNVector3(inward * 0.34, y, 0.13)
      middle.eulerAngles.z = -inward * .pi / 2
      root.addChildNode(middle)

      let distal = capsuleNode(radius: 0.112 * taper, height: 0.32 * taper)
      distal.position = SCNVector3(inward * 0.50, y - 0.055, 0.18)
      distal.eulerAngles.z = inward * 0.62
      root.addChildNode(distal)

      let fingertip = SCNSphere(radius: 0.122 * taper)
      fingertip.firstMaterial = skinMaterial
      let fingertipNode = SCNNode(geometry: fingertip)
      fingertipNode.name = "skin"
      fingertipNode.position = SCNVector3(inward * 0.57, y - 0.11, 0.19)
      fingertipNode.scale = SCNVector3(0.82, 1, 0.72)
      root.addChildNode(fingertipNode)

      let crease = SCNTorus(ringRadius: 0.088 * taper, pipeRadius: 0.009)
      crease.firstMaterial = creaseMaterial
      let creaseNode = SCNNode(geometry: crease)
      creaseNode.position = SCNVector3(inward * 0.54, y - 0.08, 0.24)
      creaseNode.eulerAngles.x = .pi / 2
      root.addChildNode(creaseNode)
    }
  }

  private func buildThumb() {
    thumbRoot.position = restThumbPosition
    // The photo reference shows the nail-facing back of a nearly vertical thumb.
    // Three true pivot nodes represent its CMC, MCP, and IP joints.
    thumbRoot.eulerAngles.z = -side.profileSign * 0.12
    root.addChildNode(thumbRoot)

    thumbRoot.addChildNode(thumbCMCJoint)
    addJointMass(radius: 0.205, to: thumbCMCJoint, showsCrease: false)
    addThumbSegment(radius: 0.19, height: 0.46, y: 0.17, to: thumbCMCJoint)

    thumbMCPJoint.position = SCNVector3(0, 0.35, 0)
    thumbCMCJoint.addChildNode(thumbMCPJoint)
    addJointMass(radius: 0.18, to: thumbMCPJoint, showsCrease: true)
    addThumbSegment(radius: 0.175, height: 0.50, y: 0.20, to: thumbMCPJoint)

    thumbIPJoint.position = SCNVector3(0, 0.41, 0)
    thumbMCPJoint.addChildNode(thumbIPJoint)
    addJointMass(radius: 0.16, to: thumbIPJoint, showsCrease: true)
    addThumbSegment(radius: 0.155, height: 0.46, y: 0.17, to: thumbIPJoint)

    let nail = SCNBox(width: 0.15, height: 0.27, length: 0.025, chamferRadius: 0.055)
    nail.firstMaterial = nailMaterial
    let nailNode = SCNNode(geometry: nail)
    nailNode.position = SCNVector3(0, 0.22, 0.16)
    thumbIPJoint.addChildNode(nailNode)

    setArticulation(.rest)
  }

  private func addThumbSegment(radius: CGFloat, height: CGFloat, y: CGFloat, to parent: SCNNode) {
    let segment = capsuleNode(radius: radius, height: height)
    segment.position = SCNVector3(0, y, 0)
    parent.addChildNode(segment)
  }

  private func addJointMass(radius: CGFloat, to parent: SCNNode, showsCrease: Bool) {
    let sphere = SCNSphere(radius: radius)
    sphere.firstMaterial = skinMaterial
    let sphereNode = SCNNode(geometry: sphere)
    sphereNode.name = "skin"
    sphereNode.scale = SCNVector3(1, 0.82, 0.94)
    parent.addChildNode(sphereNode)

    guard showsCrease else { return }
    let crease = SCNTorus(ringRadius: radius * 0.87, pipeRadius: 0.012)
    crease.firstMaterial = creaseMaterial
    let creaseNode = SCNNode(geometry: crease)
    creaseNode.position = SCNVector3(0, 0.012, 0)
    parent.addChildNode(creaseNode)
  }

  private func setArticulation(_ articulation: BeamdeskThumbArticulation) {
    thumbCMCJoint.eulerAngles = SCNVector3(-articulation.cmcFlex, 0, 0)
    thumbMCPJoint.eulerAngles = SCNVector3(
      -articulation.mcpFlex, 0, -side.profileSign * 0.035)
    thumbIPJoint.eulerAngles = SCNVector3(
      -articulation.ipFlex, 0, side.profileSign * 0.025)
  }

  private func animateArticulation(
    keyPath: KeyPath<BeamdeskThumbArticulation, CGFloat>,
    on joint: SCNNode,
    final: BeamdeskThumbArticulation,
    gestureDuration: TimeInterval,
    restZ: CGFloat = 0
  ) {
    func rotate(to articulation: BeamdeskThumbArticulation, duration: TimeInterval) -> SCNAction {
      let action = SCNAction.rotateTo(
        x: -articulation[keyPath: keyPath],
        y: 0,
        z: restZ,
        duration: duration,
        usesShortestUnitArc: true
      )
      action.timingMode = .easeInEaseOut
      return action
    }

    joint.runAction(
      .sequence([
        rotate(to: .contact, duration: 0.20),
        rotate(to: final, duration: gestureDuration),
        .wait(duration: 0.12),
        rotate(to: .rest, duration: 0.26),
      ]))
  }

  private func showMotionTrail(
    from start: SCNVector3, to end: SCNVector3, gesture: BeamdeskMicrogesture
  ) {
    let trail = SCNNode()
    trail.opacity = 0
    root.addChildNode(trail)

    if gesture == .thumbTap {
      let ring = SCNTorus(ringRadius: 0.24, pipeRadius: 0.035)
      ring.firstMaterial = motionMaterial
      trail.geometry = ring
      trail.position = start
      trail.eulerAngles.x = .pi / 2
      trail.runAction(
        .sequence([
          .fadeIn(duration: 0.10),
          .group([.scale(to: 1.8, duration: 0.38), .fadeOut(duration: 0.38)]),
          .removeFromParentNode(),
        ]))
      return
    }

    let delta = SCNVector3(end.x - start.x, end.y - start.y, end.z - start.z)
    let length = CGFloat(sqrt(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z))
    let capsule = SCNCapsule(capRadius: 0.035, height: max(length, 0.12))
    capsule.firstMaterial = motionMaterial
    trail.geometry = capsule
    trail.position = SCNVector3(
      (start.x + end.x) / 2,
      (start.y + end.y) / 2,
      (start.z + end.z) / 2
    )
    trail.look(at: end, up: root.worldUp, localFront: SCNVector3(0, 1, 0))
    trail.runAction(
      .sequence([
        .wait(duration: 0.12),
        .fadeIn(duration: 0.12),
        .wait(duration: 0.28),
        .fadeOut(duration: 0.24),
        .removeFromParentNode(),
      ]))
  }

  private func addBox(
    width: CGFloat,
    height: CGFloat,
    length: CGFloat,
    chamfer: CGFloat,
    at position: SCNVector3
  ) {
    let box = SCNBox(
      width: width,
      height: height,
      length: length,
      chamferRadius: chamfer
    )
    box.firstMaterial = skinMaterial
    let node = SCNNode(geometry: box)
    node.name = "skin"
    node.position = position
    root.addChildNode(node)
  }

  private func addCapsule(radius: CGFloat, height: CGFloat, at position: SCNVector3, angle: CGFloat)
  {
    let node = capsuleNode(radius: radius, height: height)
    node.position = position
    node.eulerAngles.z = angle
    root.addChildNode(node)
  }

  private func capsuleNode(radius: CGFloat, height: CGFloat) -> SCNNode {
    let capsule = SCNCapsule(capRadius: radius, height: max(height, radius * 2.02))
    capsule.firstMaterial = skinMaterial
    let node = SCNNode(geometry: capsule)
    node.name = "skin"
    return node
  }
}
