import Foundation
import AppKit

@MainActor
extension ControllerService {

    // MARK: - Display Update Timer

    func startDisplayUpdateTimer() {
        stopDisplayUpdateTimer()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now(), repeating: Config.displayRefreshInterval, leeway: .milliseconds(10))
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            PerformanceProbe.shared.recordDisplayTick()

            // Touchpad samples are not exposed via dedicated thread-safe accessors.
            self.storage.lock.lock()
            let touchPos = self.storage.touchpadPosition
            let touchSecPos = self.storage.touchpadSecondaryPosition
            let isTouching = self.storage.isTouchpadTouching
            let isSecTouching = self.storage.isTouchpadSecondaryTouching
            let steamLeftTouchPos = self.storage.steamLeftTouchpadPosition
            let steamRightTouchPos = self.storage.steamRightTouchpadPosition
            let isSteamLeftTouching = self.storage.isSteamLeftTouchpadTouching
            let isSteamRightTouching = self.storage.isSteamRightTouchpadTouching
            self.storage.lock.unlock()

            let currentState = ControllerDisplayState(
                leftStick: self.leftStick,
                rightStick: self.rightStick,
                leftTriggerValue: self.leftTriggerValue,
                rightTriggerValue: self.rightTriggerValue,
                displayLeftStick: self.displayLeftStick,
                displayRightStick: self.displayRightStick,
                displayLeftTrigger: self.displayLeftTrigger,
                displayRightTrigger: self.displayRightTrigger,
                displayTouchpadPosition: self.displayTouchpadPosition,
                displayTouchpadSecondaryPosition: self.displayTouchpadSecondaryPosition,
                displayIsTouchpadTouching: self.displayIsTouchpadTouching,
                displayIsTouchpadSecondaryTouching: self.displayIsTouchpadSecondaryTouching,
                displaySteamLeftTouchpadPosition: self.displaySteamLeftTouchpadPosition,
                displaySteamRightTouchpadPosition: self.displaySteamRightTouchpadPosition,
                displayIsSteamLeftTouchpadTouching: self.displayIsSteamLeftTouchpadTouching,
                displayIsSteamRightTouchpadTouching: self.displayIsSteamRightTouchpadTouching
            )
            let sample = ControllerDisplaySample(
                leftStick: self.threadSafeLeftStick,
                rightStick: self.threadSafeRightStick,
                leftTrigger: self.threadSafeLeftTrigger,
                rightTrigger: self.threadSafeRightTrigger,
                touchpadPosition: touchPos,
                touchpadSecondaryPosition: touchSecPos,
                isTouchpadTouching: isTouching,
                isTouchpadSecondaryTouching: isSecTouching,
                steamLeftTouchpadPosition: steamLeftTouchPos,
                steamRightTouchpadPosition: steamRightTouchPos,
                isSteamLeftTouchpadTouching: isSteamLeftTouching,
                isSteamRightTouchpadTouching: isSteamRightTouching
            )
            let updatedState = ControllerDisplayUpdatePolicy.resolve(
                current: currentState,
                sample: sample,
                deadzone: Config.displayUpdateDeadzone
            )
            if updatedState == currentState {
                PerformanceProbe.shared.recordDisplayNoOpTick()
                guard !Config.performanceForceLegacyDisplayPublishing else {
                    self.applyDisplayState(updatedState)
                    return
                }
                return
            }

            self.applyDisplayState(updatedState)
        }
        timer.resume()
        displayUpdateTimer = timer
        displayTimerSuspended = false
        observeWindowVisibility()
    }

    /// Observes all app window occlusion state changes to pause/resume the display
    /// timer when no window is visible. This avoids burning CPU on @Published
    /// updates and SwiftUI invalidation when the user has minimized/hidden the app.
    private func observeWindowVisibility() {
        removeWindowVisibilityObservers()

        let checkVisibility = { [weak self] in
            guard let self = self, let timer = self.displayUpdateTimer else { return }
            let anyVisible = NSApp.windows.contains {
                $0.isVisible && $0.occlusionState.contains(.visible)
                && $0.level == .normal  // Exclude overlay panels, popovers, floating indicators
            }
            if anyVisible && self.displayTimerSuspended {
                timer.resume()
                self.displayTimerSuspended = false
            } else if !anyVisible && !self.displayTimerSuspended {
                timer.suspend()
                self.displayTimerSuspended = true
            }
        }

        let names: [Notification.Name] = [
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.didChangeOcclusionStateNotification,
            NSApplication.didHideNotification,
            NSApplication.didUnhideNotification,
        ]
        for name in names {
            let token = NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { _ in checkVisibility() }
            windowVisibilityObservers.append(token)
        }
    }

    private func removeWindowVisibilityObservers() {
        for token in windowVisibilityObservers {
            NotificationCenter.default.removeObserver(token)
        }
        windowVisibilityObservers.removeAll()
    }

    private func applyDisplayState(_ state: ControllerDisplayState) {
        if Config.performanceForceLegacyDisplayPublishing {
            leftStick = state.leftStick
            rightStick = state.rightStick
            leftTriggerValue = state.leftTriggerValue
            rightTriggerValue = state.rightTriggerValue
            displayLeftStick = state.displayLeftStick
            displayRightStick = state.displayRightStick
            displayLeftTrigger = state.displayLeftTrigger
            displayRightTrigger = state.displayRightTrigger
            displayTouchpadPosition = state.displayTouchpadPosition
            displayTouchpadSecondaryPosition = state.displayTouchpadSecondaryPosition
            displayIsTouchpadTouching = state.displayIsTouchpadTouching
            displayIsTouchpadSecondaryTouching = state.displayIsTouchpadSecondaryTouching
            displaySteamLeftTouchpadPosition = state.displaySteamLeftTouchpadPosition
            displaySteamRightTouchpadPosition = state.displaySteamRightTouchpadPosition
            displayIsSteamLeftTouchpadTouching = state.displayIsSteamLeftTouchpadTouching
            displayIsSteamRightTouchpadTouching = state.displayIsSteamRightTouchpadTouching
            PerformanceProbe.shared.recordDisplayApply(fieldWrites: 16)
            return
        }

        var fieldWrites = 0
        if leftStick != state.leftStick {
            leftStick = state.leftStick
            fieldWrites += 1
        }
        if rightStick != state.rightStick {
            rightStick = state.rightStick
            fieldWrites += 1
        }
        if leftTriggerValue != state.leftTriggerValue {
            leftTriggerValue = state.leftTriggerValue
            fieldWrites += 1
        }
        if rightTriggerValue != state.rightTriggerValue {
            rightTriggerValue = state.rightTriggerValue
            fieldWrites += 1
        }
        if displayLeftStick != state.displayLeftStick {
            displayLeftStick = state.displayLeftStick
            fieldWrites += 1
        }
        if displayRightStick != state.displayRightStick {
            displayRightStick = state.displayRightStick
            fieldWrites += 1
        }
        if displayLeftTrigger != state.displayLeftTrigger {
            displayLeftTrigger = state.displayLeftTrigger
            fieldWrites += 1
        }
        if displayRightTrigger != state.displayRightTrigger {
            displayRightTrigger = state.displayRightTrigger
            fieldWrites += 1
        }
        if displayTouchpadPosition != state.displayTouchpadPosition {
            displayTouchpadPosition = state.displayTouchpadPosition
            fieldWrites += 1
        }
        if displayTouchpadSecondaryPosition != state.displayTouchpadSecondaryPosition {
            displayTouchpadSecondaryPosition = state.displayTouchpadSecondaryPosition
            fieldWrites += 1
        }
        if displayIsTouchpadTouching != state.displayIsTouchpadTouching {
            displayIsTouchpadTouching = state.displayIsTouchpadTouching
            fieldWrites += 1
        }
        if displayIsTouchpadSecondaryTouching != state.displayIsTouchpadSecondaryTouching {
            displayIsTouchpadSecondaryTouching = state.displayIsTouchpadSecondaryTouching
            fieldWrites += 1
        }
        if displaySteamLeftTouchpadPosition != state.displaySteamLeftTouchpadPosition {
            displaySteamLeftTouchpadPosition = state.displaySteamLeftTouchpadPosition
            fieldWrites += 1
        }
        if displaySteamRightTouchpadPosition != state.displaySteamRightTouchpadPosition {
            displaySteamRightTouchpadPosition = state.displaySteamRightTouchpadPosition
            fieldWrites += 1
        }
        if displayIsSteamLeftTouchpadTouching != state.displayIsSteamLeftTouchpadTouching {
            displayIsSteamLeftTouchpadTouching = state.displayIsSteamLeftTouchpadTouching
            fieldWrites += 1
        }
        if displayIsSteamRightTouchpadTouching != state.displayIsSteamRightTouchpadTouching {
            displayIsSteamRightTouchpadTouching = state.displayIsSteamRightTouchpadTouching
            fieldWrites += 1
        }

        if fieldWrites > 0 {
            PerformanceProbe.shared.recordDisplayApply(fieldWrites: fieldWrites)
        }
    }

    func stopDisplayUpdateTimer() {
        removeWindowVisibilityObservers()
        // DispatchSource must not be cancelled while suspended — resume first
        if displayTimerSuspended {
            displayUpdateTimer?.resume()
            displayTimerSuspended = false
        }
        displayUpdateTimer?.cancel()
        displayUpdateTimer = nil
        displayLeftStick = .zero
        displayRightStick = .zero
        displayLeftTrigger = 0
        displayRightTrigger = 0
        displayTouchpadPosition = .zero
        displayTouchpadSecondaryPosition = .zero
        displayIsTouchpadTouching = false
        displayIsTouchpadSecondaryTouching = false
        displaySteamLeftTouchpadPosition = .zero
        displaySteamRightTouchpadPosition = .zero
        displayIsSteamLeftTouchpadTouching = false
        displayIsSteamRightTouchpadTouching = false
    }
}
