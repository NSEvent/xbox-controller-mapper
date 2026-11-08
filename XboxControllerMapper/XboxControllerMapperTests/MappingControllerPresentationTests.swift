import XCTest
import Combine
@testable import ControllerKeys

@MainActor
final class MappingControllerPresentationTests: XCTestCase {
	private struct EditorContext: MappingControllerTypeProviding {
		let controllerService: ControllerService
		let profileManager: ProfileManager
	}

	private var context: EditorContext!
	private var directory: URL!

	override func setUp() async throws {
		try await super.setUp()
		directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		context = EditorContext(
			controllerService: ControllerService(enableHardwareMonitoring: false),
			profileManager: ProfileManager(configDirectoryOverride: directory)
		)
	}

	override func tearDown() async throws {
		context.profileManager.flushPendingSaves()
		context = nil
		try? FileManager.default.removeItem(at: directory)
		try await super.tearDown()
	}

	func testAllMappingSurfacesUseMappingPresentation() {
		// Compile-time guard: a surface reverting to the hardware-only protocol
		// must also deliberately change this regression test.
		func requireMappingPresentation<T: MappingControllerTypeProviding>(_: T.Type) {}
		requireMappingPresentation(ChordMappingSheet.self)
		requireMappingPresentation(SequenceMappingSheet.self)
		requireMappingPresentation(ChordsTab.self)
		requireMappingPresentation(SequencesTab.self)
		requireMappingPresentation(AddLayerSheet.self)
		requireMappingPresentation(EditLayerSheet.self)
		requireMappingPresentation(LayerTabBar.self)
		requireMappingPresentation(ActiveChordsView.self)
		requireMappingPresentation(ActiveSequencesView.self)
	}

	func testEveryExplicitPreviewWinsOverXboxHardwareConnectedOrDisconnected() {
		for connected in [false, true] {
			context.controllerService.isConnected = connected
			for layout in ControllerPreviewLayout.concreteLayouts {
				context.profileManager.setControllerPreviewLayout(layout)
				XCTAssertEqual(context.controllerPresentationState.family,
					ControllerVisualDescriptor.concrete(for: layout)?.family,
					"Preview \(layout) must win with connected=\(connected)")
			}
		}
	}

	func testChangingPreviewUpdatesButtonLabelsAndExtraControls() {
		context.profileManager.setControllerPreviewLayout(.dualSenseEdge)
		XCTAssertTrue(context.controllerPresentationState.isPlayStation)
		XCTAssertTrue(context.controllerPresentationState.isDualSenseEdge)
		XCTAssertTrue(context.controllerPresentationState.supportedButtons.contains(.leftFunction))
		let playStationLabel = context.controllerPresentationState.buttonLabel(.a)
		context.profileManager.setControllerPreviewLayout(.xbox)
		XCTAssertFalse(context.controllerPresentationState.isPlayStation)
		XCTAssertFalse(context.controllerPresentationState.supportedButtons.contains(.leftFunction))
		XCTAssertNotEqual(context.controllerPresentationState.buttonLabel(.a), playStationLabel)
	}

	func testActivePreviewFollowsHardwareChangesButExplicitPreviewDoesNot() {
		context.controllerService.isConnected = true
		context.profileManager.setControllerPreviewLayout(.active)
		for type: ControllerTypeState in [.dualSense, .nintendo(.unknown), .steam, .wiimote, .xbox] {
			context.controllerService.storage.lock.withLock {
				context.controllerService.storage.applyControllerTypeLocked(type)
			}
			XCTAssertEqual(context.controllerPresentationState,
				ControllerVisualDescriptor.active(using: context.controllerService))
		}
		context.profileManager.setControllerPreviewLayout(.dualShock)
		XCTAssertTrue(context.controllerPresentationState.isDualShock)
		XCTAssertEqual(context.controllerService.threadSafeControllerPresentationState.controllerType, .xbox,
			"Selecting an editor preview must not mutate hardware identity")
	}

	func testSwitchingProfilesUsesThatProfilesSelectedLayout() {
		var first = Profile(name: "PlayStation")
		first.controllerPreviewLayout = .dualSense
		var second = Profile(name: "Nintendo")
		second.controllerPreviewLayout = .nintendo
		context.profileManager.profiles = [first, second]
		context.profileManager.setActiveProfile(second)
		XCTAssertTrue(context.controllerPresentationState.isNintendo)
		context.profileManager.setActiveProfile(first)
		XCTAssertTrue(context.controllerPresentationState.isPlayStation)
	}
	func testPhysicalButtonPublisherUpdatesPreviewAndEditorLabels() async {
		let controller = context.controllerService
		let manager = context.profileManager
		controller.isConnected = true
		controller.storage.lock.withLock { controller.storage.applyControllerTypeLocked(.dualSense) }
		manager.setControllerPreviewLayout(.xbox)
		let subscription = controller.previewActivity.sink { layout in
			manager.setControllerPreviewLayout(layout)
		}
		defer { subscription.cancel() }
		// Exercise the real async physical-input publication without an output handler.
		controller.buttonPressed(.a)
		controller.buttonReleased(.a)
		let followed = await waitForCondition(timeout: 1) {
			manager.activeProfile?.controllerPreviewLayout == .dualSense && controller.activeButtons.isEmpty
		}
		XCTAssertTrue(followed, "A fast press/release must still change the selected layout")
		XCTAssertTrue(context.controllerPresentationState.isPlayStation)
		manager.setControllerPreviewLayout(.nintendo)
		controller.activeButtons = []
		XCTAssertTrue(context.controllerPresentationState.isNintendo, "Idle input must preserve a manual choice")
		controller.buttonPressed(.b)
		controller.buttonReleased(.b)
		let followedAgain = await waitForCondition(timeout: 1) {
			manager.activeProfile?.controllerPreviewLayout == .dualSense && controller.activeButtons.isEmpty
		}
		XCTAssertTrue(followedAgain)
	}

}
