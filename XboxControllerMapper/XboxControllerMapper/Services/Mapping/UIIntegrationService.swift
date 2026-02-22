import Foundation
import CoreGraphics

/// Handles UI overlay integration: on-screen keyboard, command wheel, laser pointer,
/// directory navigator, D-pad navigation repeat, and swipe prediction intercepts.
///
/// Extracted from MappingEngine to reduce its responsibilities.
extension MappingEngine {

    // MARK: - On-Screen Keyboard

    /// Handles on-screen keyboard button press
    /// - holdMode: If true, shows keyboard while held. If false, toggles keyboard on/off.
    nonisolated func handleOnScreenKeyboardPressed(_ button: ControllerButton, holdMode: Bool) {
        state.lock.withLock {
            state.onScreenKeyboardButton = button
            state.onScreenKeyboardHoldMode = holdMode
            if holdMode {
                state.commandWheelActive = true
            }
        }

        DispatchQueue.main.async { [weak self] in
            if holdMode {
                OnScreenKeyboardManager.shared.show()
                self?.controllerService.playHaptic(
                    intensity: Config.keyboardShowHapticIntensity,
                    sharpness: Config.keyboardShowHapticSharpness,
                    duration: Config.keyboardShowHapticDuration,
                    transient: true
                )
                let settings = self?.profileManager.onScreenKeyboardSettings
                let apps = settings?.appBarItems ?? []
                let websites = settings?.websiteLinks ?? []
                let showWebsitesFirst = settings?.wheelShowsWebsites == true
                if let self = self {
                    self.state.lock.withLock {
                        self.state.wheelAlternateModifiers = settings?.wheelAlternateModifiers ?? ModifierFlags()
                    }
                }
                if !apps.isEmpty || !websites.isEmpty {
                    CommandWheelManager.shared.prepare(apps: apps, websites: websites, showWebsitesFirst: showWebsitesFirst)
                    CommandWheelManager.shared.onSegmentChanged = { [weak self] in
                        self?.controllerService.playHaptic(
                            intensity: Config.wheelSegmentHapticIntensity,
                            sharpness: Config.wheelSegmentHapticSharpness,
                            transient: true
                        )
                    }
                    CommandWheelManager.shared.onPerimeterCrossed = { [weak self] in
                        self?.controllerService.playHaptic(
                            intensity: Config.wheelPerimeterHapticIntensity,
                            sharpness: Config.wheelPerimeterHapticSharpness,
                            transient: true
                        )
                    }
                    CommandWheelManager.shared.onForceQuitReady = { [weak self] in
                        self?.controllerService.playHaptic(
                            intensity: Config.wheelForceQuitHapticIntensity,
                            sharpness: Config.wheelForceQuitHapticSharpness,
                            transient: true
                        )
                        DispatchQueue.main.asyncAfter(deadline: .now() + Config.wheelForceQuitHapticGap) {
                            self?.controllerService.playHaptic(
                                intensity: Config.wheelForceQuitHapticIntensity,
                                sharpness: Config.wheelForceQuitHapticSharpness,
                                transient: true
                            )
                        }
                    }
                    CommandWheelManager.shared.onSelectionActivated = { [weak self] isSecondary in
                        let intensity = isSecondary ? Config.wheelSecondaryHapticIntensity : Config.wheelActivateHapticIntensity
                        let sharpness = isSecondary ? Config.wheelSecondaryHapticSharpness : Config.wheelActivateHapticSharpness
                        let duration = isSecondary ? Config.wheelSecondaryHapticDuration : Config.wheelActivateHapticDuration
                        self?.controllerService.playHaptic(
                            intensity: intensity,
                            sharpness: sharpness,
                            duration: duration,
                            transient: true
                        )
                    }
                    CommandWheelManager.shared.onItemSetChanged = { [weak self] isAlternate in
                        let intensity = isAlternate ? Config.wheelSetEnterHapticIntensity : Config.wheelSetExitHapticIntensity
                        let sharpness = isAlternate ? Config.wheelSetEnterHapticSharpness : Config.wheelSetExitHapticSharpness
                        let duration = isAlternate ? Config.wheelSetEnterHapticDuration : Config.wheelSetExitHapticDuration
                        self?.controllerService.playHaptic(
                            intensity: intensity,
                            sharpness: sharpness,
                            duration: duration,
                            transient: true
                        )
                    }
                }
            } else {
                let wasVisible = OnScreenKeyboardManager.shared.isVisible
                OnScreenKeyboardManager.shared.toggle()
                let isVisible = OnScreenKeyboardManager.shared.isVisible
                if isVisible != wasVisible {
                    let intensity = isVisible ? Config.keyboardShowHapticIntensity : Config.keyboardHideHapticIntensity
                    let sharpness = isVisible ? Config.keyboardShowHapticSharpness : Config.keyboardHideHapticSharpness
                    let duration = isVisible ? Config.keyboardShowHapticDuration : Config.keyboardHideHapticDuration
                    self?.controllerService.playHaptic(
                        intensity: intensity,
                        sharpness: sharpness,
                        duration: duration,
                        transient: true
                    )
                }
            }
        }
        inputLogService?.log(buttons: [button], type: .singlePress, action: "On-Screen Keyboard")
    }

    /// Handles on-screen keyboard button release (hides keyboard only in hold mode)
    nonisolated func handleOnScreenKeyboardReleased(_ button: ControllerButton) {
        let (wasKeyboardButton, wasHoldMode) = state.lock.withLock {
            let wasKeyboardButton = state.onScreenKeyboardButton == button
            let wasHoldMode = state.onScreenKeyboardHoldMode
            if wasKeyboardButton {
                state.onScreenKeyboardButton = nil
                state.commandWheelActive = false
            }
            return (wasKeyboardButton, wasHoldMode)
        }

        if wasKeyboardButton && wasHoldMode {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                CommandWheelManager.shared.activateSelection()
                CommandWheelManager.shared.hide()
                OnScreenKeyboardManager.shared.hide()
                self.controllerService.playHaptic(
                    intensity: Config.keyboardHideHapticIntensity,
                    sharpness: Config.keyboardHideHapticSharpness,
                    duration: Config.keyboardHideHapticDuration,
                    transient: true
                )
            }
        }
    }

    // MARK: - Laser Pointer

    nonisolated func handleLaserPointerPressed(_ button: ControllerButton, holdMode: Bool) {
        state.lock.withLock {
            state.laserPointerButton = button
            state.laserPointerHoldMode = holdMode
        }

        DispatchQueue.main.async {
            if holdMode {
                LaserPointerOverlay.shared.show()
            } else {
                LaserPointerOverlay.shared.toggle()
            }
        }
        inputLogService?.log(buttons: [button], type: .singlePress, action: "Laser Pointer")
    }

    nonisolated func handleLaserPointerReleased(_ button: ControllerButton) {
        let (wasLaserButton, wasHoldMode) = state.lock.withLock {
            let wasLaserButton = state.laserPointerButton == button
            let wasHoldMode = state.laserPointerHoldMode
            if wasLaserButton {
                state.laserPointerButton = nil
            }
            return (wasLaserButton, wasHoldMode)
        }

        if wasLaserButton && wasHoldMode {
            DispatchQueue.main.async {
                LaserPointerOverlay.shared.hide()
            }
        }
    }

    // MARK: - Directory Navigator

    nonisolated func handleDirectoryNavigatorPressed(_ button: ControllerButton, holdMode: Bool) {
        state.lock.withLock {
            state.directoryNavigatorButton = button
            state.directoryNavigatorHoldMode = holdMode
        }

        DispatchQueue.main.async {
            if holdMode {
                DirectoryNavigatorManager.shared.show()
            } else {
                DirectoryNavigatorManager.shared.toggle()
            }
        }
        inputLogService?.log(buttons: [button], type: .singlePress, action: "Directory Navigator")
    }

    nonisolated func handleDirectoryNavigatorReleased(_ button: ControllerButton) {
        let (wasNavButton, wasHoldMode) = state.lock.withLock {
            let wasNavButton = state.directoryNavigatorButton == button
            let wasHoldMode = state.directoryNavigatorHoldMode
            if wasNavButton {
                state.directoryNavigatorButton = nil
            }
            return (wasNavButton, wasHoldMode)
        }

        if wasNavButton && wasHoldMode {
            DispatchQueue.main.async {
                DirectoryNavigatorManager.shared.hide()
            }
        }
    }

    // MARK: - D-Pad Navigation Repeat

    nonisolated func startDpadNavigationRepeat(_ button: ControllerButton) {
        let timer = DispatchSource.makeTimerSource(queue: inputQueue)
        timer.schedule(
            deadline: .now() + Config.dpadRepeatInitialDelay,
            repeating: Config.dpadRepeatInterval
        )
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            let keyboardVisible = OnScreenKeyboardManager.shared.threadSafeIsVisible
            let navigatorVisible = DirectoryNavigatorManager.shared.threadSafeIsVisible
            guard keyboardVisible || navigatorVisible else {
                self.stopDpadNavigationRepeat(button)
                return
            }
            Task { @MainActor in
                if navigatorVisible {
                    DirectoryNavigatorManager.shared.handleDPadNavigation(button)
                } else {
                    OnScreenKeyboardManager.shared.handleDPadNavigation(button)
                }
            }
        }
        state.lock.withLock {
            state.dpadNavigationTimer?.cancel()
            state.dpadNavigationButton = button
            state.dpadNavigationTimer = timer
        }
        timer.resume()
    }

    nonisolated func stopDpadNavigationRepeat(_ button: ControllerButton) {
        state.lock.lock()
        defer { state.lock.unlock() }
        if state.dpadNavigationButton == button {
            state.dpadNavigationTimer?.cancel()
            state.dpadNavigationTimer = nil
            state.dpadNavigationButton = nil
        }
    }
}
