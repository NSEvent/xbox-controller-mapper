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

// MARK: - SHARK2 Template

/// Precomputed template for a single dictionary word.
private struct WordTemplate {
    let locationPoints: [CGPoint]  // N resampled points (absolute 0-1 coords)
    let shapePoints: [CGPoint]     // N normalized points (centroid=origin, unit variance)
    let frequency: Int
    let firstChar: Character
    let lastChar: Character
}

// MARK: - Constants

private let RESAMPLE_COUNT = 32

// MARK: - SwipeTypingModel

/// SHARK2-inspired swipe typing engine.
/// Uses template matching with dual-channel scoring (location + shape) and endpoint pruning.
class SwipeTypingModel {
    private var model: MLModel?
    private let lock = NSLock()
    private var templates: [String: WordTemplate] = [:]
    private var maxFrequency: Int = 1

    var isLoaded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !templates.isEmpty
    }

    /// Loads the dictionary and precomputes word templates on a background thread.
    func loadModel() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            guard let vocabURL = Bundle.main.url(forResource: "swipe_vocab", withExtension: "txt"),
                  let vocabText = try? String(contentsOf: vocabURL, encoding: .utf8) else {
                NSLog("[SwipeTypingModel] swipe_vocab.txt not found in bundle")
                return
            }

            var wordFreqs: [(String, Int)] = []
            var maxFreq = 1
            for line in vocabText.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }

                let word: String
                let freq: Int
                if let tabIdx = trimmed.firstIndex(of: "\t") {
                    word = String(trimmed[trimmed.startIndex..<tabIdx]).lowercased()
                    freq = Int(trimmed[trimmed.index(after: tabIdx)...]) ?? 1
                } else {
                    word = trimmed.lowercased()
                    freq = 1
                }
                guard word.count >= 2, word.count <= 12, word.allSatisfy({ $0.isLetter }) else { continue }
                wordFreqs.append((word, freq))
                maxFreq = max(maxFreq, freq)
            }

            // Add user's shell aliases and functions from their zsh/bash config
            let existingWords = Set(wordFreqs.map { $0.0 })
            let shellWords = Self.parseShellAliasesAndFunctions()
            let shellFreq = 7000  // Same boost as app names / directory names
            var shellAdded = 0
            for name in shellWords {
                let lower = name.lowercased()
                guard lower.count >= 2, lower.count <= 12, lower.allSatisfy({ $0.isLetter }) else { continue }
                if !existingWords.contains(lower) {
                    wordFreqs.append((lower, shellFreq))
                    shellAdded += 1
                }
                maxFreq = max(maxFreq, shellFreq)
            }
            if shellAdded > 0 {
                NSLog("[SwipeTypingModel] Added %d shell aliases/functions to dictionary", shellAdded)
            }

            // Precompute templates
            var builtTemplates: [String: WordTemplate] = [:]
            builtTemplates.reserveCapacity(wordFreqs.count)

            for (word, freq) in wordFreqs {
                guard let locationPath = Self.buildWordPath(for: word) else { continue }
                let resampled = Self.resamplePath(locationPath, toCount: RESAMPLE_COUNT)
                let shape = Self.normalizePath(resampled)
                let chars = Array(word)
                guard let firstChar = chars.first, let lastChar = chars.last else { continue }
                builtTemplates[word] = WordTemplate(
                    locationPoints: resampled,
                    shapePoints: shape,
                    frequency: freq,
                    firstChar: firstChar,
                    lastChar: lastChar
                )
            }

            self.lock.lock()
            self.templates = builtTemplates
            self.maxFrequency = maxFreq
            self.lock.unlock()

            NSLog("[SwipeTypingModel] SHARK2 templates loaded: %d words, maxFreq=%d", builtTemplates.count, maxFreq)
        }
    }

    // MARK: - Prediction (SHARK2)

    func predict(samples: [SwipeSample], beamWidth: Int = 8, topN: Int = 5) -> [SwipeTypingPrediction] {
        lock.lock()
        let tmpl = templates
        let maxFreq = maxFrequency
        lock.unlock()

        guard samples.count >= 5, !tmpl.isEmpty else { return [] }

        // 1. Smooth input samples
        let smoothed = Self.smoothSamples(samples, windowSize: 3)
        let samplePoints = smoothed.map { CGPoint(x: $0.x, y: $0.y) }

        // 2. Resample gesture to N equidistant points
        let gestureLocation = Self.resamplePath(samplePoints, toCount: RESAMPLE_COUNT)

        // 3. Normalize gesture for shape channel
        let gestureShape = Self.normalizePath(gestureLocation)

        // 4. Endpoint pruning: top-3 nearest keys at start and end
        guard let startPoint = gestureLocation.first, let endPoint = gestureLocation.last else { return [] }
        let startKeys = Set(SwipeKeyboardLayout.nearestKeys(to: startPoint, count: 3)
            .map { Character($0.character.lowercased()) })
        let endKeys = Set(SwipeKeyboardLayout.nearestKeys(to: endPoint, count: 3)
            .map { Character($0.character.lowercased()) })

        // 5. Score candidates
        var candidates: [(word: String, score: Double)] = []

        for (word, template) in tmpl {
            // Endpoint filter
            guard startKeys.contains(template.firstChar),
                  endKeys.contains(template.lastChar) else { continue }

            // Location score
            let locDist = Self.meanEuclideanDistance(gestureLocation, template.locationPoints)
            let locationScore = 1.0 / (1.0 + locDist)

            // Shape score
            let shapeDist = Self.meanEuclideanDistance(gestureShape, template.shapePoints)
            let shapeScore = 1.0 / (1.0 + shapeDist)

            // Endpoint score: how precisely the gesture starts/ends on the word's keys
            // Uses exponential decay for sharper discrimination between adjacent keys
            let firstKey = SwipeKeyboardLayout.key(for: template.firstChar)!.center
            let lastKey = SwipeKeyboardLayout.key(for: template.lastChar)!.center
            let startDist = hypot(Double(startPoint.x - firstKey.x), Double(startPoint.y - firstKey.y))
            let endDist = hypot(Double(endPoint.x - lastKey.x), Double(endPoint.y - lastKey.y))
            let endpointScore = exp(-(startDist + endDist) * 10.0)

            // Frequency score
            let freqScore = log(Double(template.frequency) + 2.0) / log(Double(maxFreq) + 2.0)

            // Combined: geometry-dominant with strong endpoint precision
            let combined = 0.25 * shapeScore + 0.30 * locationScore + 0.35 * endpointScore + 0.10 * freqScore
            candidates.append((word, combined))
        }

        // Sort descending
        candidates.sort { $0.score > $1.score }

        let predictions = candidates.prefix(topN).map {
            SwipeTypingPrediction(word: $0.word, confidence: $0.score)
        }

        // Debug log
        let debugURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("swipe_debug.log")
        let startKeysStr = String(startKeys.sorted())
        let endKeysStr = String(endKeys.sorted())
        let top5 = predictions.map { "\($0.word)(\(String(format: "%.3f", $0.confidence)))" }.joined(separator: ", ")
        let msg = "[SHARK2] startKeys=\(startKeysStr), endKeys=\(endKeysStr), candidates=\(candidates.count), top5: \(top5)\n"
        if let h = try? FileHandle(forWritingTo: debugURL) {
            h.seekToEndOfFile()
            h.write(msg.data(using: .utf8)!)
            h.closeFile()
        } else {
            try? msg.write(to: debugURL, atomically: true, encoding: .utf8)
        }

        return Array(predictions)
    }

    // MARK: - Path Building

    /// Build the ideal path (polyline through key centers) for a word.
    /// Consecutive duplicate letters are collapsed (e.g., "hello" → H,E,L,O)
    /// because users swipe through repeated letters without pausing.
    private static func buildWordPath(for word: String) -> [CGPoint]? {
        let chars = Array(word.uppercased())
        var path: [CGPoint] = []
        var lastChar: Character?
        for ch in chars {
            if ch == lastChar { continue } // skip consecutive duplicates
            guard let key = SwipeKeyboardLayout.key(for: ch) else { return nil }
            path.append(key.center)
            lastChar = ch
        }
        guard path.count >= 2 else { return nil }
        return path
    }

    // MARK: - Resampling

    /// Resample a polyline to N equidistant points via arc-length interpolation.
    private static func resamplePath(_ points: [CGPoint], toCount N: Int) -> [CGPoint] {
        guard points.count >= 2 else { return points }

        // Compute cumulative arc lengths
        var cumLengths = [0.0]
        for i in 1..<points.count {
            let dx = Double(points[i].x - points[i-1].x)
            let dy = Double(points[i].y - points[i-1].y)
            let segLen = (dx * dx + dy * dy).squareRoot()
            cumLengths.append((cumLengths.last ?? 0.0) + segLen)
        }

        let totalLen = cumLengths.last ?? 0.0
        guard totalLen > 1e-9 else {
            // Degenerate: all points coincide
            return [CGPoint](repeating: points[0], count: N)
        }

        let spacing = totalLen / Double(N - 1)
        var result: [CGPoint] = []
        result.reserveCapacity(N)
        var segIdx = 1

        for i in 0..<N {
            let targetDist = Double(i) * spacing

            // Advance segIdx until cumLengths[segIdx] >= targetDist
            while segIdx < cumLengths.count - 1 && cumLengths[segIdx] < targetDist {
                segIdx += 1
            }

            let segStart = cumLengths[segIdx - 1]
            let segEnd = cumLengths[segIdx]
            let segLen = segEnd - segStart
            let t: Double = segLen > 1e-12 ? (targetDist - segStart) / segLen : 0.0

            let x = Double(points[segIdx - 1].x) + t * Double(points[segIdx].x - points[segIdx - 1].x)
            let y = Double(points[segIdx - 1].y) + t * Double(points[segIdx].y - points[segIdx - 1].y)
            result.append(CGPoint(x: x, y: y))
        }

        return result
    }

    // MARK: - Shape Normalization

    /// Normalize a path: translate centroid to origin, scale to unit variance.
    private static func normalizePath(_ points: [CGPoint]) -> [CGPoint] {
        guard !points.isEmpty else { return points }
        let n = Double(points.count)

        // Centroid
        var cx = 0.0, cy = 0.0
        for p in points {
            cx += Double(p.x)
            cy += Double(p.y)
        }
        cx /= n
        cy /= n

        // Translate to origin
        var centered = points.map { CGPoint(x: Double($0.x) - cx, y: Double($0.y) - cy) }

        // Variance = mean(x² + y²)
        var variance = 0.0
        for p in centered {
            variance += Double(p.x * p.x + p.y * p.y)
        }
        variance /= n

        // Scale by 1/√variance
        if variance > 1e-12 {
            let scale = 1.0 / variance.squareRoot()
            centered = centered.map { CGPoint(x: Double($0.x) * scale, y: Double($0.y) * scale) }
        }

        return centered
    }

    // MARK: - Distance

    /// Mean point-by-point Euclidean distance between two equal-length point arrays.
    private static func meanEuclideanDistance(_ a: [CGPoint], _ b: [CGPoint]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return Double.greatestFiniteMagnitude }
        var total = 0.0
        for i in 0..<a.count {
            let dx = Double(a[i].x - b[i].x)
            let dy = Double(a[i].y - b[i].y)
            total += (dx * dx + dy * dy).squareRoot()
        }
        return total / Double(a.count)
    }

    // MARK: - Smoothing

    /// Moving average filter on sample coordinates.
    private static func smoothSamples(_ samples: [SwipeSample], windowSize: Int) -> [SwipeSample] {
        guard samples.count > windowSize else { return samples }
        let half = windowSize / 2
        var result: [SwipeSample] = []
        result.reserveCapacity(samples.count)

        for i in 0..<samples.count {
            let lo = max(0, i - half)
            let hi = min(samples.count - 1, i + half)
            let count = Double(hi - lo + 1)
            var sx = 0.0, sy = 0.0
            for j in lo...hi {
                sx += samples[j].x
                sy += samples[j].y
            }
            result.append(SwipeSample(x: sx / count, y: sy / count, dt: samples[i].dt))
        }
        return result
    }

    // MARK: - Shell Config Parsing

    /// Parse user's shell config files to extract alias and function names.
    /// Auto-detects zsh vs bash from $SHELL, reads appropriate config files.
    private static func parseShellAliasesAndFunctions() -> Set<String> {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        // Detect shell from $SHELL environment variable
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellName = (shellPath as NSString).lastPathComponent

        // Choose config files based on shell
        let configFiles: [String]
        switch shellName {
        case "bash":
            configFiles = [
                "\(home)/.bashrc",
                "\(home)/.bash_aliases",
                "\(home)/.bash_profile",
            ]
        default: // zsh and anything else
            configFiles = [
                "\(home)/.zshrc",
                "\(home)/.zsh_aliases",
            ]
        }

        var names = Set<String>()

        for path in configFiles {
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            let cleaned = stripShellComments(content)
            names.formUnion(parseAliasNames(from: cleaned))
            names.formUnion(parseFunctionNames(from: cleaned))
        }

        return names
    }

    /// Strip comments (lines starting with # or inline # outside quotes).
    private static func stripShellComments(_ text: String) -> String {
        text.components(separatedBy: .newlines).map { line in
            var result: [Character] = []
            var inSingle = false
            var inDouble = false
            for ch in line {
                if ch == "'" && !inDouble { inSingle.toggle(); result.append(ch) }
                else if ch == "\"" && !inSingle { inDouble.toggle(); result.append(ch) }
                else if ch == "#" && !inSingle && !inDouble { break }
                else { result.append(ch) }
            }
            return String(result)
        }.joined(separator: "\n")
    }

    /// Parse `alias name=value` definitions from shell config text.
    private static func parseAliasNames(from text: String) -> Set<String> {
        // Matches: alias [-flags] name='value' [name2='value2' ...]
        let aliasLineRegex = try! NSRegularExpression(pattern: #"^\s*alias(?:\s+-\w+)*\s+(.+)"#, options: .anchorsMatchLines)
        var names = Set<String>()

        let nsText = text as NSString
        let matches = aliasLineRegex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            let rest = nsText.substring(with: match.range(at: 1))
            // Extract name=value pairs; name is everything before the first =
            // Handle multiple aliases per line: alias a='x' b='y'
            var remaining = rest.trimmingCharacters(in: .whitespaces)
            while !remaining.isEmpty {
                guard let eqIdx = remaining.firstIndex(of: "=") else { break }
                let name = remaining[remaining.startIndex..<eqIdx].trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    names.insert(name)
                }
                // Skip past the value (quoted or unquoted)
                var i = remaining.index(after: eqIdx)
                if i < remaining.endIndex {
                    let quoteChar = remaining[i]
                    if quoteChar == "'" || quoteChar == "\"" {
                        // Find matching close quote
                        i = remaining.index(after: i)
                        while i < remaining.endIndex && remaining[i] != quoteChar {
                            i = remaining.index(after: i)
                        }
                        if i < remaining.endIndex { i = remaining.index(after: i) }
                    } else {
                        // Unquoted value: skip to next whitespace
                        while i < remaining.endIndex && !remaining[i].isWhitespace {
                            i = remaining.index(after: i)
                        }
                    }
                }
                remaining = String(remaining[i...]).trimmingCharacters(in: .whitespaces)
            }
        }
        return names
    }

    /// Parse function definitions: `name() {`, `function name {`, `function name() {`
    private static func parseFunctionNames(from text: String) -> Set<String> {
        let patterns = [
            #"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*\)\s*\{"#,           // name() {
            #"^\s*function\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:\(\s*\))?\s*\{"#, // function name { or function name() {
        ]
        var names = Set<String>()
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else { continue }
            let nsText = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                let name = nsText.substring(with: match.range(at: 1))
                names.insert(name)
            }
        }
        return names
    }
}
