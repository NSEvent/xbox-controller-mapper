import Foundation
import AppKit
import GameController
import IOKit
import IOKit.hid

// MARK: - Battery Monitoring & Battery LED Animation

@MainActor
extension ControllerService {

    /// (Re)starts battery polling. Bumping the generation token invalidates any
    /// previously scheduled poll chain, so repeated triggers (connect, BLE battery
    /// publishes, charging transitions) never multiply the 10s polling chains.
    func updateBatteryInfo() {
        batteryPollGeneration &+= 1
        pollBatteryInfo(generation: batteryPollGeneration)
    }

    /// Runs one battery poll and reschedules itself while connected. Bails when
    /// `generation` no longer matches `batteryPollGeneration` (a newer chain
    /// superseded this one). Internal for test visibility.
    func pollBatteryInfo(generation: UInt64) {
        guard generation == batteryPollGeneration else { return }
        guard steamHIDActiveDevice == nil else {
            updateBatteryLightBar()
            return
        }

		// Xbox battery over GameController is unreliable on macOS and can report
		// 0%/.unknown before the Bluetooth Battery Service read completes.
		let isAppleTVRemote = storage.lock.withLock { storage.isAppleTVRemote }
		let batteryController = connectedController ?? (isAppleTVRemote ? Self.connectedAppleTVRemoteController() : nil)
		let isXbox = batteryController?.extendedGamepad is GCXboxGamepad
		let bluetoothLevel = batteryMonitor.batteryLevel
		let prefersBluetoothBattery = isXbox || (isAppleTVRemote && bluetoothLevel != nil)
		let controllerBattery = batteryController?.battery
		if let reading = ControllerBatteryReadingResolver.resolve(
			prefersBluetoothBattery: prefersBluetoothBattery,
			bluetoothLevel: bluetoothLevel,
			bluetoothIsCharging: batteryMonitor.isCharging,
			controllerBatteryLevel: controllerBattery?.batteryLevel,
			controllerBatteryState: controllerBattery?.batteryState
		) {
			batteryLevel = reading.level
			batteryState = reading.state
		} else {
			batteryLevel = -1
			batteryState = .unknown
		}

        // Update battery light bar if enabled
        updateBatteryLightBar()

        if isConnected {
            DispatchQueue.main.asyncAfter(deadline: .now() + Config.batteryUpdateInterval) { [weak self] in
                self?.pollBatteryInfo(generation: generation)
            }
        }
    }

	private static func connectedAppleTVRemoteController() -> GCController? {
		GCController.controllers().first {
			isAppleTVRemoteMetadata(
				vendorName: $0.vendorName,
				productCategory: $0.productCategory
			)
		}
	}

    /// Updates the light bar color to reflect battery level when battery light bar mode is enabled.
    /// Red (0%) → Yellow (50%) → Green (100%). Blinks red at 5% or below.
    /// Plays a pulsing animation while charging.
    func updateBatteryLightBar() {
        guard threadSafeIsPlayStation,
              let currentSettings = threadSafeLEDSettings,
              currentSettings.batteryLightBar,
              currentSettings.lightBarEnabled,
              !partyModeEnabled,
              batteryLevel >= 0 else {
            stopBatteryBlink()
            stopChargingAnim()
            return
        }

        // Charging: pulse animation from current battery color up to green
        if batteryState == .charging {
            stopBatteryBlink()
            startChargingAnim()
            return
        } else {
            stopChargingAnim()
        }

        // Low battery: blink red
        if batteryLevel <= Config.batteryBlinkThreshold {
            startBatteryBlink()
            return
        } else {
            stopBatteryBlink()
        }

        applyBatteryColor()
    }

    /// Applies the static battery-level color (no animation).
    private func applyBatteryColor() {
        guard let currentSettings = threadSafeLEDSettings else { return }

        let level = Double(min(1.0, max(0.0, batteryLevel)))

        // Map battery 0-100% to hue 0°-120° (red → orange → yellow → green)
        let hue = level / 3.0
        let nsColor = NSColor(hue: hue, saturation: 1.0, brightness: 1.0, alpha: 1.0)
            .usingColorSpace(.sRGB) ?? NSColor(red: 1, green: 0, blue: 0, alpha: 1)

        var settings = currentSettings
        settings.lightBarColor = CodableColor(
            red: Double(nsColor.redComponent),
            green: Double(nsColor.greenComponent),
            blue: Double(nsColor.blueComponent)
        )
        applyLEDSettings(settings)
    }

    /// Returns the battery-level hue (0°-120°) as an RGB CodableColor.
    private func batteryHueColor() -> (red: Double, green: Double, blue: Double) {
        let level = Double(min(1.0, max(0.0, batteryLevel)))
        let hue = level / 3.0
        let nsColor = NSColor(hue: hue, saturation: 1.0, brightness: 1.0, alpha: 1.0)
            .usingColorSpace(.sRGB) ?? NSColor(red: 1, green: 0, blue: 0, alpha: 1)
        return (Double(nsColor.redComponent), Double(nsColor.greenComponent), Double(nsColor.blueComponent))
    }

    // MARK: - Low Battery Blink

    private func startBatteryBlink() {
        guard batteryBlinkTimer == nil else { return }
        batteryBlinkOn = true
        batteryBlinkTimer = Timer.scheduledTimer(withTimeInterval: Config.batteryBlinkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickBatteryBlink()
            }
        }
    }

    func stopBatteryBlink() {
        batteryBlinkTimer?.invalidate()
        batteryBlinkTimer = nil
    }

    private func tickBatteryBlink() {
        guard let currentSettings = threadSafeLEDSettings,
              currentSettings.batteryLightBar,
              currentSettings.lightBarEnabled,
              !partyModeEnabled else {
            stopBatteryBlink()
            return
        }

        batteryBlinkOn.toggle()

        var settings = currentSettings
        if batteryBlinkOn {
            settings.lightBarColor = CodableColor(red: 1.0, green: 0.0, blue: 0.0)
        } else {
            settings.lightBarColor = CodableColor(red: 0.0, green: 0.0, blue: 0.0)
        }
        applyLEDSettings(settings)
    }

    // MARK: - Charging Animation

    /// Pulsing animation while charging: smoothly breathes from the current battery color
    /// up to bright green and back, like energy flowing in.
    private func startChargingAnim() {
        guard chargingAnimTimer == nil else { return }
        chargingAnimPhase = 0.0
        let interval = 1.0 / Config.chargingAnimFrequency
        chargingAnimTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickChargingAnim()
            }
        }
    }

    func stopChargingAnim() {
        chargingAnimTimer?.invalidate()
        chargingAnimTimer = nil
    }

    private func tickChargingAnim() {
        guard let currentSettings = threadSafeLEDSettings,
              currentSettings.batteryLightBar,
              currentSettings.lightBarEnabled,
              !partyModeEnabled,
              batteryState == .charging else {
            stopChargingAnim()
            return
        }

        // Advance phase (0-1 over one cycle)
        let phaseStep = 1.0 / (Config.chargingAnimFrequency * Config.chargingAnimCycleDuration)
        chargingAnimPhase += phaseStep
        if chargingAnimPhase >= 1.0 { chargingAnimPhase -= 1.0 }

        // Smooth sine pulse: 0 → 1 → 0
        let pulse = (1.0 - cos(chargingAnimPhase * 2.0 * .pi)) / 2.0

        // Blend from battery-level color (base) toward bright green (target)
        let base = batteryHueColor()
        let targetGreen = (red: 0.0, green: 1.0, blue: 0.0)

        let r = base.red + (targetGreen.red - base.red) * pulse
        let g = base.green + (targetGreen.green - base.green) * pulse
        let b = base.blue + (targetGreen.blue - base.blue) * pulse

        var settings = currentSettings
        settings.lightBarColor = CodableColor(red: r, green: g, blue: b)
        applyLEDSettings(settings)
    }
}
