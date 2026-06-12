import Foundation
import TriggerKitCore
import TriggerKitLibrary

/// Maintains `Profile.sharedMacroSnapshots` — the embedded copies of shared
/// TriggerKit library macros that a profile's bindings reference.
///
/// Snapshots serve two purposes:
/// - **Deletion fallback:** if a library macro is deleted, bindings keep
///   running the last snapshot (the TriggerKit consumer contract).
/// - **Portability:** an exported/community profile carries the programs its
///   bindings need, so it works on machines without the library macro.
///
/// Sync runs on profile save (`ProfileManager.updateProfile`): live library
/// macros refresh their snapshot, deleted macros keep the existing snapshot,
/// and snapshots no longer referenced by any binding are dropped.
enum SharedMacroSnapshotPolicy {

    /// Macro IDs referenced by any binding surface that are *not* profile
    /// macros — i.e. references into the shared TriggerKit library.
    static func referencedSharedMacroIds(in profile: Profile) -> Set<UUID> {
        var collector = MacroReferenceCollector()
        profile.walkSurface(&collector)
        return collector.macroIds.subtracting(Set(profile.macros.map(\.id)))
    }

    /// The synced snapshot map for `profile`.
    static func syncedSnapshots(
        for profile: Profile,
        store: AutomationMacroStore
    ) -> [UUID: AutomationProgram] {
        var synced: [UUID: AutomationProgram] = [:]
        for id in referencedSharedMacroIds(in: profile) {
            if let macro = store.macro(id: id) {
                // An intentionally-empty library macro snapshots as empty:
                // "macro exists but has no steps" means do nothing, and the
                // snapshot must preserve that choice.
                synced[id] = macro.program.normalized(fallbackName: macro.name)
            } else if let existing = profile.sharedMacroSnapshots[id] {
                synced[id] = existing
            }
        }
        return synced
    }

    /// Collects every `macroId` reachable from the profile's binding surfaces
    /// via `ProfileSurfaceVisitor`, so new surfaces added to the walk are
    /// covered here automatically.
    private struct MacroReferenceCollector: ProfileSurfaceVisitor {
        var macroIds: Set<UUID> = []

        mutating func visit(action: any ExecutableAction, context: String) {
            if let macroId = action.macroId {
                macroIds.insert(macroId)
            }
        }

        mutating func visit(systemCommand: SystemCommand, context: String) {}
        mutating func visit(macroStep: MacroStep, context: String) {}
        mutating func visit(script: Script) {}
        mutating func visit(quickText: QuickText) {}
        mutating func visit(automationStep: AutomationStep, context: String) {}
    }
}
