import Foundation

/// A reusable sequence of input actions
struct Macro: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var steps: [MacroStep]
    
    init(id: UUID = UUID(), name: String, steps: [MacroStep] = []) {
        self.id = id
        self.name = name
        self.steps = steps
    }
}

/// A single step in a macro sequence
enum MacroStep: Codable, Equatable {
    /// Press and release a key combination
    case press(KeyMapping)
    
    /// Hold a key combination (must be paired with release or used for duration)
    case hold(KeyMapping, duration: TimeInterval)
    
    /// Wait for a specified duration
    case delay(TimeInterval)
    
    /// Type a string of text with specified speed (CPM). 0 = Instant Paste.
    case typeText(String, speed: Int)
    
    // Custom decoding/encoding to handle enum associated values
    private enum CodingKeys: String, CodingKey {
        case type, payload
    }
    
    private enum StepType: String, Codable {
        case press, hold, delay, typeText
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(StepType.self, forKey: .type)
        
        switch type {
        case .press:
            let mapping = try container.decode(KeyMapping.self, forKey: .payload)
            self = .press(mapping)
        case .hold:
            let data = try container.decode(HoldPayload.self, forKey: .payload)
            self = .hold(data.mapping, duration: data.duration)
        case .delay:
            let duration = try container.decode(TimeInterval.self, forKey: .payload)
            self = .delay(duration)
        case .typeText:
            let data = try container.decode(TypeTextPayload.self, forKey: .payload)
            self = .typeText(data.text, speed: data.speed)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .press(let mapping):
            try container.encode(StepType.press, forKey: .type)
            try container.encode(mapping, forKey: .payload)
        case .hold(let mapping, let duration):
            try container.encode(StepType.hold, forKey: .type)
            try container.encode(HoldPayload(mapping: mapping, duration: duration), forKey: .payload)
        case .delay(let duration):
            try container.encode(StepType.delay, forKey: .type)
            try container.encode(duration, forKey: .payload)
        case .typeText(let text, let speed):
            try container.encode(StepType.typeText, forKey: .type)
            try container.encode(TypeTextPayload(text: text, speed: speed), forKey: .payload)
        }
    }
    
    private struct HoldPayload: Codable {
        let mapping: KeyMapping
        let duration: TimeInterval
    }
    
    private struct TypeTextPayload: Codable {
        let text: String
        let speed: Int
    }
}

extension MacroStep {
    var displayString: String {
        switch self {
        case .press(let mapping):
            return "Press: \(mapping.displayString)"
        case .hold(let mapping, let duration):
            return "Hold: \(mapping.displayString) (\(String(format: "%.2fs", duration)))"
        case .delay(let duration):
            return "Wait: \(String(format: "%.2fs", duration))"
        case .typeText(let text, let speed):
            let speedText = speed == 0 ? "Paste" : "\(speed) CPM"
            return "Type: \"\(text)\" (\(speedText))"
        }
    }
}
