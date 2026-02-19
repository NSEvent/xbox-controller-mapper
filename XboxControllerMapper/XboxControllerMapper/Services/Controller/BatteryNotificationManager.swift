import Foundation
import UserNotifications
import Combine

/// Monitors controller battery level and sends macOS notifications at low thresholds
@MainActor
class BatteryNotificationManager {
    private var cancellables = Set<AnyCancellable>()
    private var hasNotifiedAt20 = false
    private var hasNotifiedAt10 = false
    private var hasRequestedPermission = false

    private let warningThreshold: Float = 0.20
    private let criticalThreshold: Float = 0.10
    private let resetMargin: Float = 0.05

    func startMonitoring(controllerService: ControllerService) {
        controllerService.$batteryLevel
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.handleBatteryUpdate(level: level)
            }
            .store(in: &cancellables)

        // Reset notification state on disconnect
        controllerService.$isConnected
            .removeDuplicates()
            .filter { $0 == false }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reset()
            }
            .store(in: &cancellables)
    }

    private func handleBatteryUpdate(level: Float) {
        // Ignore unknown/invalid battery levels
        guard level >= 0 && level <= 1.0 else { return }

        // Reset flags when charged above threshold + margin
        if level > warningThreshold + resetMargin {
            hasNotifiedAt20 = false
        }
        if level > criticalThreshold + resetMargin {
            hasNotifiedAt10 = false
        }

        // Check critical threshold (10%)
        if level <= criticalThreshold && !hasNotifiedAt10 {
            hasNotifiedAt10 = true
            sendNotification(
                title: "Controller Battery Critical",
                body: "Battery at \(Int(level * 100))%. Connect charger soon.",
                identifier: "controllerkeys-battery-critical"
            )
        }
        // Check warning threshold (20%)
        else if level <= warningThreshold && !hasNotifiedAt20 {
            hasNotifiedAt20 = true
            sendNotification(
                title: "Controller Battery Low",
                body: "Battery at \(Int(level * 100))%.",
                identifier: "controllerkeys-battery-warning"
            )
        }
    }

    private func sendNotification(title: String, body: String, identifier: String) {
        let center = UNUserNotificationCenter.current()

        if !hasRequestedPermission {
            hasRequestedPermission = true
            center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
                if granted {
                    self?.postNotification(center: center, title: title, body: body, identifier: identifier)
                }
            }
        } else {
            postNotification(center: center, title: title, body: body, identifier: identifier)
        }
    }

    private func postNotification(center: UNUserNotificationCenter, title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            if let error = error {
                NSLog("[BatteryNotification] Failed to send: \(error.localizedDescription)")
            }
        }
    }

    /// Reset notification state (called on controller disconnect)
    func reset() {
        hasNotifiedAt20 = false
        hasNotifiedAt10 = false
    }
}
