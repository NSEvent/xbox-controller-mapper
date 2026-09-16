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
		shouldUseHoldPath(
			button: nil,
			mapping: mapping,
			isChordPart: isChordPart,
			isDPadPresetDirection: false
		)
	}

	static func shouldUseHoldPath(
		button: ControllerButton?,
		mapping: KeyMapping,
		isChordPart: Bool,
		isDPadPresetDirection: Bool
	) -> Bool {
		let isMouseClick = mapping.keyCode.map { KeyCodeMapping.isMouseButton($0) } ?? false
		let hasDoubleTap = mapping.doubleTapMapping.map { !$0.isEmpty } ?? false

		return mapping.isHoldModifier
			|| mapping.midiControlChange != nil
			|| shouldHoldDPadPresetDirection(button: button, mapping: mapping, isDPadPresetDirection: isDPadPresetDirection)
			|| (isMouseClick && !isChordPart && !hasDoubleTap)
	}

	private static func shouldHoldDPadPresetDirection(
		button: ControllerButton?,
		mapping: KeyMapping,
		isDPadPresetDirection: Bool
	) -> Bool {
		// An explicitly enabled repeat-while-held opts the direction out of
		// the preset hold path — otherwise the user's repeat config would be
		// silently bypassed (Discord #support 2026-07-30).
		guard isDPadPresetDirection,
			  let button,
			  DPadPreset.buttons.contains(button),
			  mapping.effectiveActionType == .keyPress,
			  mapping.keyCode != nil,
			  !mapping.modifiers.hasAny,
			  !(mapping.repeatMapping?.enabled ?? false),
			  mapping.longHoldMapping?.isEmpty ?? true,
			  mapping.doubleTapMapping?.isEmpty ?? true else {
			return false
		}

		return true
	}

	static func shouldUseRealtimeHoldPath(
		mapping: KeyMapping,
		isChordPart: Bool,
		isOtherLayerActivatorPress: Bool = false
	) -> Bool {
		// When a different layer is active, its remap of another layer's
		// activator should keep tap semantics instead of becoming a held key.
		// Track-skip/play-pause keys are also tap-semantic: holding the NX
		// event for the whole physical press makes Next/Previous scrub
		// instead of skip, so they take the tap path exactly like standard
		// (non-realtime) mode. Fast Forward/Rewind and volume/brightness
		// stay hold-eligible (hold-to-seek and step-at-press).
		guard !isChordPart,
			  !isOtherLayerActivatorPress,
			  mapping.effectiveActionType == .keyPress,
			  let keyCode = mapping.keyCode,
			  !KeyCodeMapping.isTapOnlyMediaKey(keyCode),
			  mapping.longHoldMapping?.isEmpty ?? true,
			  mapping.doubleTapMapping?.isEmpty ?? true,
			  !(mapping.repeatMapping?.enabled ?? false) else {
			return false
		}
		return true
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
