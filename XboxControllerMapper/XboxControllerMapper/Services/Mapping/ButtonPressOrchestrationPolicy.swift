import Foundation

/// Decides button-press interception and mapping context for `MappingEngine`.
enum ButtonPressOrchestrationPolicy {
    struct MappingContext: Equatable {
        let mapping: KeyMapping
        let lastTap: Date?
        let shouldTreatAsHold: Bool
    }

    enum Outcome: Equatable {
        case interceptDpadNavigation
        case interceptKeyboardActivation
        case interceptOnScreenKeyboard(holdMode: Bool)
        case interceptLaserPointer(holdMode: Bool)
        case interceptControllerLock
        case interceptSwipePredictionNavigation
        case interceptSwipePredictionConfirm
        case interceptSwipePredictionCancel
        case unmapped
        case mapping(MappingContext)
    }

    static func resolve(
        button: ControllerButton,
        mapping: KeyMapping?,
        keyboardVisible: Bool,
        navigationModeActive: Bool,
        isChordPart: Bool,
        lastTap: Date?
    ) -> Outcome {
        // Swipe typing interceptions based on current swipe state
        if keyboardVisible {
            let swipeState = SwipeTypingEngine.shared.threadSafeState
            if swipeState == .showingPredictions {
                switch button {
                case .dpadLeft, .dpadRight:
                    return .interceptSwipePredictionNavigation
                case .a:
                    return .interceptSwipePredictionConfirm
                case .b:
                    return .interceptSwipePredictionCancel
                default:
                    break
                }
            } else if swipeState == .active || swipeState == .swiping {
                // B cancels swipe mode during active/swiping
                if button == .b {
                    return .interceptSwipePredictionCancel
                }
            }
        }

        if keyboardVisible {
            switch button {
            case .dpadUp, .dpadDown, .dpadLeft, .dpadRight:
                return .interceptDpadNavigation
            default:
                break
            }
        }

        guard let mapping else {
            return .unmapped
        }

        if keyboardVisible,
           navigationModeActive,
           let keyCode = mapping.keyCode,
           keyCode == KeyCodeMapping.mouseLeftClick {
            return .interceptKeyboardActivation
        }

        if mapping.keyCode == KeyCodeMapping.showOnScreenKeyboard {
            return .interceptOnScreenKeyboard(holdMode: mapping.isHoldModifier)
        }

        if mapping.keyCode == KeyCodeMapping.showLaserPointer {
            return .interceptLaserPointer(holdMode: mapping.isHoldModifier)
        }

        if mapping.keyCode == KeyCodeMapping.controllerLock {
            return .interceptControllerLock
        }

        return .mapping(
            MappingContext(
                mapping: mapping,
                lastTap: lastTap,
                shouldTreatAsHold: ButtonInteractionFlowPolicy.shouldUseHoldPath(
                    mapping: mapping,
                    isChordPart: isChordPart
                )
            )
        )
    }
}
