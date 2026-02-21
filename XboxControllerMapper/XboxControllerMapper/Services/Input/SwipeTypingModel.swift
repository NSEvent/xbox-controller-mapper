import Foundation
import CoreML

// MARK: - Data Types

struct SwipeSample {
    let x: Double   // normalized 0-1
    let y: Double   // normalized 0-1
    let dt: Double   // time delta since last sample in seconds
}

struct SwipeTypingPrediction {
    let word: String
    let confidence: Double
}

// MARK: - Constants (must match Python training code)

private let MAX_STROKE_LEN = 80
private let MAX_WORD_LEN = 20
private let VOCAB_SIZE = 29     // PAD(0) + A-Z(1-26) + SOS(27) + EOS(28)
private let PAD_TOKEN: Int32 = 0
private let SOS_TOKEN: Int32 = 27
private let EOS_TOKEN: Int32 = 28
private let TARGET_LEN = MAX_WORD_LEN + 2  // 22

// MARK: - SwipeTypingModel

/// Wraps a Core ML seq2seq model for swipe typing inference.
/// Performs autoregressive greedy/beam decoding to produce word predictions.
class SwipeTypingModel {
    private var model: MLModel?
    private let lock = NSLock()
    private var dictionary: Set<String> = []

    var isLoaded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return model != nil
    }

    /// Loads the Core ML model and dictionary from the app bundle on a background thread.
    func loadModel() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Load dictionary
            if let vocabURL = Bundle.main.url(forResource: "swipe_vocab", withExtension: "txt"),
               let vocabText = try? String(contentsOf: vocabURL, encoding: .utf8) {
                let words = Set(vocabText.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                    .filter { !$0.isEmpty })
                self.lock.lock()
                self.dictionary = words
                self.lock.unlock()
                NSLog("[SwipeTypingModel] Dictionary loaded: %d words", words.count)
            }

            // Try .mlmodelc (compiled) first, then .mlpackage
            let modelURL: URL? = Bundle.main.url(forResource: "SwipeTyping", withExtension: "mlmodelc")
                ?? Bundle.main.url(forResource: "SwipeTyping", withExtension: "mlpackage")

            guard let url = modelURL else {
                NSLog("[SwipeTypingModel] Model not found in bundle — running in stub mode")
                return
            }

            do {
                let config = MLModelConfiguration()
                config.computeUnits = .cpuAndGPU
                let loadedModel = try MLModel(contentsOf: url, configuration: config)
                self.lock.lock()
                self.model = loadedModel
                self.lock.unlock()
                NSLog("[SwipeTypingModel] Model loaded successfully from %@", url.lastPathComponent)
            } catch {
                NSLog("[SwipeTypingModel] Failed to load model: %@", error.localizedDescription)
            }
        }
    }

    /// Runs prediction using path shape matching against the dictionary.
    /// Compares the actual swipe trajectory against ideal paths for candidate words.
    func predict(samples: [SwipeSample], beamWidth: Int = 8, topN: Int = 5) -> [SwipeTypingPrediction] {
        lock.lock()
        let dict = dictionary
        lock.unlock()

        guard samples.count >= 5, !dict.isEmpty else { return [] }

        // 1. Collect keys visited along the path (for pre-filtering)
        var visitedKeys = Set<Character>()
        var nearestAtStart = Set<Character>()
        var nearestAtEnd = Set<Character>()
        for (i, sample) in samples.enumerated() {
            let point = CGPoint(x: sample.x, y: sample.y)
            // Add top-3 nearest keys at each point for broader coverage
            let nearest3 = SwipeKeyboardLayout.nearestKeys(to: point, count: 3)
            for key in nearest3 {
                visitedKeys.insert(Character(key.character.lowercased()))
            }
            // Track first/last segment keys (first/last 25% of samples)
            if i < max(1, samples.count / 4) {
                for key in nearest3 { nearestAtStart.insert(Character(key.character.lowercased())) }
            }
            if i >= samples.count - max(1, samples.count / 4) {
                for key in nearest3 { nearestAtEnd.insert(Character(key.character.lowercased())) }
            }
        }

        // Estimate word length from key transitions (not arc length)
        let wordLenEstimate = estimateWordLength(samples: samples)

        // Debug log
        let debugURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("swipe_debug.log")
        let debugMsg = "[PathMatch] visited=\(String(visitedKeys.sorted())), start=\(String(nearestAtStart.sorted())), end=\(String(nearestAtEnd.sorted())), estLen=\(wordLenEstimate)\n"
        if let h = try? FileHandle(forWritingTo: debugURL) {
            h.seekToEndOfFile()
            h.write(debugMsg.data(using: .utf8)!)
            h.closeFile()
        } else {
            try? debugMsg.write(to: debugURL, atomically: true, encoding: .utf8)
        }

        // 2. Pre-filter dictionary (generous length bounds — path similarity handles ranking)
        let minLen = 2
        let maxLen = min(wordLenEstimate + 5, 15)
        var candidates: [(word: String, similarity: Double)] = []

        for word in dict {
            // Length filter
            guard word.count >= minLen && word.count <= maxLen else { continue }
            let chars = Array(word)
            // First character must be near start of path
            guard nearestAtStart.contains(chars[0]) else { continue }
            // Last character must be near end of path
            guard nearestAtEnd.contains(chars[chars.count - 1]) else { continue }
            // All unique characters must be in visited set
            let wordChars = Set(chars)
            guard wordChars.isSubset(of: visitedKeys) else { continue }

            // 3. Score by path shape similarity
            let sim = pathSimilarity(word: word, samples: samples)
            candidates.append((word, sim))
        }

        // Sort by similarity (higher is better)
        candidates.sort { $0.similarity > $1.similarity }

        let predictions = candidates.prefix(topN).map {
            SwipeTypingPrediction(word: $0.word, confidence: $0.similarity)
        }

        // Debug log top results
        let resultMsg = "[PathMatch] top5: \(predictions.map { "\($0.word)(\(String(format: "%.3f", $0.confidence)))" }.joined(separator: ", "))\n"
        if let h = try? FileHandle(forWritingTo: debugURL) {
            h.seekToEndOfFile()
            h.write(resultMsg.data(using: .utf8)!)
            h.closeFile()
        }

        return Array(predictions)
    }

    // MARK: - Path Matching Helpers

    /// Estimate the intended word length from nearest-key transitions in the path.
    private func estimateWordLength(samples: [SwipeSample]) -> Int {
        // Count distinct nearest-key transitions (collapsed)
        var transitions = 1
        var lastKey: Character?
        for sample in samples {
            let point = CGPoint(x: sample.x, y: sample.y)
            guard let nearest = SwipeKeyboardLayout.nearestKey(to: point) else { continue }
            let ch = Character(nearest.character.lowercased())
            if let last = lastKey, ch != last {
                transitions += 1
            }
            lastKey = ch
        }
        // The number of key transitions is typically 2-3x the word length
        // (because the cursor passes through intermediate keys)
        let estimated = max(2, transitions / 2)
        return min(estimated, 12)
    }

    // MARK: - Path Similarity

    /// Score how well a word's expected key positions match the actual swipe path.
    /// Uses DTW-like alignment: for each letter in the word, find the closest
    /// point on the swipe path (in temporal order) to that letter's key center.
    /// Returns 0-1 where 1 is perfect match.
    private func pathSimilarity(word: String, samples: [SwipeSample]) -> Double {
        let wordChars = Array(word.uppercased())
        var keyCenters: [CGPoint] = []
        for ch in wordChars {
            if let key = SwipeKeyboardLayout.key(for: ch) {
                keyCenters.append(key.center)
            }
        }
        guard keyCenters.count >= 2, samples.count >= 2 else { return 0 }

        // For each letter, find the point on the path that minimizes total distance
        // while maintaining temporal order (each letter maps to a later point than previous)
        var totalDist = 0.0
        var searchStart = 0
        let segmentSize = max(1, samples.count / keyCenters.count)

        for (i, center) in keyCenters.enumerated() {
            // Search window: from searchStart to a reasonable end
            let searchEnd = min(samples.count, searchStart + segmentSize * 2 + 1)
            var bestDist = Double.greatestFiniteMagnitude
            var bestIdx = searchStart

            for j in searchStart..<searchEnd {
                let dx = samples[j].x - Double(center.x)
                let dy = samples[j].y - Double(center.y)
                let dist = (dx * dx + dy * dy).squareRoot()
                if dist < bestDist {
                    bestDist = dist
                    bestIdx = j
                }
            }

            totalDist += bestDist
            // Advance search start for next letter (must be after this match)
            searchStart = bestIdx + 1
            if searchStart >= samples.count && i < keyCenters.count - 1 {
                // Ran out of path — penalize heavily
                totalDist += Double(keyCenters.count - i - 1) * 0.5
                break
            }
        }

        let avgDist = totalDist / Double(keyCenters.count)
        // Convert to 0-1 similarity (dist of 0 → 1.0, dist of 0.3 → ~0.22)
        return exp(-avgDist * 5.0)
    }

    // MARK: - Feature Building

    /// Builds the (1, MAX_STROKE_LEN, 29) feature tensor from swipe samples.
    /// Features per sample: x, y, dt, 26-dim key proximity vector.
    private func buildFeatures(from samples: [SwipeSample]) throws -> MLMultiArray {
        let featureDim = 29  // x, y, dt + 26 proximity
        let array = try MLMultiArray(
            shape: [1, NSNumber(value: MAX_STROKE_LEN), NSNumber(value: featureDim)],
            dataType: .float32
        )

        // Zero-fill
        let ptr = array.dataPointer.bindMemory(to: Float.self, capacity: MAX_STROKE_LEN * featureDim)
        ptr.update(repeating: 0, count: MAX_STROKE_LEN * featureDim)

        // Subsample if too long
        let effectiveSamples: [SwipeSample]
        if samples.count > MAX_STROKE_LEN {
            var subsampled: [SwipeSample] = []
            let step = Double(samples.count - 1) / Double(MAX_STROKE_LEN - 1)
            for i in 0..<MAX_STROKE_LEN {
                subsampled.append(samples[Int(Double(i) * step)])
            }
            effectiveSamples = subsampled
        } else {
            effectiveSamples = samples
        }

        // Log strides to verify C-contiguous layout
        struct FeaturesDebug { nonisolated(unsafe) static var logged = false }
        if !FeaturesDebug.logged {
            FeaturesDebug.logged = true
            let debugURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("swipe_debug.log")
            let msg = "[Features] array shape=\(array.shape), strides=\(array.strides)\n"
            if let h = try? FileHandle(forWritingTo: debugURL) {
                h.seekToEndOfFile()
                h.write(msg.data(using: .utf8)!)
                h.closeFile()
            }
        }

        for (i, sample) in effectiveSamples.enumerated() {
            let base = i * featureDim
            ptr[base + 0] = Float(sample.x)
            ptr[base + 1] = Float(sample.y)
            ptr[base + 2] = Float(min(sample.dt, 1.0))

            // 26-dim key proximity (A-Z order)
            let proximity = SwipeKeyboardLayout.keyProximityVector(
                for: CGPoint(x: sample.x, y: sample.y)
            )
            for (j, p) in proximity.enumerated() {
                ptr[base + 3 + j] = Float(p)
            }

            // Log first sample's proximity for comparison with Python
            if i == 0 {
                let debugURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("swipe_debug.log")
                let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
                var top3: [(Character, Float)] = []
                for (j, p) in proximity.enumerated() {
                    let ch = alphabet[alphabet.index(alphabet.startIndex, offsetBy: j)]
                    top3.append((ch, Float(p)))
                }
                top3.sort { $0.1 > $1.1 }
                let top3Str = top3.prefix(5).map { "\($0.0)=\(String(format: "%.4f", $0.1))" }.joined(separator: ", ")
                let msg = String(format: "[Features] sample[0]: x=%.4f y=%.4f dt=%.4f top5prox=[%@]\n",
                                 sample.x, sample.y, sample.dt, top3Str)
                if let h = try? FileHandle(forWritingTo: debugURL) {
                    h.seekToEndOfFile()
                    h.write(msg.data(using: .utf8)!)
                    h.closeFile()
                }
            }
        }

        return array
    }

    // MARK: - Beam Search

    private typealias Beam = (tokens: [Int32], score: Double)

    private func beamSearch(
        model: MLModel,
        features: MLMultiArray,
        strokeLen: MLMultiArray,
        beamWidth: Int,
        maxLen: Int
    ) throws -> [Beam] {
        var beams: [Beam] = [([SOS_TOKEN], 0.0)]
        var finished: [Beam] = []

        for step in 0..<maxLen {
            var candidates: [Beam] = []

            for beam in beams {
                let lastToken = beam.tokens.last ?? SOS_TOKEN
                if lastToken == EOS_TOKEN {
                    finished.append(beam)
                    continue
                }

                // Build target_tokens: pad beam tokens to TARGET_LEN
                let targetTokens = try MLMultiArray(shape: [1, NSNumber(value: TARGET_LEN)], dataType: .int32)
                let tPtr = targetTokens.dataPointer.bindMemory(to: Int32.self, capacity: TARGET_LEN)
                tPtr.update(repeating: PAD_TOKEN, count: TARGET_LEN)
                for (i, t) in beam.tokens.enumerated() where i < TARGET_LEN {
                    tPtr[i] = t
                }

                // Run model
                let input = try MLDictionaryFeatureProvider(dictionary: [
                    "features": MLFeatureValue(multiArray: features),
                    "stroke_len": MLFeatureValue(multiArray: strokeLen),
                    "target_tokens": MLFeatureValue(multiArray: targetTokens),
                ])
                let output = try model.prediction(from: input)

                guard let logits = output.featureValue(for: "logits")?.multiArrayValue else {
                    NSLog("[SwipeTypingModel] No logits in output")
                    continue
                }

                // logits shape: (1, TARGET_LEN-1, VOCAB_SIZE)
                // We want the logits at position (step) which predicts token at position (step+1)
                let logitPos = beam.tokens.count - 1  // index into decoder output
                guard logitPos < TARGET_LEN - 1 else { continue }

                // Extract logits using safe subscript access (handles float16/float32 automatically)
                // Debug: log data type once
                struct StridesDebug { nonisolated(unsafe) static var logged = false }
                if !StridesDebug.logged {
                    StridesDebug.logged = true
                    let debugURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("swipe_debug.log")
                    let debugMsg = "[Model] logits shape=\(logits.shape), strides=\(logits.strides), dataType=\(logits.dataType.rawValue)\n"
                    if let h = try? FileHandle(forWritingTo: debugURL) {
                        h.seekToEndOfFile()
                        h.write(debugMsg.data(using: .utf8)!)
                        h.closeFile()
                    }
                }

                // Read logits at this position using safe subscript (auto-converts float16→float32)
                var logitValues = [Float](repeating: 0, count: VOCAB_SIZE)
                for v in 0..<VOCAB_SIZE {
                    logitValues[v] = logits[[0, logitPos, v] as [NSNumber]].floatValue
                }

                // Compute log-softmax
                var maxVal: Float = -Float.infinity
                for v in 0..<VOCAB_SIZE {
                    maxVal = max(maxVal, logitValues[v])
                }
                var sumExp: Float = 0
                for v in 0..<VOCAB_SIZE {
                    sumExp += exp(logitValues[v] - maxVal)
                }
                let logSumExp = maxVal + log(sumExp)

                // Find top-k tokens
                var tokenScores: [(Int32, Float)] = []
                for v in 0..<VOCAB_SIZE {
                    let logProb = logitValues[v] - logSumExp
                    tokenScores.append((Int32(v), logProb))
                }
                tokenScores.sort { $0.1 > $1.1 }

                // Log first-step logits for comparison with Python
                if step == 0 && beam.tokens == [SOS_TOKEN] {
                    let debugURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("swipe_debug.log")
                    func tokenChar(_ t: Int32) -> String {
                        if t == 0 { return "<PAD>" }
                        if t >= 1 && t <= 26 { return String(Character(UnicodeScalar(Int(UnicodeScalar("a").value) + Int(t) - 1)!)) }
                        if t == 27 { return "<SOS>" }
                        if t == 28 { return "<EOS>" }
                        return "?"
                    }
                    let top5Str = tokenScores.prefix(5).map { "\(tokenChar($0.0))(\(String(format: "%.3f", $0.1)))" }.joined(separator: ", ")
                    let rawLogitsStr = logitValues.map { String(format: "%.2f", $0) }.joined(separator: ",")
                    let msg = "[Beam] step0 top5=[\(top5Str)] rawLogits=[\(rawLogitsStr)]\n"
                    if let h = try? FileHandle(forWritingTo: debugURL) {
                        h.seekToEndOfFile()
                        h.write(msg.data(using: .utf8)!)
                        h.closeFile()
                    }
                }

                for i in 0..<min(beamWidth, tokenScores.count) {
                    let (token, logProb) = tokenScores[i]
                    // Skip PAD token
                    if token == PAD_TOKEN { continue }
                    let newTokens = beam.tokens + [token]
                    let newScore = beam.score + Double(logProb)
                    candidates.append((newTokens, newScore))
                }
            }

            if candidates.isEmpty { break }
            candidates.sort { $0.score > $1.score }
            beams = Array(candidates.prefix(beamWidth))
        }

        // Collect all results
        finished.append(contentsOf: beams)
        // Sort by length-normalized score
        finished.sort { $0.score / Double(max($0.tokens.count, 1)) > $1.score / Double(max($1.tokens.count, 1)) }
        return finished
    }

    // MARK: - Token Decoding

    /// Convert token indices to a word string.
    /// Tokens 1-26 map to a-z. SOS/EOS/PAD are skipped.
    private func tokensToWord(_ tokens: [Int32]) -> String {
        var chars: [Character] = []
        for t in tokens {
            if t == SOS_TOKEN || t == PAD_TOKEN { continue }
            if t == EOS_TOKEN { break }
            if t >= 1 && t <= 26 {
                let scalar = UnicodeScalar(Int(UnicodeScalar("a").value) + Int(t) - 1)!
                chars.append(Character(scalar))
            }
        }
        return String(chars)
    }
}
