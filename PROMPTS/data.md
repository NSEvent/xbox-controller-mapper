# Data Model Patterns

Constraints for the configuration schema and Codable conventions.

---

## All structs use custom decoders with `decodeIfPresent`

Every Codable struct in the config schema uses a custom `init(from decoder:)` that decodes each field with `decodeIfPresent` and a sensible default. This ensures any missing key in JSON falls back gracefully instead of throwing a decoding error.

```swift
// GOOD: every field uses decodeIfPresent
init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    sensitivity = try container.decodeIfPresent(Double.self, forKey: .sensitivity) ?? 0.5
    enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    name = try container.decodeIfPresent(String.self, forKey: .name)  // optional, auto nil
}

// BAD: strict decode that crashes on missing keys
init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    sensitivity = try container.decode(Double.self, forKey: .sensitivity)  // throws if missing
}
```

**The only exception:** `Profile.id` uses strict `decode()` because a profile without an ID is truly invalid.

**Why this matters:** Users have config files from every version of the app. A strict decoder would crash on old configs missing new fields. The `decodeIfPresent` pattern makes every schema change backwards compatible by construction.

**Why tests can't fully catch this:** Tests can verify that decoding a specific JSON blob succeeds, but they can't verify the *absence* of a strict `decode()` call in future code. The constraint is structural: "never use strict decode for new fields."

---

## ProfileManager safety: never overwrite on load failure

`ProfileManager` tracks a `loadSucceeded` flag. If loading the config file fails, the flag is `false` and `save()` becomes a no-op. This prevents a schema error from overwriting the user's config with empty/default data.

**Why tests can't catch this:** The invariant is about the relationship between two operations across time (load failure → save suppression). You can test the individual operations, but the constraint "never overwrite a file you failed to read" is an architectural rule.

---

## Config file location and migration

Config lives at `~/.controllerkeys/config.json`. Legacy path `~/.xbox-controller-mapper/config.json` is auto-migrated on first launch. Backups are kept at `~/.controllerkeys/backups/` (last 5).

The config is pretty-printed JSON with ISO8601 dates.

---

## Adding new fields is always safe

Because all structs use custom decoders, adding a new field to any config struct requires:

1. Add the property with a default value
2. Add to `CodingKeys` enum
3. Add `decodeIfPresent` line in `init(from decoder:)` with the same default
4. If the struct has a custom `encode(to:)` (only `Profile` does), add there too

No migration code. No version bumps. The default value handles old configs automatically.
