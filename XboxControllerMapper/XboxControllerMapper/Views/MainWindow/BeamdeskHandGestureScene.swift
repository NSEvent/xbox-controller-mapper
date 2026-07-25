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

	@MainActor
	final class Coordinator {
		private var rigs: [BeamdeskHandSide: BeamdeskHandRig] = [:]
		private var lastActivationID = 0
		private var pendingPresentation: BeamdeskGesturePresentation?
		private weak var installedScene: SCNScene?
		private var meshLoadTask: Task<Void, Never>?

		func install(in view: SCNView) {
			let scene = SCNScene()
			installedScene = scene
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

			meshLoadTask?.cancel()
			meshLoadTask = Task { @MainActor [weak self, weak scene] in
				let meshes = await BeamdeskHandMeshCache.load()
				guard let self, let scene, !Task.isCancelled, self.installedScene === scene else {
					return
				}
				self.installRigs(in: scene, meshes: meshes)
			}
		}

		private func installRigs(in scene: SCNScene, meshes: BeamdeskHandMeshLibrary) {
			let left = BeamdeskHandRig(side: .left, meshes: meshes)
			let right = BeamdeskHandRig(side: .right, meshes: meshes)
			left.root.position = SCNVector3(-0.72, -0.02, 0)
			right.root.position = SCNVector3(0.72, -0.02, 0)
			scene.rootNode.addChildNode(left.root)
			scene.rootNode.addChildNode(right.root)
			rigs = [.left: left, .right: right]
			if let pendingPresentation {
				animate(pendingPresentation)
			}
		}

		func releaseScene() {
			meshLoadTask?.cancel()
			meshLoadTask = nil
			installedScene = nil
			pendingPresentation = nil
			rigs.removeAll()
		}

		func present(_ presentation: BeamdeskGesturePresentation?, activationID: Int) {
			guard activationID != lastActivationID, let presentation else { return }
			lastActivationID = activationID
			pendingPresentation = presentation
			animate(presentation)
		}

		private func animate(_ presentation: BeamdeskGesturePresentation) {
			guard !rigs.isEmpty else { return }
			pendingPresentation = nil
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
	private var animationToken = 0

	private var restThumbPosition: SCNVector3 {
		// POV fists: each thumb rises from its fist's inner edge, matching the
		// first-person reference photo (left thumb screen-right of its fist).
		SCNVector3(side.inwardSign * 0.30, -0.14, 0.50)
	}

	init(side: BeamdeskHandSide, meshes: BeamdeskHandMeshLibrary) {
		self.side = side
		configureMaterials()
		buildHand(meshes: meshes)
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

		let isHorizontalSwipe =
			presentation.gesture == .swipeLeft || presentation.gesture == .swipeRight
		// Depth gestures stay on the 0.42 plane so the thumb grazes the sculpted
		// fist shell while it slides instead of submerging into the mesh.
		let contact = SCNVector3(
			restThumbPosition.x - side.profileSign * 0.04,
			restThumbPosition.y + 0.06,
			isHorizontalSwipe ? 0.58 : 0.42
		)
		let semanticOffset = presentation.thumbSlideOffset
		// Keep the CMC attached to the hand. Joint flex supplies most of the visible
		// travel while a smaller root translation traces the recognized direction.
		// Depth (z) travel is damped further: under the orthographic camera it adds
		// no on-screen motion, it only sinks the thumb behind the sculpted shell.
		let rootMotionScale: CGFloat = 0.38
		let depthMotionScale: CGFloat = 0.22
		let offset = SCNVector3(
			semanticOffset.x * rootMotionScale,
			semanticOffset.y * rootMotionScale,
			semanticOffset.z * depthMotionScale
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
			gestureDuration: gestureDuration,
			finalZ: presentation.finalArticulation.lateralSweep
		)
		animateArticulation(
			keyPath: \BeamdeskThumbArticulation.mcpFlex,
			on: thumbMCPJoint,
			final: presentation.finalArticulation,
			gestureDuration: gestureDuration,
			restZ: -side.profileSign * 0.035,
			finalZ: -side.profileSign * 0.035 + presentation.finalArticulation.lateralSweep * 0.42
		)
		animateArticulation(
			keyPath: \BeamdeskThumbArticulation.ipFlex,
			on: thumbIPJoint,
			final: presentation.finalArticulation,
			gestureDuration: gestureDuration,
			restZ: side.profileSign * 0.025,
			finalZ: side.profileSign * 0.025 + presentation.finalArticulation.lateralSweep * 0.14
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
		// The trail is HUD feedback, not anatomy: render it over the hands so
		// depth-gesture trails aren't swallowed by the fist mesh.
		motionMaterial.readsFromDepthBuffer = false

		nailMaterial.diffuse.contents = NSColor(
			calibratedRed: 0.66, green: 0.96, blue: 0.98, alpha: 1)
		nailMaterial.roughness.contents = 0.38
		nailMaterial.metalness.contents = 0.02
		nailMaterial.lightingModel = .physicallyBased
	}

	private func buildHand(meshes: BeamdeskHandMeshLibrary) {
		// First-person thumbs-up pose from the reference photo: backs of the
		// hands and thumb-side surfaces face the viewer, palms stay hidden.
		// The whole fist — dorsal dome, curled digits, wrist, forearm — is one
		// sculpted signed-distance shell (see BeamdeskHandGeometry) so the
		// silhouette reads as a single form; only the animated thumb is separate.
		root.eulerAngles.x = -.pi / 8
		root.eulerAngles.y = side.profileSign * .pi / 24
		root.eulerAngles.z = side.profileSign * .pi / 20
		root.scale = SCNVector3(0.98, 0.98, 0.98)

		addSculptedNode(mesh: meshes.fist(inward: inwardSign), to: root)
		buildThumb(meshes: meshes)
	}

	private var inwardSign: Float { Float(side.inwardSign) }

	private func addSculptedNode(mesh: BeamdeskSurfaceMesh, to parent: SCNNode) {
		let node = SCNNode(geometry: BeamdeskHandGeometry.geometry(from: mesh, material: skinMaterial))
		node.name = "skin"
		parent.addChildNode(node)
	}

	private func buildThumb(meshes: BeamdeskHandMeshLibrary) {
		thumbRoot.position = restThumbPosition
		// The photo reference shows the nail-facing back of a nearly vertical
		// thumb. The sculpted thenar bridge joins the fist to the CMC; from there
		// the metacarpal and both phalanges are sculpted shells whose bases bulge
		// over their pivot and whose shafts overrun the next joint, so the
		// silhouette stays sealed through the full articulation range.
		thumbRoot.eulerAngles.z = -side.profileSign * 0.12
		root.addChildNode(thumbRoot)

		addSculptedNode(mesh: meshes.thumbBridge(inward: inwardSign), to: thumbRoot)

		// Radii nest downward (each joint's base cap swallows its parent's tip)
		// so the overlapping shells never show a ridge along the column.
		thumbRoot.addChildNode(thumbCMCJoint)
		addSculptedNode(
			mesh: meshes.thumbCMC,
			to: thumbCMCJoint)

		thumbMCPJoint.position = SCNVector3(0, 0.35, 0)
		thumbCMCJoint.addChildNode(thumbMCPJoint)
		addSculptedNode(
			mesh: meshes.thumbMCP,
			to: thumbMCPJoint)

		thumbIPJoint.position = SCNVector3(0, 0.41, 0)
		thumbMCPJoint.addChildNode(thumbIPJoint)
		addSculptedNode(
			mesh: meshes.thumbIP,
			to: thumbIPJoint)

		let nail = SCNBox(width: 0.12, height: 0.20, length: 0.025, chamferRadius: 0.05)
		nail.firstMaterial = nailMaterial
		let nailNode = SCNNode(geometry: nail)
		nailNode.position = SCNVector3(0, 0.17, 0.128)
		nailNode.eulerAngles.x = -0.12
		thumbIPJoint.addChildNode(nailNode)

		setArticulation(.rest)
	}

	private func setArticulation(_ articulation: BeamdeskThumbArticulation) {
		thumbCMCJoint.eulerAngles = SCNVector3(
			-articulation.cmcFlex, 0, articulation.lateralSweep)
		thumbMCPJoint.eulerAngles = SCNVector3(
			-articulation.mcpFlex,
			0,
			-side.profileSign * 0.035 + articulation.lateralSweep * 0.42
		)
		thumbIPJoint.eulerAngles = SCNVector3(
			-articulation.ipFlex,
			0,
			side.profileSign * 0.025 + articulation.lateralSweep * 0.14
		)
	}

	private func animateArticulation(
		keyPath: KeyPath<BeamdeskThumbArticulation, CGFloat>,
		on joint: SCNNode,
		final: BeamdeskThumbArticulation,
		gestureDuration: TimeInterval,
		restZ: CGFloat = 0,
		finalZ: CGFloat = 0
	) {
		func rotate(
			to articulation: BeamdeskThumbArticulation,
			z: CGFloat,
			duration: TimeInterval
		) -> SCNAction {
			let action = SCNAction.rotateTo(
				x: -articulation[keyPath: keyPath],
				y: 0,
		z: z,
				duration: duration,
				usesShortestUnitArc: true
			)
			action.timingMode = .easeInEaseOut
			return action
		}

		joint.runAction(
			.sequence([
		rotate(to: .contact, z: restZ, duration: 0.20),
		rotate(to: final, z: finalZ, duration: gestureDuration),
				.wait(duration: 0.12),
		rotate(to: .rest, z: restZ, duration: 0.26),
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

}
