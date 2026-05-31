import Foundation

let startDate = Date()

// Baseline:
let start1 = Date()
for _ in 0..<10_000 {
    _ = ISO8601DateFormatter().string(from: startDate)
}
let baseline = Date().timeIntervalSince(start1)
print("Baseline: \(baseline)")

// Optimized:
let isoFormatter = ISO8601DateFormatter()
let start2 = Date()
for _ in 0..<10_000 {
    _ = isoFormatter.string(from: startDate)
}
let optimized = Date().timeIntervalSince(start2)
print("Optimized: \(optimized)")
