import XCTest
@testable import ControllerKeys

final class TelemetryServiceTests: XCTestCase {
    private final class TransportRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var requests: [URLRequest] = []
        private var completions: [(Int?) -> Void] = []

        func send(_ request: URLRequest, completion: @escaping (Int?) -> Void) {
            lock.lock()
            requests.append(request)
            completions.append(completion)
            lock.unlock()
        }

        func respondNext(_ status: Int?) {
            lock.lock()
            let completion = completions.isEmpty ? nil : completions.removeFirst()
            lock.unlock()
            completion?(status)
        }

        func requestBodies() -> [[String: Any]] {
            lock.lock()
            let snapshot = requests
            lock.unlock()
            return snapshot.compactMap { request in
                guard let data = request.httpBody else { return nil }
                return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
        }
    }

    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var date: Date

        init(_ date: Date) { self.date = date }

        func now() -> Date {
            lock.lock()
            defer { lock.unlock() }
            return date
        }

        func set(_ newDate: Date) {
            lock.lock()
            date = newDate
            lock.unlock()
        }
    }

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "TelemetryServiceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testLaunchQueuesVersionedIdempotentFunnelBatchAndRemovesItOnlyAfterSuccess() throws {
        let recorder = TransportRecorder()
        let service = makeService(recorder: recorder)

        service.appLaunched(status: "trial")
        service.synchronizeForTesting()

        XCTAssertEqual(service.pendingEventCountForTesting(), 4)
        let events = try eventPayloads(in: recorder.requestBodies()).first ?? []
        XCTAssertEqual(Set(events.compactMap { $0["event"] as? String }), [
            "install", "trial_started", "app_version_first_seen", "launch",
        ])
        for event in events {
            XCTAssertEqual(event["schema_version"] as? Int, 3)
            XCTAssertNotNil(event["event_id"] as? String)
            XCTAssertNotNil(event["occurred_at"] as? String)
            XCTAssertNil(event["key_code"])
            XCTAssertNil(event["profile_name"])
            XCTAssertNil(event["controller_name"])
        }

        recorder.respondNext(200)
        service.synchronizeForTesting()
        XCTAssertEqual(service.pendingEventCountForTesting(), 0)

        service.appLaunched(status: "trial")
        service.synchronizeForTesting()
        XCTAssertEqual(service.pendingEventCountForTesting(), 0)
        XCTAssertEqual(recorder.requestBodies().count, 1, "Acknowledged markers must suppress duplicates")
    }

    func testRejectedMilestonesCanBeQueuedAgain() {
        let recorder = TransportRecorder()
        let service = makeService(recorder: recorder)

        service.appLaunched(status: "trial")
        service.synchronizeForTesting()
        recorder.respondNext(400)
        service.synchronizeForTesting()
        XCTAssertEqual(service.pendingEventCountForTesting(), 0)

        service.appLaunched(status: "trial")
        service.synchronizeForTesting()
        XCTAssertEqual(service.pendingEventCountForTesting(), 4)
        XCTAssertEqual(recorder.requestBodies().count, 2)
    }

    func testFailedDeliverySurvivesServiceRecreationAndRetriesWithSameEventIDs() throws {
        let firstRecorder = TransportRecorder()
        let firstService = makeService(recorder: firstRecorder)
        firstService.appLaunched(status: "trial")
        firstService.synchronizeForTesting()
        let originalIDs = try eventIDs(in: firstRecorder.requestBodies())

        firstRecorder.respondNext(503)
        firstService.synchronizeForTesting()
        XCTAssertEqual(firstService.pendingEventCountForTesting(), 4)

        defaults.set(0, forKey: "telemetryRetryAfter")
        let retryRecorder = TransportRecorder()
        let retryService = makeService(recorder: retryRecorder)
        retryService.appLaunched(status: "trial")
        retryService.synchronizeForTesting()
        XCTAssertEqual(try eventIDs(in: retryRecorder.requestBodies()), originalIDs)

        retryRecorder.respondNext(200)
        retryService.synchronizeForTesting()
        XCTAssertEqual(retryService.pendingEventCountForTesting(), 0)
    }

    func testDailyUseUploadsOnlyBucketsAndCoarseCategories() throws {
        let recorder = TransportRecorder()
        let clock = Clock(ISO8601DateFormatter().date(from: "2026-09-01T12:00:00Z")!)
        let service = makeService(recorder: recorder, clock: clock)
        service.appLaunched(status: "trial")
        service.synchronizeForTesting()
        recorder.respondNext(200)
        service.synchronizeForTesting()

        service.recordSuccessfulAction(category: .macro, isComplex: true)
        service.synchronizeForTesting()
        recorder.respondNext(200)
        service.synchronizeForTesting()
        for _ in 0..<5 {
            service.recordSuccessfulAction(category: .keyboard, isComplex: false)
        }

        clock.set(ISO8601DateFormatter().date(from: "2026-09-02T12:00:00Z")!)
        service.appLaunched(status: "trial")
        service.synchronizeForTesting()

        let events = try eventPayloads(in: recorder.requestBodies()).flatMap { $0 }
        let usefulDay = try XCTUnwrap(events.first { ($0["event"] as? String) == "useful_day" })
        XCTAssertEqual(usefulDay["client_day"] as? String, "2026-09-01")
        XCTAssertEqual(usefulDay["action_count_bucket"] as? String, "6-25")
        XCTAssertEqual(usefulDay["feature_categories"] as? [String], ["keyboard", "macro"])
        XCTAssertEqual(usefulDay["complex_action_used"] as? Bool, true)
    }

    func testOnboardingUsesOnlyCoarseOptionalDimensions() throws {
        let recorder = TransportRecorder()
        let service = makeService(recorder: recorder)

        service.onboardingStepReached(
            .inputMonitoring,
            accessibilityGranted: false,
            inputMonitoringGranted: false
        )
        service.onboardingCompleted(
            elapsedSeconds: 75,
            accessibilityGranted: true,
            inputMonitoringGranted: false,
            useCase: .couchControl
        )
        service.synchronizeForTesting()
        recorder.respondNext(200)
        service.synchronizeForTesting()

        let events = try eventPayloads(in: recorder.requestBodies()).flatMap { $0 }
        let step = try XCTUnwrap(events.first { ($0["event"] as? String) == "onboarding_step_reached" })
        XCTAssertEqual(step["onboarding_stage"] as? String, "input_monitoring")
        XCTAssertEqual(step["permission_state"] as? String, "accessibility_missing")

        let completed = try XCTUnwrap(events.first { ($0["event"] as? String) == "onboarding_completed" })
        XCTAssertEqual(completed["elapsed_time_bucket"] as? String, "1_to_2m")
        XCTAssertEqual(completed["permission_state"] as? String, "accessibility_only")
        XCTAssertEqual(completed["use_case"] as? String, "couch_control")
    }

    func testOptOutDeletesPendingEvents() {
        let recorder = TransportRecorder()
        let service = makeService(recorder: recorder)
        service.appLaunched(status: "trial")
        service.synchronizeForTesting()
        XCTAssertGreaterThan(service.pendingEventCountForTesting(), 0)

        defaults.set(false, forKey: "telemetryEnabled")
        service.preferenceChanged(enabled: false)
        service.synchronizeForTesting()
        XCTAssertEqual(service.pendingEventCountForTesting(), 0)
    }

    private func makeService(
        recorder: TransportRecorder,
        clock: Clock = Clock(ISO8601DateFormatter().date(from: "2026-09-02T12:00:00Z")!)
    ) -> TelemetryService {
        TelemetryService(
            defaults: defaults,
            now: clock.now,
            transport: recorder.send,
            runtimeAllowsTelemetry: { true },
            schedulesRetries: false
        )
    }

    private func eventPayloads(in bodies: [[String: Any]]) throws -> [[[String: Any]]] {
        try bodies.map { body in
            try XCTUnwrap(body["events"] as? [[String: Any]])
        }
    }

    private func eventIDs(in bodies: [[String: Any]]) throws -> [String] {
        try eventPayloads(in: bodies)
            .flatMap { $0 }
            .compactMap { $0["event_id"] as? String }
    }
}
