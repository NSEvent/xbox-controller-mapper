import Foundation

extension TelemetryService {
    enum FeatureCategory: String, Codable {
        case keyboard, pointer, macro, automation, midi, other
        case profileControl = "profile_control"
    }

    enum ControllerFamily: String, Codable {
        case xbox, playstation, nintendo, steam, generic, wearable, unknown
        case appleTVRemote = "apple_tv_remote"
        case handTracking = "hand_tracking"
    }

    enum ProfileOrigin: String, Codable {
        case manual, community
        case `import`, `default`
    }

    enum MappingWorkflow: String, Codable {
        case button, chord, sequence, gesture, layer
        case `import`
    }

    enum ActivationErrorCategory: String, Codable {
        case emptyKey = "empty_key"
        case invalidKey = "invalid_key"
        case revokedPurchase = "revoked_purchase"
        case network, server, unknown
    }

    struct QueuedEvent: Codable {
        let event: String
        let eventID: String
        let occurredAt: String
        let schemaVersion: Int
        let installID: String
        let appVersion: String
        let build: String
        let osVersion: String
        let arch: String
        let locale: String
        let status: String
        let trialDay: Int
        let channel: String
        let saleID: String?
        let funnelVersion: String
        let offerVersion: String
        let clientDay: String?
        let surface: String?
        let controllerFamily: String?
        let profileOrigin: String?
        let workflow: String?
        let actionCountBucket: String?
        let featureCategories: [String]?
        let complexActionUsed: Bool?
        let result: String?
        let errorCategory: String?

        enum CodingKeys: String, CodingKey {
            case event, build, arch, locale, status, channel, surface, workflow, result
            case eventID = "event_id"
            case occurredAt = "occurred_at"
            case schemaVersion = "schema_version"
            case installID = "install_id"
            case appVersion = "app_version"
            case osVersion = "os_version"
            case trialDay = "trial_day"
            case saleID = "sale_id"
            case funnelVersion = "funnel_version"
            case offerVersion = "offer_version"
            case clientDay = "client_day"
            case controllerFamily = "controller_family"
            case profileOrigin = "profile_origin"
            case actionCountBucket = "action_count_bucket"
            case featureCategories = "feature_categories"
            case complexActionUsed = "complex_action_used"
            case errorCategory = "error_category"
        }
    }

    struct EventBatch: Encodable {
        let events: [QueuedEvent]
    }

    struct DailyUsage: Codable {
        var day: String
        var actionCount: Int = 0
        var categories: Set<String> = []
        var usedComplexAction = false

        var actionCountBucket: String {
            switch actionCount {
            case 0: return "0"
            case 1...5: return "1-5"
            case 6...25: return "6-25"
            case 26...100: return "26-100"
            default: return "101+"
            }
        }
    }

    static let defaultEndpoint = URL(string: "https://analytics.kevintang.app/controllerkeys/e")!
    static let schemaVersion = 2
    static let funnelVersion = "trial-v2-2026-09"
    static let offerVersion = "gumroad-19.99-v1"
    static let maximumOutboxCount = 100
    static let batchSize = 25
    static let retryDelays: [TimeInterval] = [5, 15, 60, 300, 900, 3_600]

    static func defaultTransport(request: URLRequest, completion: @escaping (Int?) -> Void) {
        URLSession.shared.dataTask(with: request) { _, response, _ in
            completion((response as? HTTPURLResponse)?.statusCode)
        }.resume()
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    static var osVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    static var arch: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    static var channel: String {
        for prefix in ["/opt/homebrew", "/usr/local"] {
            if FileManager.default.fileExists(atPath: "\(prefix)/Caskroom/controllerkeys") { return "homebrew" }
        }
        return "direct"
    }

    static func dayStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    static func safeDimension(_ value: String) -> String {
        String(value.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" }.prefix(32))
    }
}
