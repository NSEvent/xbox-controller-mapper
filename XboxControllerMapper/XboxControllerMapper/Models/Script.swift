import Foundation

/// A user-defined JavaScript script that can be triggered by controller input
struct Script: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var source: String             // JavaScript source code
    var description: String?       // Optional user notes
    var createdAt: Date
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        name: String = "",
        source: String = "",
        description: String? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.description = description
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, source, description, createdAt, modifiedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? Date()
    }
}

/// The type of button press that triggered a script
enum PressType: String, Codable, Sendable {
    case press
    case release
    case longHold
    case doubleTap
}

/// Context passed to a script when it's triggered by controller input
struct ScriptTrigger {
    let button: ControllerButton
    let pressType: PressType
    let holdDuration: TimeInterval?
    let timestamp: Date

    init(button: ControllerButton, pressType: PressType = .press, holdDuration: TimeInterval? = nil, timestamp: Date = Date()) {
        self.button = button
        self.pressType = pressType
        self.holdDuration = holdDuration
        self.timestamp = timestamp
    }
}

/// Result of executing a script
enum ScriptResult {
    case success(hintOverride: String?)
    case error(String)
}
