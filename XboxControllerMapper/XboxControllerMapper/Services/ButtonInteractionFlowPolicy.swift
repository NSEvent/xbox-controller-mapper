import Foundation

/// Encapsulates button press/release flow decisions used by `MappingEngine`.
enum ButtonInteractionFlowPolicy {
    enum ReleaseDecision: Equatable {
        case skip
        case executeLongHold(LongHoldMapping)
        case evaluateDoubleTap(DoubleTapMapping, skipSingleTapFallback: Bool)
        case executeSingleTap
    }

    static func shouldUseHoldPath(mapping: KeyMapping, isChordPart: Bool) -> Bool {
        let isMouseClick = mapping.keyCode.map { KeyCodeMapping.isMouseButton($0) } ?? false
        let hasDoubleTap = mapping.doubleTapMapping.map { !$0.isEmpty } ?? false

        return mapping.isHoldModifier || (isMouseClick && !isChordPart && !hasDoubleTap)
    }

    static func releaseDecision(
        mapping: KeyMapping,
        holdDuration: TimeInterval,
        isLongHoldTriggered: Bool
    ) -> ReleaseDecision {
        let isRepeatMapping = mapping.repeatMapping?.enabled ?? false
        let hasDoubleTap = mapping.doubleTapMapping.map { !$0.isEmpty } ?? false

        if mapping.isHoldModifier || isRepeatMapping || isLongHoldTriggered {
            if isRepeatMapping, hasDoubleTap, let doubleTapMapping = mapping.doubleTapMapping {
                return .evaluateDoubleTap(doubleTapMapping, skipSingleTapFallback: true)
            }
            return .skip
        }

        if let longHoldMapping = mapping.longHoldMapping,
           holdDuration >= longHoldMapping.threshold,
           !longHoldMapping.isEmpty {
            return .executeLongHold(longHoldMapping)
        }

        if hasDoubleTap, let doubleTapMapping = mapping.doubleTapMapping {
            return .evaluateDoubleTap(doubleTapMapping, skipSingleTapFallback: false)
        }

        return .executeSingleTap
    }
}
