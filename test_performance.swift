import Foundation

// Generate a large array of random words
func generateWords(count: Int) -> [String] {
    var words: [String] = []
    let characters = "abcdefghijklmnopqrstuvwxyz"
    for _ in 0..<count {
        let length = Int.random(in: 4...10)
        let word = String((0..<length).map { _ in characters.randomElement()! })
        words.append(word)
    }
    return words
}

let words = generateWords(count: 100000)
let searchWords = generateWords(count: 1000)

let startTimeArray = CFAbsoluteTimeGetCurrent()
var arrayContainsCount = 0
for searchWord in searchWords {
    if words.contains(searchWord) {
        arrayContainsCount += 1
    }
}
let timeElapsedArray = CFAbsoluteTimeGetCurrent() - startTimeArray
print("Array contains time: \(timeElapsedArray) seconds")

let wordSet = Set(words)
let startTimeSet = CFAbsoluteTimeGetCurrent()
var setContainsCount = 0
for searchWord in searchWords {
    if wordSet.contains(searchWord) {
        setContainsCount += 1
    }
}
let timeElapsedSet = CFAbsoluteTimeGetCurrent() - startTimeSet
print("Set contains time: \(timeElapsedSet) seconds")
