import Foundation

/// Persisted identity used to match a profile to a physical controller.
struct ControllerIdentity: Codable, Equatable {
    var stableId: String?
    var fallbackId: String
    var vendorId: Int?
    var productId: Int?
    var productName: String?
    var transport: String?
    var serialNumber: String?
    var deviceAddress: String?

    var hasStableId: Bool {
        stableId != nil
    }

    var displayName: String {
        productName ?? fallbackId
    }

    func matches(_ other: ControllerIdentity) -> Bool {
        if let stableId, let otherStableId = other.stableId {
            return stableId == otherStableId
        }
        return fallbackId == other.fallbackId
    }

    func exactMatches(_ other: ControllerIdentity) -> Bool {
        guard let stableId, let otherStableId = other.stableId else { return false }
        return stableId == otherStableId
    }
}

struct ControllerProfileBinding: Codable, Equatable, Identifiable {
    var id: UUID
    var displayName: String
    var identity: ControllerIdentity
    var createdAt: Date
    var lastSeenAt: Date?

    init(
        id: UUID = UUID(),
        displayName: String,
        identity: ControllerIdentity,
        createdAt: Date = Date(),
        lastSeenAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.identity = identity
        self.createdAt = createdAt
        self.lastSeenAt = lastSeenAt
    }
}

enum InputLatencyMode: String, Codable, CaseIterable, Identifiable {
    case standard
    case realtime

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .realtime: return "Realtime"
        }
    }
}
