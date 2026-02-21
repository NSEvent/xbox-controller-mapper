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
    /// 1. Extracts the nearest-key sequence from the swipe path
    /// 2. Pre-filters dictionary by key sequence matching
    /// 3. Scores candidates using DTW alignment + coverage + length match
    func predict(samples: [SwipeSample], beamWidth: Int = 8, topN: Int = 5) -> [SwipeTypingPrediction] {
        lock.lock()
        let dict = dictionary
        lock.unlock()

        guard samples.count >= 5, !dict.isEmpty else { return [] }

        let samplePoints = samples.map { CGPoint(x: $0.x, y: $0.y) }

        // 1. Extract nearest-key sequence from the swipe path.
        //    For each sample, find the nearest key. Collapse consecutive duplicates.
        //    This gives us the sequence of keys the cursor passed through.
        var keySequence: [Character] = []
        for point in samplePoints {
            if let nearest = SwipeKeyboardLayout.nearestKey(to: point) {
                let ch = Character(nearest.character.lowercased())
                if keySequence.last != ch {
                    keySequence.append(ch)
                }
            }
        }

        // Also collect top-2 nearest for a broader visited set
        var visitedKeys = Set<Character>()
        for point in samplePoints {
            for key in SwipeKeyboardLayout.nearestKeys(to: point, count: 2) {
                visitedKeys.insert(Character(key.character.lowercased()))
            }
        }

        // Estimate word length from key transitions (more reliable than displacement)
        // keySequence length is typically 2-3x the word length (includes intermediate keys)
        let estWordLen = max(2, min((keySequence.count + 1) / 2, 15))

        // 2. Pre-filter: word characters must appear as a subsequence of the key sequence
        //    (allowing gaps for intermediate keys the cursor passed through)
        var candidates: [(word: String, similarity: Double)] = []

        for word in dict {
            guard word.count >= 2 && word.count <= 12 else { continue }

            // Quick check: most unique characters in the word must be in visited keys
            // (allow 1 missed character for nearby keys not in the top-2)
            let wordChars = Array(word)
            let uniqueWordChars = Set(wordChars)
            let missedCount = uniqueWordChars.filter { !visitedKeys.contains($0) }.count
            guard missedCount <= 1 else { continue }

            // Check subsequence match: word chars must appear in order in keySequence
            let subseqScore = subsequenceMatchScore(word: wordChars, keySequence: keySequence)
            guard subseqScore > 0 else { continue }

            // Score by DTW alignment quality
            let dtwScore = pathSimilarity(word: word, samplePoints: samplePoints, estWordLen: estWordLen)

            // Combined score: subsequence quality + DTW alignment
            let combined = 0.4 * subseqScore + 0.6 * dtwScore
            candidates.append((word, combined))
        }

        // Sort by similarity (higher is better)
        candidates.sort { $0.similarity > $1.similarity }

        let predictions = candidates.prefix(topN).map {
            SwipeTypingPrediction(word: $0.word, confidence: $0.similarity)
        }

        // Debug log
        let debugURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("swipe_debug.log")
        let keySeqStr = String(keySequence)
        let visited = String(visitedKeys.sorted())
        let top5 = predictions.map { "\($0.word)(\(String(format: "%.3f", $0.confidence)))" }.joined(separator: ", ")
        let msg = "[PathMatch] keySeq=\(keySeqStr), visited=\(visited), estLen=\(estWordLen), candidates=\(candidates.count), top5: \(top5)\n"
        if let h = try? FileHandle(forWritingTo: debugURL) {
            h.seekToEndOfFile()
            h.write(msg.data(using: .utf8)!)
            h.closeFile()
        } else {
            try? msg.write(to: debugURL, atomically: true, encoding: .utf8)
        }

        return Array(predictions)
    }

    // MARK: - Subsequence Matching

    /// Collapse consecutive duplicate characters in a word.
    /// "hello" → "helo", "Mississippi" → "misisipi"
    /// This matches the key sequence which also has duplicates collapsed.
    private func collapseRepeats(_ chars: [Character]) -> [Character] {
        var result: [Character] = []
        for ch in chars {
            if result.last != ch {
                result.append(ch)
            }
        }
        return result
    }

    /// Score how well the word's characters match as a subsequence of the key sequence.
    /// Returns 0 if not a subsequence, 0-1 based on match quality.
    /// Higher scores for tighter matches (fewer gaps between matched characters).
    /// Consecutive duplicate letters in the word are collapsed (e.g., "hello" → "helo")
    /// since the key sequence also collapses consecutive duplicates.
    private func subsequenceMatchScore(word: [Character], keySequence: [Character]) -> Double {
        guard !word.isEmpty, !keySequence.isEmpty else { return 0 }

        // Collapse consecutive duplicates in the word to match key sequence format
        let collapsed = collapseRepeats(word)

        // Greedy subsequence match: find each collapsed word character in order in keySequence.
        // Allow up to 1 skipped character (for keys the cursor barely missed).
        var keyIdx = 0
        var matchPositions: [Int] = []
        var skipped = 0

        for ch in collapsed {
            var found = false
            let savedKeyIdx = keyIdx
            while keyIdx < keySequence.count {
                if keySequence[keyIdx] == ch {
                    matchPositions.append(keyIdx)
                    keyIdx += 1
                    found = true
                    break
                }
                keyIdx += 1
            }
            if !found {
                skipped += 1
                keyIdx = savedKeyIdx  // Reset so future characters can still match
                if skipped > 1 { return 0 }  // Too many misses
            }
        }

        // Need at least 2 matched positions
        guard matchPositions.count >= 2 else { return 0 }

        // Match fraction: what fraction of the collapsed word was matched
        let matchFraction = Double(matchPositions.count) / Double(collapsed.count)

        // Coverage: what fraction of the key sequence does the match span?
        // In swipe typing, the target word should span MOST of the swipe path.
        // Words that only match a small fragment of the path should score lower.
        let totalSpan = matchPositions.last! - matchPositions.first! + 1
        let coverage = Double(totalSpan) / Double(keySequence.count)

        // Penalize skipped characters
        let skipPenalty = skipped == 0 ? 1.0 : 0.6

        // Combined: reward full matches that span the whole key sequence.
        // Don't penalize gaps between matched characters (intermediate keys are expected).
        return matchFraction * (0.3 + 0.7 * coverage) * skipPenalty
    }

    // MARK: - Path Geometry Helpers

    /// Total displacement of a swipe path — sum of distances between consecutive points.
    private func pathTotalDisplacement(_ points: [CGPoint]) -> Double {
        guard points.count >= 2 else { return 0 }
        var total = 0.0
        for i in 1..<points.count {
            let dx = Double(points[i].x - points[i-1].x)
            let dy = Double(points[i].y - points[i-1].y)
            total += (dx * dx + dy * dy).squareRoot()
        }
        return total
    }

    /// Bounding box diagonal of the swipe path — measures the spatial extent.
    private func pathExtent(_ points: [CGPoint]) -> Double {
        guard points.count >= 2 else { return 0 }
        var minX = Double.greatestFiniteMagnitude, maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude, maxY = -Double.greatestFiniteMagnitude
        for p in points {
            minX = min(minX, Double(p.x)); maxX = max(maxX, Double(p.x))
            minY = min(minY, Double(p.y)); maxY = max(maxY, Double(p.y))
        }
        let dx = maxX - minX
        let dy = maxY - minY
        return (dx * dx + dy * dy).squareRoot()
    }

    // MARK: - Path Similarity (DTW Alignment)

    /// Score how well a word's expected key positions match the actual swipe path.
    /// Uses optimal subsequence alignment: finds the best temporal mapping of each
    /// letter to a point on the path, allowing the path to pass through intermediate keys.
    /// Also incorporates a path coverage penalty so that longer words that use more of
    /// the swipe path are preferred over short words that only match a fragment.
    /// Returns 0-1 where 1 is perfect match.
    private func pathSimilarity(word: String, samplePoints: [CGPoint], estWordLen: Int) -> Double {
        let wordChars = Array(word.uppercased())
        var keyCenters: [CGPoint] = []
        for ch in wordChars {
            if let key = SwipeKeyboardLayout.key(for: ch) {
                keyCenters.append(key.center)
            }
        }
        guard keyCenters.count >= 2, samplePoints.count >= 2 else { return 0 }

        let n = keyCenters.count   // word length
        let m = samplePoints.count // path length

        // DP: find the minimum-cost monotone alignment of n keys to m path points.
        // dp[i][j] = min total distance to align keys[0..i-1] to path[0..j-1]
        // where key i is aligned to path point j.
        // Transition: dp[i][j] = dist(key_i, point_j) + min(dp[i-1][k] for k < j)
        //
        // Optimization: track running min to avoid O(n*m^2).
        var prevRow = [Double](repeating: Double.greatestFiniteMagnitude, count: m)

        // Track which path point each key aligns to (for coverage computation)
        var prevArgmin = [Int](repeating: 0, count: m)

        // First key: can align to any path point (allows cursor to start anywhere)
        for j in 0..<m {
            let dx = Double(keyCenters[0].x) - Double(samplePoints[j].x)
            let dy = Double(keyCenters[0].y) - Double(samplePoints[j].y)
            prevRow[j] = (dx * dx + dy * dy).squareRoot()
            prevArgmin[j] = j
        }

        // Track alignment endpoints for coverage
        var prevBestPredecessor = [Int](repeating: 0, count: m) // which j from prev row was used

        // Subsequent keys
        for i in 1..<n {
            var currRow = [Double](repeating: Double.greatestFiniteMagnitude, count: m)
            var runningMin = Double.greatestFiniteMagnitude
            var runningMinIdx = 0
            var currBestPredecessor = [Int](repeating: 0, count: m)

            for j in 0..<m {
                // Update running min from previous row (all points before j)
                if j > 0 && prevRow[j - 1] < runningMin {
                    runningMin = prevRow[j - 1]
                    runningMinIdx = j - 1
                }
                guard runningMin < Double.greatestFiniteMagnitude else { continue }

                let dx = Double(keyCenters[i].x) - Double(samplePoints[j].x)
                let dy = Double(keyCenters[i].y) - Double(samplePoints[j].y)
                let dist = (dx * dx + dy * dy).squareRoot()
                currRow[j] = runningMin + dist
                currBestPredecessor[j] = runningMinIdx
            }
            prevRow = currRow
            prevBestPredecessor = currBestPredecessor
        }

        // Find best endpoint
        var bestJ = 0
        var bestDist = Double.greatestFiniteMagnitude
        for j in 0..<m {
            if prevRow[j] < bestDist {
                bestDist = prevRow[j]
                bestJ = j
            }
        }

        let totalDist = bestDist
        let avgDist = totalDist / Double(n)

        // Alignment similarity: how close each key is to its aligned path point
        let alignSim = exp(-avgDist * 5.0)

        // Coverage: what fraction of the swipe path is spanned by the alignment?
        // Trace back to find start point of the first key
        // For simplicity, use the extent of the word's ideal path vs the swipe extent
        var wordExtent = 0.0
        for i in 1..<keyCenters.count {
            let dx = Double(keyCenters[i].x - keyCenters[i-1].x)
            let dy = Double(keyCenters[i].y - keyCenters[i-1].y)
            wordExtent += (dx * dx + dy * dy).squareRoot()
        }

        let swipeExtent = pathTotalDisplacement(samplePoints)
        // Coverage ratio: how much of the swipe does this word's path explain?
        let coverageRatio = swipeExtent > 0.01 ? min(wordExtent / swipeExtent, 1.0) : 0.5

        // Length penalty: prefer words whose length is close to estimated word length
        let lenDiff = abs(n - estWordLen)
        let lenPenalty: Double
        if lenDiff == 0 {
            lenPenalty = 1.0
        } else if lenDiff == 1 {
            lenPenalty = 0.9
        } else if lenDiff == 2 {
            lenPenalty = 0.7
        } else {
            lenPenalty = max(0.3, 1.0 - Double(lenDiff) * 0.15)
        }

        // Combined score: alignment quality * coverage * length match
        return alignSim * (0.5 + 0.5 * coverageRatio) * lenPenalty
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
