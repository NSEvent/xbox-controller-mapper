import XCTest
@testable import ControllerKeys

// =============================================================================
// Cache Locality Benchmark Results (2026-04-21, Apple M2 Ultra, Release build)
//
// Precomputed Lookups (160k calls per measure block):
//   isButtonUsedInChords  — OLD 0.160s → NEW 0.016s  (10.0x faster)
//   isButtonUsedInSequences — OLD 0.338s → NEW 0.015s  (22.5x faster)
//   Chord matching        — OLD 0.086s → NEW 0.025s  ( 3.4x faster)
//
// Controller Snapshot (100k reads per measure block):
//   5 individual locks    — 0.017s
//   1 snapshot lock       — 0.013s  (1.31x faster / 31% fewer lock cycles)
//
// UI State Snapshots (100k reads per measure block):
//   Keyboard 2 reads → 1  — OLD 0.016s → NEW 0.013s  (1.23x faster)
//   Swipe    2 reads → 1  — OLD 0.016s → NEW 0.012s  (1.33x faster)
//
// Letter Area Cache (100k reads per measure block):
//   Uncached (recompute)  — 0.019s
//   Cached (dirty flag)   — 0.012s  (1.58x faster)
//
// SequenceDetector in-place rewrite was benchmarked and REVERTED — Swift's COW
// array semantics made the old allocating approach 1.9x faster than the in-place
// write-index compaction for typical small active-sequence counts (<5).
// =============================================================================

// MARK: - Benchmark: Precomputed Lookups

/// Compares the old linear-scan approach vs the new precomputed Set/Dictionary lookups
/// for chord and sequence membership tests and chord matching.
final class PrecomputedLookupBenchmarkTests: XCTestCase {

    // Realistic test data: 8 chords, 10 sequences, simulating a well-configured profile
    static let allButtons: [ControllerButton] = [.a, .b, .x, .y, .leftBumper, .rightBumper, .dpadUp, .dpadDown, .dpadLeft, .dpadRight, .leftTrigger, .rightTrigger, .menu, .view, .leftThumbstick, .rightThumbstick]

    static let testChords: [ChordMapping] = [
        ChordMapping(buttons: [.a, .b], keyCode: 0),
        ChordMapping(buttons: [.x, .y], keyCode: 1),
        ChordMapping(buttons: [.leftBumper, .rightBumper], keyCode: 2),
        ChordMapping(buttons: [.a, .leftBumper], keyCode: 3),
        ChordMapping(buttons: [.b, .rightBumper], keyCode: 4),
        ChordMapping(buttons: [.dpadUp, .dpadDown], keyCode: 5),
        ChordMapping(buttons: [.a, .b, .x], keyCode: 6),
        ChordMapping(buttons: [.leftBumper, .rightBumper, .a], keyCode: 7),
    ]

    static let testSequences: [SequenceMapping] = [
        SequenceMapping(steps: [.dpadDown, .dpadDown, .a], stepTimeout: 0.4, keyCode: 10),
        SequenceMapping(steps: [.dpadUp, .dpadUp, .b], stepTimeout: 0.4, keyCode: 11),
        SequenceMapping(steps: [.a, .b, .x], stepTimeout: 0.4, keyCode: 12),
        SequenceMapping(steps: [.leftBumper, .a], stepTimeout: 0.4, keyCode: 13),
        SequenceMapping(steps: [.rightBumper, .b], stepTimeout: 0.4, keyCode: 14),
        SequenceMapping(steps: [.x, .y, .a, .b], stepTimeout: 0.4, keyCode: 15),
        SequenceMapping(steps: [.dpadLeft, .dpadRight, .a], stepTimeout: 0.4, keyCode: 16),
        SequenceMapping(steps: [.dpadRight, .dpadLeft, .b], stepTimeout: 0.4, keyCode: 17),
        SequenceMapping(steps: [.a, .a, .a], stepTimeout: 0.4, keyCode: 18),
        SequenceMapping(steps: [.b, .b], stepTimeout: 0.4, keyCode: 19),
    ]

    // Precomputed caches (the "new" approach)
    static let chordParticipantButtons: Set<ControllerButton> = Set(testChords.flatMap { $0.buttons })
    static let sequenceParticipantButtons: Set<ControllerButton> = Set(testSequences.flatMap { $0.steps })
    static let chordLookup: [Set<ControllerButton>: ChordMapping] = Dictionary(uniqueKeysWithValues: testChords.map { ($0.buttons, $0) })

    // --- isButtonUsedInChords ---

    func testBenchmark_isButtonUsedInChords_OLD_linearScan() {
        let chords = Self.testChords
        let buttons = Self.allButtons
        measure {
            for _ in 0..<10_000 {
                for button in buttons {
                    _ = chords.contains { chord in
                        chord.buttons.contains(button)
                    }
                }
            }
        }
    }

    func testBenchmark_isButtonUsedInChords_NEW_precomputedSet() {
        let cache = Self.chordParticipantButtons
        let buttons = Self.allButtons
        measure {
            for _ in 0..<10_000 {
                for button in buttons {
                    _ = cache.contains(button)
                }
            }
        }
    }

    // --- isButtonUsedInSequences ---

    func testBenchmark_isButtonUsedInSequences_OLD_linearScan() {
        let sequences = Self.testSequences
        let buttons = Self.allButtons
        measure {
            for _ in 0..<10_000 {
                for button in buttons {
                    _ = sequences.contains { seq in
                        seq.steps.contains(button)
                    }
                }
            }
        }
    }

    func testBenchmark_isButtonUsedInSequences_NEW_precomputedSet() {
        let cache = Self.sequenceParticipantButtons
        let buttons = Self.allButtons
        measure {
            for _ in 0..<10_000 {
                for button in buttons {
                    _ = cache.contains(button)
                }
            }
        }
    }

    // --- Chord matching ---

    func testBenchmark_chordMatching_OLD_linearScanWithSetEquality() {
        let chords = Self.testChords
        // Test with a mix of matching and non-matching button sets
        let queries: [Set<ControllerButton>] = [
            [.a, .b],           // match
            [.x, .y],           // match
            [.a, .x],           // no match
            [.leftBumper, .rightBumper, .a],  // match
            [.dpadUp, .dpadLeft],  // no match
            [.a, .b, .x],      // match
            [.menu, .view],     // no match
            [.b, .rightBumper], // match
        ]
        measure {
            for _ in 0..<10_000 {
                for query in queries {
                    _ = chords.first { chord in
                        chord.buttons == query
                    }
                }
            }
        }
    }

    func testBenchmark_chordMatching_NEW_dictionaryLookup() {
        let lookup = Self.chordLookup
        let queries: [Set<ControllerButton>] = [
            [.a, .b],
            [.x, .y],
            [.a, .x],
            [.leftBumper, .rightBumper, .a],
            [.dpadUp, .dpadLeft],
            [.a, .b, .x],
            [.menu, .view],
            [.b, .rightBumper],
        ]
        measure {
            for _ in 0..<10_000 {
                for query in queries {
                    _ = lookup[query]
                }
            }
        }
    }
}

// MARK: - Benchmark: Controller Snapshot (Agent C)

/// Compares multiple individual lock acquisitions vs a single snapshot read.
final class ControllerSnapshotBenchmarkTests: XCTestCase {

    func testBenchmark_controllerRead_OLD_individualLocks() {
        let storage = ControllerStorage()
        // Simulate realistic values
        storage.leftStick = CGPoint(x: 0.5, y: -0.3)
        storage.rightStick = CGPoint(x: -0.1, y: 0.8)
        storage.leftTrigger = 0.7
        storage.rightTrigger = 0.2
        storage.isDualSense = true

        measure {
            for _ in 0..<100_000 {
                // Old pattern: 5 separate lock/unlock cycles
                storage.lock.lock()
                let ls = storage.leftStick
                storage.lock.unlock()

                storage.lock.lock()
                let rs = storage.rightStick
                storage.lock.unlock()

                storage.lock.lock()
                let lt = storage.leftTrigger
                storage.lock.unlock()

                storage.lock.lock()
                let rt = storage.rightTrigger
                storage.lock.unlock()

                storage.lock.lock()
                let ds = storage.isDualSense
                storage.lock.unlock()

                // Prevent optimizer from removing the reads
                _ = (ls, rs, lt, rt, ds)
            }
        }
    }

    func testBenchmark_controllerRead_NEW_singleSnapshot() {
        let storage = ControllerStorage()
        storage.leftStick = CGPoint(x: 0.5, y: -0.3)
        storage.rightStick = CGPoint(x: -0.1, y: 0.8)
        storage.leftTrigger = 0.7
        storage.rightTrigger = 0.2
        storage.isDualSense = true

        measure {
            for _ in 0..<100_000 {
                // New pattern: 1 lock/unlock, read everything at once
                storage.lock.lock()
                let snapshot = (
                    leftStick: storage.leftStick,
                    rightStick: storage.rightStick,
                    leftTrigger: storage.leftTrigger,
                    rightTrigger: storage.rightTrigger,
                    isDualSense: storage.isDualSense
                )
                storage.lock.unlock()

                _ = snapshot
            }
        }
    }
}
