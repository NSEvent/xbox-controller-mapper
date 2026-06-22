import XCTest
import Combine
import CoreGraphics
import Carbon.HIToolbox
import SwiftUI
import AppKit
@testable import ControllerKeys

/// Shared fixture for MappingEngine integration tests.
/// Split out of the original monolithic XboxControllerMapperTests.swift; the
/// concrete test classes (MappingEngineCoreTests, LayerTests, etc.) inherit
/// this setUp/tearDown and the `waitForTasks` helper.
class MappingEngineTestCase: XCTestCase {

    var controllerService: ControllerService!
    var profileManager: ProfileManager!
    var appMonitor: AppMonitor!
    var mockInputSimulator: MockInputSimulator!
    var mappingEngine: MappingEngine!
    private var testConfigDirectory: URL!
    
    override func setUp() async throws {
        testConfigDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("controllerkeys-tests-\(UUID().uuidString)", isDirectory: true)

        await MainActor.run {
            controllerService = ControllerService(enableHardwareMonitoring: false)
            // Reduce chord window for faster test execution (50ms should be safe)
            controllerService.chordWindow = 0.05
            profileManager = ProfileManager(configDirectoryOverride: testConfigDirectory)
            appMonitor = AppMonitor()
            mockInputSimulator = MockInputSimulator()

            mappingEngine = MappingEngine(
                controllerService: controllerService,
                profileManager: profileManager,
                appMonitor: appMonitor,
                inputSimulator: mockInputSimulator
            )

            mappingEngine.enable()
        }
    }

    override func tearDown() async throws {
        // Disable engine and clean up to prevent state leakage between tests
        await MainActor.run {
            mappingEngine?.disable()
        }
        // Wait for any pending async work to complete
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        await MainActor.run {
            mockInputSimulator?.releaseAllModifiers()
            controllerService?.onInputEvent = nil
            controllerService?.cleanup() // Clean up HID resources before deallocation
            // Reset PlayStation controller flags to prevent LED code from running
            UserDefaults.standard.removeObject(forKey: Config.lastControllerWasDualSenseKey)
            UserDefaults.standard.removeObject(forKey: Config.lastControllerWasDualShockKey)
            mappingEngine = nil
            controllerService = nil
            profileManager = nil
            appMonitor = nil
            mockInputSimulator = nil
        }
        // Extra delay to let deallocation complete
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
    }

    func waitForTasks(_ delay: TimeInterval = 0.4) async {
        await Task.yield()
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        await Task.yield()
    }
}
