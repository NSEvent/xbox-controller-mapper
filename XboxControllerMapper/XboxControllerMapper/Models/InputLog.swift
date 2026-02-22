import Foundation

enum InputEventType: String, Codable {
    case singlePress = "Press"
    case doubleTap = "Double Tap"
    case longPress = "Long Press"
    case chord = "Chord"
    case sequence = "Sequence"
    case gesture = "Gesture"
    case webhookSuccess = "Webhook ✓"
    case webhookFailure = "Webhook ✗"
}

struct InputLogEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp = Date()
    let buttons: [ControllerButton]
    let type: InputEventType
    let actionDescription: String
}
