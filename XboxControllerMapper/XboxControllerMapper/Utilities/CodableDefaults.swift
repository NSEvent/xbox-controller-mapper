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
}
