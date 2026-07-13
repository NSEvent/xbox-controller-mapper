import Foundation
import SwiftUI
import AppKit
import Combine
import IOKit.hid
import CoreBluetooth
import ApplicationServices

/// Tri-state for a macOS privacy permission, as surfaced in the onboarding UI.
///
/// macOS Accessibility is really binary (trusted / not trusted) so we map "not
/// trusted" to `.notDetermined` — the user always has an action to take, and we
/// can't reliably distinguish "never asked" from "explicitly denied" for it.
enum PermissionState: Equatable {
    case granted
    case denied
    case notDetermined
}

/// Low-level, **nonisolated** permission probes.
///
/// These only *read* current TCC state — none of them trigger a system prompt —
/// so they're cheap and safe to call from any thread or actor. In particular
/// `ControllerService`'s controller-connect path and `ServiceContainer.init`
/// use these to decide whether a permission is already granted (returning user)
/// before starting the services that would otherwise cold-trigger a prompt.
enum SystemPermission {
    /// Accessibility — required to post synthesized keyboard/mouse events and to
    /// install a local `NSEvent` monitor. The make-or-break permission.
    static var accessibilityGranted: Bool { AXIsProcessTrusted() }

    /// Input Monitoring — required to *read* controller input via `IOHIDManager`
    /// (Steam controllers, generic HID gamepads, the Apple TV remote, and the
    /// Xbox guide button). Plain `GCController` gamepad input does **not** need
    /// it, so basic PS/Xbox pads still work without this granted.
    static var inputMonitoring: PermissionState {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: return .granted
        case kIOHIDAccessTypeDenied: return .denied
        default: return .notDetermined
        }
    }

    static var inputMonitoringGranted: Bool { inputMonitoring == .granted }

    /// Bluetooth — required by CoreBluetooth to read wireless-controller battery
    /// level over GATT. Reading `CBManager.authorization` does not prompt; only
    /// constructing a `CBCentralManager` does.
    static var bluetooth: PermissionState {
        switch CBManager.authorization {
        case .allowedAlways: return .granted
        case .denied, .restricted: return .denied
        default: return .notDetermined
        }
    }

    static var bluetoothGranted: Bool { bluetooth == .granted }
}

/// Centralizes live permission status, the guided-onboarding request actions,
/// and the "permission just got granted" side effects.
///
/// The previous design fired up to four TCC prompts simultaneously at launch
/// (accessibility, input monitoring, bluetooth, local network) with no context,
/// and nothing ever observed the grant flipping true — so even after the user
/// toggled Accessibility on, the input event monitor stayed dead until a manual
/// relaunch. This type fixes both: the onboarding flow drives one prompt at a
/// time, and `startPolling()` watches for grants and re-activates the dependent
/// services live (`onAccessibilityGranted` / `onInputMonitoringGranted`).
@MainActor
final class PermissionsManager: ObservableObject {
    static let shared = PermissionsManager()

    @Published private(set) var accessibility: PermissionState = .notDetermined
    @Published private(set) var inputMonitoring: PermissionState = .notDetermined
    @Published private(set) var bluetooth: PermissionState = .notDetermined

    /// Fired exactly once when the corresponding permission transitions into
    /// `.granted` while the app is running. The app wires these (in
    /// `AppDelegate`) to restart the services that depend on each permission, so
    /// a grant takes effect without a relaunch. Bluetooth needs no grant hook —
    /// `requestBluetooth` starts the battery monitor, which begins scanning on
    /// its own once CoreBluetooth reports `.poweredOn`.
    var onAccessibilityGranted: (@MainActor () -> Void)?
    var onInputMonitoringGranted: (@MainActor () -> Void)?

    /// Wired by the app to start the Bluetooth battery monitor (which constructs
    /// the `CBCentralManager` that triggers the system prompt). Kept as a hook
    /// so the onboarding view stays decoupled from `ServiceContainer`.
    var requestBluetoothAction: (@MainActor () -> Void)?

    private var pollTimer: Timer?

    private init() {
        refresh()
    }

    // MARK: - Status

    /// Re-reads every permission and fires the one-shot grant hooks on any
    /// `false → granted` transition. Cheap; safe to call on a timer.
    func refresh() {
        applyAccessibility(SystemPermission.accessibilityGranted ? .granted : .notDetermined)
        applyInputMonitoring(SystemPermission.inputMonitoring)
        bluetooth = SystemPermission.bluetooth
    }

    private func applyAccessibility(_ newValue: PermissionState) {
        let wasGranted = accessibility == .granted
        accessibility = newValue
        if newValue == .granted && !wasGranted {
            onAccessibilityGranted?()
        }
    }

    private func applyInputMonitoring(_ newValue: PermissionState) {
        let wasGranted = inputMonitoring == .granted
        inputMonitoring = newValue
        if newValue == .granted && !wasGranted {
            onInputMonitoringGranted?()
        }
    }

    /// Accessibility is the only permission whose absence makes the app inert,
    /// so the "permission was revoked" banner keys off this.
    var accessibilityGranted: Bool { accessibility == .granted }

    // MARK: - Polling

    /// Begins ~1s polling of TCC state. Used while the onboarding wizard (or the
    /// revoked-permission banner) is on screen so cards flip to "Granted ✓" the
    /// instant the user toggles a switch in System Settings — no relaunch, no
    /// guessing. Idempotent.
    func startPolling() {
        guard pollTimer == nil else { return }
        refresh()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Request actions (user-initiated, from the onboarding wizard)

    /// Adds the app to the Accessibility list, attempts the system prompt as a
    /// courtesy, and deep-links to the pane so the user only has to flip the
    /// switch. The prompt is unreliable on recent macOS / after app updates, so
    /// the deep-link + live polling is what actually makes this dependable.
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        openSettings("com.apple.preference.security?Privacy_Accessibility")
    }

    /// Triggers the Input Monitoring system prompt (and adds the app to the
    /// list) the first time, then deep-links to the pane for repeat visits.
    func requestInputMonitoring() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        openSettings("com.apple.preference.security?Privacy_ListenEvent")
    }

    /// Starts the Bluetooth battery monitor, which constructs the
    /// `CBCentralManager` that shows the system prompt.
    func requestBluetooth() {
        requestBluetoothAction?()
    }

    func openAccessibilitySettings() {
        openSettings("com.apple.preference.security?Privacy_Accessibility")
    }

    func openInputMonitoringSettings() {
        openSettings("com.apple.preference.security?Privacy_ListenEvent")
    }

    func openBluetoothSettings() {
        openSettings("com.apple.preference.security?Privacy_Bluetooth")
    }

    /// Reveals ControllerKeys.app in Finder so the user can drag it into the
    /// permission list if the "+" route is easier for them.
    func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    /// Relaunch fallback for the stale-TCC-after-update case, where macOS has
    /// the app listed and checked but the running process still reads as
    /// untrusted until a fresh launch.
    func relaunchApp() {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    private func openSettings(_ path: String) {
        guard let url = URL(string: "x-apple.systempreferences:\(path)") else { return }
        NSWorkspace.shared.open(url)
    }
}
