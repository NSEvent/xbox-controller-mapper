import Foundation

/// Visitor over the code-execution surface of a `Profile`. Used by
/// `ProfileImportSafetyAuditor` (and future visitors that need to inspect
/// every place a profile can run code on the user's machine).
///
/// The data types own the walk via `walkSurface` / `accept` extensions
/// below. Each leaf-level executable surface — a SystemCommand, a Macro, a
/// Script, an OSK QuickText — gets its own `visit` method so a new visitor
/// can opt into exactly the surfaces it cares about. Equally important: a
/// data-model change that adds a new field with executable content has one
/// natural place to extend the walk (the `accept` on the containing type),
/// and every existing visitor automatically inherits the new call.
///
/// This replaces a hand-rolled walk that four separate review passes each
/// found a bypass in (a missed surface that let a malicious profile hide
/// shell payloads past the safety warning sheet).
protocol ProfileSurfaceVisitor {
    mutating func visit(systemCommand: SystemCommand, context: String)
    mutating func visit(macroStep: MacroStep, context: String)
    mutating func visit(script: Script)
    mutating func visit(quickText: QuickText)
}

// MARK: - Profile

extension Profile {
    /// Walks every executable surface in this profile, dispatching to the
    /// visitor for each leaf. Adding a new surface means extending this
    /// method (or the relevant `accept` on a nested type) — and every
    /// visitor that conforms to `ProfileSurfaceVisitor` automatically gets
    /// the new call.
    func walkSurface<V: ProfileSurfaceVisitor>(_ visitor: inout V) {
        // Primary button mappings (each KeyMapping owns its own primary +
        // long-hold + double-tap walk via accept(_:context:)).
        for (button, mapping) in buttonMappings {
            mapping.accept(&visitor, context: "Button \(button.shortLabel)")
        }

        for chord in chordMappings {
            if let command = chord.systemCommand {
                visitor.visit(systemCommand: command,
                              context: "Chord \(chord.buttonsDisplayString)")
            }
        }

        for sequence in sequenceMappings {
            if let command = sequence.systemCommand {
                visitor.visit(systemCommand: command,
                              context: "Sequence \(sequence.stepsDisplayString)")
            }
        }

        for gesture in gestureMappings {
            if let command = gesture.systemCommand {
                visitor.visit(systemCommand: command,
                              context: "Gesture: \(gesture.gestureType.displayName)")
            }
        }

        for action in commandWheelActions {
            let label = action.displayName.isEmpty ? "(unnamed)" : action.displayName
            if let command = action.systemCommand {
                visitor.visit(systemCommand: command,
                              context: "Command Wheel: \(label)")
            }
        }

        // Layers reuse `KeyMapping.accept`. This is the structural fix for
        // the pass-4 bypass: a Layer can no longer forget to walk long-hold
        // / double-tap variants, because that walk lives on KeyMapping.
        for layer in layers {
            let layerName = layer.name.isEmpty ? "(unnamed)" : layer.name
            for (button, mapping) in layer.buttonMappings {
                mapping.accept(&visitor,
                               context: "Layer '\(layerName)' Button \(button.shortLabel)")
            }
        }

        // Macros: visit each step individually so the auditor can switch
        // exhaustively over MacroStep cases. The previous design passed the
        // whole Macro and let the visitor walk steps internally, which left
        // the inner pattern non-exhaustive — exactly the recurring-bypass
        // shape the refactor is trying to prevent.
        for macro in macros {
            let macroName = macro.name.isEmpty ? "(unnamed)" : macro.name
            for (idx, step) in macro.steps.enumerated() {
                visitor.visit(macroStep: step,
                              context: "Macro '\(macroName)' step \(idx + 1)")
            }
        }

        for script in scripts {
            visitor.visit(script: script)
        }

        // Legacy v1 touchpad-region mappings (drained at load via
        // ProfileConfigurationMigrationService, but a freshly imported
        // profile can still carry them prior to migration).
        for region in touchpadRegionMappings {
            if let command = region.systemCommand {
                visitor.visit(systemCommand: command,
                              context: "Touchpad region \(region.region.rawValue) (\(region.triggerMode.rawValue))")
            }
        }

        // On-screen-keyboard quick texts. Terminal items run shell payloads
        // through Terminal — same execution surface as a .shellCommand
        // binding, just reached via the OSK.
        for quickText in onScreenKeyboardSettings.quickTexts {
            visitor.visit(quickText: quickText)
        }
    }
}

// MARK: - KeyMapping

extension KeyMapping {
    /// Single source of truth for walking a KeyMapping's executable surface:
    /// the primary `systemCommand` plus the optional long-hold and double-tap
    /// variants. Both base profile mappings and Layer mappings call this, so
    /// the variants can never silently fall out of audit coverage.
    func accept<V: ProfileSurfaceVisitor>(_ visitor: inout V, context: String) {
        if let command = systemCommand {
            visitor.visit(systemCommand: command, context: context)
        }
        if let longHold = longHoldMapping?.systemCommand {
            visitor.visit(systemCommand: longHold, context: "\(context) (long hold)")
        }
        if let doubleTap = doubleTapMapping?.systemCommand {
            visitor.visit(systemCommand: doubleTap, context: "\(context) (double tap)")
        }
    }
}
