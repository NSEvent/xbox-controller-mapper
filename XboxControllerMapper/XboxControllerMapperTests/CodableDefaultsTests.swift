import XCTest
@testable import ControllerKeys

/// Direct unit tests for the `KeyedDecodingContainer.decode(_:default:)` and
/// clamping overload in `Utilities/CodableDefaults.swift`. The model decoders
/// across the project depend on these helpers' fallback semantics — covering
/// them here in isolation lets a regression surface as one focused failure
/// instead of cascading into 29 model decoder tests.
final class CodableDefaultsTests: XCTestCase {

    // MARK: - Test fixture

    /// A minimal struct that exercises both helper overloads. Each field
    /// exercises one fallback path the helpers must support.
    private struct Sample: Decodable {
        let name: String
        let count: Int
        let speed: Double          // clamped to 0.0...1.0
        let optional: String?

        enum CodingKeys: String, CodingKey {
            case name, count, speed, optional
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(.name, default: "default-name")
            count = try c.decode(.count, default: 7)
            speed = try c.decode(.speed, default: 0.5, clampedTo: 0.0...1.0)
            optional = try c.decodeIfPresent(String.self, forKey: .optional)
        }
    }

    private func decode(_ json: String) throws -> Sample {
        try JSONDecoder().decode(Sample.self, from: Data(json.utf8))
    }

    // MARK: - Basic decode(_:default:)

    func testFallbackUsedWhenKeyIsMissing() throws {
        let s = try decode("{}")
        XCTAssertEqual(s.name, "default-name")
        XCTAssertEqual(s.count, 7)
    }

    func testFallbackUsedWhenKeyIsExplicitlyNull() throws {
        let s = try decode(#"{"name": null, "count": null}"#)
        XCTAssertEqual(s.name, "default-name")
        XCTAssertEqual(s.count, 7)
    }

    func testPresentValueWins() throws {
        let s = try decode(#"{"name": "Kevin", "count": 42}"#)
        XCTAssertEqual(s.name, "Kevin")
        XCTAssertEqual(s.count, 42)
    }

    func testWrongTypeStillThrows() {
        // The helper preserves Codable's normal error behavior on type
        // mismatch — callers shouldn't get silent default-substitution for
        // typo'd or corrupted values.
        XCTAssertThrowsError(try decode(#"{"count": "not-a-number"}"#))
    }

    // MARK: - decode(_:default:clampedTo:)

    func testClampingFallbackUsedWhenKeyMissing() throws {
        let s = try decode("{}")
        XCTAssertEqual(s.speed, 0.5, accuracy: 1e-10)
    }

    func testClampingPassesValuesInRange() throws {
        let s = try decode(#"{"speed": 0.42}"#)
        XCTAssertEqual(s.speed, 0.42, accuracy: 1e-10)
    }

    func testClampingPullsValuesAboveRangeDown() throws {
        let s = try decode(#"{"speed": 9.5}"#)
        XCTAssertEqual(s.speed, 1.0, accuracy: 1e-10)
    }

    func testClampingPullsValuesBelowRangeUp() throws {
        let s = try decode(#"{"speed": -3.0}"#)
        XCTAssertEqual(s.speed, 0.0, accuracy: 1e-10)
    }

    func testClampingExactBoundsArePreserved() throws {
        let lower = try decode(#"{"speed": 0.0}"#)
        XCTAssertEqual(lower.speed, 0.0, accuracy: 1e-10)
        let upper = try decode(#"{"speed": 1.0}"#)
        XCTAssertEqual(upper.speed, 1.0, accuracy: 1e-10)
    }

    func testClampingFallsBackOnNonFiniteValues() throws {
        // NaN and Infinity bypass the clamp and use the fallback. Without this
        // a corrupted/malicious config could poison downstream math.
        struct Container: Decodable {
            let value: Double
            enum CodingKeys: String, CodingKey { case value }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                value = try c.decode(.value, default: 0.5, clampedTo: 0.0...1.0)
            }
        }
        // JSON spec doesn't allow NaN/Inf as bare literals — synthesize via a
        // single-value container fed an explicit Double to exercise the guard.
        let nanResult = try decodeContainer(value: .nan)
        XCTAssertEqual(nanResult, 0.5, accuracy: 1e-10)

        let posInf = try decodeContainer(value: .infinity)
        XCTAssertEqual(posInf, 0.5, accuracy: 1e-10)

        let negInf = try decodeContainer(value: -.infinity)
        XCTAssertEqual(negInf, 0.5, accuracy: 1e-10)
    }

    // MARK: - Type inference (compile-time / smoke)

    func testInferenceWorksFromContextWithoutExplicitTypeArg() throws {
        // If this file compiles, type inference is intact. The body of
        // Sample.init exercises String, Int, and Double inference from
        // context — regressing the generic signature would break that
        // before this test ever ran.
        let s = try decode("{}")
        XCTAssertNotNil(s)
    }

    // MARK: - Helpers

    /// Exercises the clamping helper on a non-finite Double by routing it
    /// through a custom Decoder (JSON can't represent NaN/Inf as literals).
    private func decodeContainer(value: Double) throws -> Double {
        struct Container: Decodable {
            let value: Double
            enum CodingKeys: String, CodingKey { case value }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                value = try c.decode(.value, default: 0.5, clampedTo: 0.0...1.0)
            }
        }
        let decoder = NonFiniteDoubleDecoder(value: value)
        return try Container(from: decoder).value
    }
}

// MARK: - Custom Decoder for non-finite Doubles

/// Minimal Decoder that returns the supplied Double when asked for the `value`
/// key. Used to feed NaN/Infinity into the clamping helper, which JSON literals
/// can't express.
private struct NonFiniteDoubleDecoder: Decoder {
    let value: Double
    var codingPath: [CodingKey] = []
    var userInfo: [CodingUserInfoKey: Any] = [:]

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        KeyedDecodingContainer(Container<Key>(value: value))
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        fatalError("unused")
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        fatalError("unused")
    }

    private struct Container<K: CodingKey>: KeyedDecodingContainerProtocol {
        typealias Key = K
        let value: Double
        var codingPath: [CodingKey] = []
        var allKeys: [K] { [] }

        func contains(_ key: K) -> Bool { key.stringValue == "value" }
        func decodeNil(forKey key: K) throws -> Bool { false }

        func decode<T: Decodable>(_ type: T.Type, forKey key: K) throws -> T {
            guard let typed = value as? T else {
                throw DecodingError.typeMismatch(T.self, .init(codingPath: [], debugDescription: ""))
            }
            return typed
        }

        func decodeIfPresent<T: Decodable>(_ type: T.Type, forKey key: K) throws -> T? {
            guard key.stringValue == "value", let typed = value as? T else { return nil }
            return typed
        }

        func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: K) throws -> KeyedDecodingContainer<NestedKey> {
            fatalError("unused")
        }
        func nestedUnkeyedContainer(forKey key: K) throws -> UnkeyedDecodingContainer {
            fatalError("unused")
        }
        func superDecoder() throws -> Decoder { fatalError("unused") }
        func superDecoder(forKey key: K) throws -> Decoder { fatalError("unused") }
    }
}
