import Foundation

extension KeyedDecodingContainer {
    /// Decode `key`, returning `fallback` when the key is missing or null.
    /// Collapses the `decodeIfPresent(_:forKey:) ?? fallback` pattern used
    /// throughout the model layer for forward/backward-compatible configs.
    func decode<T: Decodable>(_ key: Key, default fallback: T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? fallback
    }

    /// Decode a floating-point field with `fallback` for missing/null values,
    /// then clamp into `range`. Non-finite decoded values also fall back.
    func decode<T: Decodable & FloatingPoint>(
        _ key: Key,
        default fallback: T,
        clampedTo range: ClosedRange<T>
    ) throws -> T {
        let raw = try decodeIfPresent(T.self, forKey: key) ?? fallback
        guard raw.isFinite else { return fallback }
        return min(range.upperBound, max(range.lowerBound, raw))
    }

    /// Decode a `RawRepresentable` enum, mapping a missing key OR an unrecognized
    /// raw value to `fallback`. Unlike plain `decode(_:default:)`, this does not
    /// throw when a newer build wrote an enum case this build doesn't know about,
    /// which keeps configs downgrade-safe (the schema contract: unknown values
    /// degrade gracefully, they never break loading).
    func decodeLenient<T>(_ key: Key, default fallback: T) throws -> T
        where T: RawRepresentable, T.RawValue: Decodable {
        guard let rawValue = try decodeIfPresent(T.RawValue.self, forKey: key) else { return fallback }
        return T(rawValue: rawValue) ?? fallback
    }

    /// Optional variant: a missing key or an unrecognized raw value both decode
    /// to `nil` (e.g. a layer stick-mode override falling back to "inherit").
    func decodeLenient<T>(_ key: Key) throws -> T?
        where T: RawRepresentable, T.RawValue: Decodable {
        guard let rawValue = try decodeIfPresent(T.RawValue.self, forKey: key) else { return nil }
        return T(rawValue: rawValue)
    }
}

/// Wraps a `Decodable` so a value that fails to decode (e.g. a forward-versioned
/// payload from a newer build) becomes `nil` instead of throwing out of the
/// surrounding container. Decode a `[Key: LossyDecoded<T>]` to drop only the
/// undecodable entries rather than losing the whole dictionary — and, with it,
/// every sibling that decoded fine.
struct LossyDecoded<Wrapped: Decodable>: Decodable {
    let value: Wrapped?

    init(from decoder: Decoder) throws {
        value = try? Wrapped(from: decoder)
    }
}
