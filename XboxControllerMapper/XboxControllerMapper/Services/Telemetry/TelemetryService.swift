import Foundation

/// Pseudonymous, opt-out product telemetry with a bounded persistent outbox.
///
/// Only coarse lifecycle, funnel, and daily aggregate-use signals leave the
/// Mac. Controller inputs, key codes, profile names, app names, scripts, URLs,
/// quick text, license keys, and device identifiers are never included.
final class TelemetryService: @unchecked Sendable {
    static let shared = TelemetryService()

    typealias Transport = (URLRequest, @escaping (Int?) -> Void) -> Void

    private enum Key {
        static let enabled = "telemetryEnabled"
        static let installID = "telemetryInstallID"
        static let installDate = "telemetryInstallDate"
        static let lastLaunchDay = "telemetryLastLaunchDay"
        static let didReportInstall = "telemetryDidReportInstall"
        static let didReportTrialStarted = "telemetryDidReportTrialStarted"
        static let didReportOnboarding = "telemetryDidReportOnboarding"
        static let didReportController = "telemetryDidReportController"
        static let didReportMapping = "telemetryDidReportMapping"
        static let didReportFirstAction = "telemetryDidReportFirstAction"
        static let lastReportedStatus = "telemetryLastReportedStatus"
        static let lastKnownStatus = "telemetryLastKnownStatus"
        static let lastReportedVersion = "telemetryLastReportedVersion"
        static let outbox = "telemetryOutboxV2"
        static let failureCount = "telemetryFailureCount"
        static let retryAfter = "telemetryRetryAfter"
        static let dailyUsage = "telemetryDailyUsageV2"
    }

    private let endpoint: URL
    private let defaults: UserDefaults
    private let now: () -> Date
    private let transport: Transport
    private let runtimeAllowsTelemetry: () -> Bool
    private let schedulesRetries: Bool
    private let stateQueue = DispatchQueue(label: "com.controllerkeys.telemetry", qos: .utility)
    private let usageLock = NSLock()
    private var dailyUsage: DailyUsage
    private var isSending = false
    private var retryWorkItem: DispatchWorkItem?

    init(
        endpoint: URL = defaultEndpoint,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        transport: Transport? = nil,
        runtimeAllowsTelemetry: @escaping () -> Bool = {
            !AppRuntime.isRunningTests && AppRuntime.screenshotVariant == nil
        },
        schedulesRetries: Bool = true
    ) {
        self.endpoint = endpoint
        self.defaults = defaults
        self.now = now
        self.runtimeAllowsTelemetry = runtimeAllowsTelemetry
        self.schedulesRetries = schedulesRetries
        self.transport = transport ?? Self.defaultTransport
        defaults.register(defaults: [Key.enabled: true])
        if let data = defaults.data(forKey: Key.dailyUsage),
           let stored = try? JSONDecoder().decode(DailyUsage.self, from: data) {
            dailyUsage = stored
        } else {
            dailyUsage = DailyUsage(day: Self.dayStamp(now()))
        }
    }

    /// Honors the Settings opt-out toggle.
    var isEnabled: Bool { defaults.bool(forKey: Key.enabled) }

    // MARK: - Public funnel API

    func appLaunched(status: String) {
        stateQueue.async { [weak self] in
            self?.handleAppLaunch(status: status)
        }
    }

    func onboardingCompleted() {
        enqueueMilestoneAsync(event: "onboarding_completed", marker: Key.didReportOnboarding)
    }

    func controllerConnected(family: ControllerFamily) {
        enqueueMilestoneAsync(
            event: "controller_connected_first",
            marker: Key.didReportController,
            controllerFamily: family.rawValue
        )
    }

    func firstMappingReady(origin: ProfileOrigin, workflow: MappingWorkflow) {
        enqueueMilestoneAsync(
            event: "first_mapping_ready",
            marker: Key.didReportMapping,
            profileOrigin: origin.rawValue,
            workflow: workflow.rawValue
        )
    }

    func paywallViewed(surface: String) {
        stateQueue.async { [weak self] in
            guard let self, self.canCollect else { return }
            let marker = "telemetryPaywallDay.\(Self.safeDimension(surface))"
            let today = Self.dayStamp(self.now())
            guard self.defaults.string(forKey: marker) != today else { return }
            if self.enqueue(event: "paywall_viewed", surface: Self.safeDimension(surface)) {
                self.defaults.set(today, forKey: marker)
                self.flushOutboxIfNeeded()
            }
        }
    }

    func checkoutOpened(surface: String) {
        enqueueAsync(event: "checkout_opened", surface: Self.safeDimension(surface))
    }

    func licenseActivated(saleID: String?) {
        stateQueue.async { [weak self] in
            guard let self, self.canCollect else { return }
            _ = self.enqueue(event: "license_activation_result", status: "licensed", result: "success")
            _ = self.enqueue(event: "license_activated", status: "licensed", saleID: saleID)
            self.flushOutboxIfNeeded()
        }
    }

    func licenseActivationFailed(_ category: ActivationErrorCategory) {
        enqueueAsync(
            event: "license_activation_result",
            result: "failure",
            errorCategory: category.rawValue
        )
    }

    /// Emits `trial_expired` / `license_valid` once per state transition.
    func reportStatusTransition(_ status: String) {
        stateQueue.async { [weak self] in
            guard let self, self.canCollect else { return }
            self.reportStatusTransitionLocked(status)
            self.flushOutboxIfNeeded()
        }
    }

    /// Hot-path safe: persists only when the coarse bucket/category changes.
    func recordSuccessfulAction(category: FeatureCategory, isComplex: Bool) {
        guard canCollect else { return }

        let currentDate = now()
        let currentDay = Self.dayStamp(currentDate)
        var completedDay: DailyUsage?
        var shouldCheckFirstAction = false

        usageLock.lock()
        if dailyUsage.day != currentDay {
            if dailyUsage.actionCount > 0 { completedDay = dailyUsage }
            dailyUsage = DailyUsage(day: currentDay)
        }
        let previousBucket = dailyUsage.actionCountBucket
        let insertedCategory = dailyUsage.categories.insert(category.rawValue).inserted
        let enabledComplex = isComplex && !dailyUsage.usedComplexAction
        shouldCheckFirstAction = dailyUsage.actionCount == 0
        dailyUsage.actionCount = min(101, dailyUsage.actionCount + 1)
        dailyUsage.usedComplexAction = dailyUsage.usedComplexAction || isComplex
        let changedBucket = previousBucket != dailyUsage.actionCountBucket
        if completedDay != nil || insertedCategory || enabledComplex || changedBucket || shouldCheckFirstAction {
            persistDailyUsageLocked()
        }
        usageLock.unlock()

        guard completedDay != nil || shouldCheckFirstAction else { return }
        stateQueue.async { [weak self] in
            guard let self, self.canCollect else { return }
            if let completedDay { _ = self.enqueueUsefulDay(completedDay) }
            if shouldCheckFirstAction {
                _ = self.enqueueMilestone(event: "first_action_succeeded", marker: Key.didReportFirstAction)
            }
            self.flushOutboxIfNeeded()
        }
    }

    /// Called when Settings changes the opt-out. Disabling drops unsent data.
    func preferenceChanged(enabled: Bool) {
        stateQueue.async { [weak self] in
            guard let self else { return }
            if enabled {
                self.flushOutboxIfNeeded()
            } else {
                self.retryWorkItem?.cancel()
                self.retryWorkItem = nil
                self.isSending = false
                self.defaults.removeObject(forKey: Key.outbox)
                self.defaults.removeObject(forKey: Key.failureCount)
                self.defaults.removeObject(forKey: Key.retryAfter)
                self.resetDailyUsage()
            }
        }
    }

    // MARK: - Launch and milestone bookkeeping

    private var canCollect: Bool { isEnabled && runtimeAllowsTelemetry() }

    private func handleAppLaunch(status: String) {
        guard canCollect else { return }
        defaults.set(status, forKey: Key.lastKnownStatus)
        if let completed = rollOverDailyUsageIfNeeded() { _ = enqueueUsefulDay(completed) }

        _ = enqueueMilestone(event: "install", marker: Key.didReportInstall, status: status)
        if status == "trial" {
            _ = enqueueMilestone(event: "trial_started", marker: Key.didReportTrialStarted, status: status)
        }

        if defaults.string(forKey: Key.lastReportedVersion) != Self.appVersion,
           enqueue(event: "app_version_first_seen", status: status) {
            defaults.set(Self.appVersion, forKey: Key.lastReportedVersion)
        }

        let today = Self.dayStamp(now())
        if defaults.string(forKey: Key.lastLaunchDay) != today,
           enqueue(event: "launch", status: status, clientDay: today) {
            defaults.set(today, forKey: Key.lastLaunchDay)
        }

        reportStatusTransitionLocked(status)
        flushOutboxIfNeeded()
    }

    private func reportStatusTransitionLocked(_ status: String) {
        defaults.set(status, forKey: Key.lastKnownStatus)
        guard defaults.string(forKey: Key.lastReportedStatus) != status else { return }
        let event: String?
        switch status {
        case "expired": event = "trial_expired"
        case "licensed": event = "license_valid"
        default: event = nil
        }
        guard let event, enqueue(event: event, status: status) else { return }
        defaults.set(status, forKey: Key.lastReportedStatus)
    }

    private func enqueueMilestoneAsync(
        event: String,
        marker: String,
        controllerFamily: String? = nil,
        profileOrigin: String? = nil,
        workflow: String? = nil
    ) {
        stateQueue.async { [weak self] in
            guard let self, self.canCollect else { return }
            if self.enqueueMilestone(
                event: event,
                marker: marker,
                controllerFamily: controllerFamily,
                profileOrigin: profileOrigin,
                workflow: workflow
            ) {
                self.flushOutboxIfNeeded()
            }
        }
    }

    @discardableResult
    private func enqueueMilestone(
        event: String,
        marker: String,
        status: String? = nil,
        controllerFamily: String? = nil,
        profileOrigin: String? = nil,
        workflow: String? = nil
    ) -> Bool {
        guard !defaults.bool(forKey: marker) else { return false }
        guard enqueue(
            event: event,
            status: status,
            controllerFamily: controllerFamily,
            profileOrigin: profileOrigin,
            workflow: workflow
        ) else { return false }
        defaults.set(true, forKey: marker)
        return true
    }

    private func enqueueAsync(
        event: String,
        surface: String? = nil,
        result: String? = nil,
        errorCategory: String? = nil
    ) {
        stateQueue.async { [weak self] in
            guard let self, self.canCollect else { return }
            if self.enqueue(event: event, surface: surface, result: result, errorCategory: errorCategory) {
                self.flushOutboxIfNeeded()
            }
        }
    }

    // MARK: - Daily aggregate

    private func rollOverDailyUsageIfNeeded() -> DailyUsage? {
        let today = Self.dayStamp(now())
        usageLock.lock()
        defer { usageLock.unlock() }
        guard dailyUsage.day != today else { return nil }
        let completed = dailyUsage.actionCount > 0 ? dailyUsage : nil
        dailyUsage = DailyUsage(day: today)
        persistDailyUsageLocked()
        return completed
    }

    private func enqueueUsefulDay(_ usage: DailyUsage) -> Bool {
        enqueue(
            event: "useful_day",
            occurredAt: "\(usage.day)T23:59:59Z",
            clientDay: usage.day,
            actionCountBucket: usage.actionCountBucket,
            featureCategories: usage.categories.sorted(),
            complexActionUsed: usage.usedComplexAction
        )
    }

    private func persistDailyUsageLocked() {
        guard let data = try? JSONEncoder().encode(dailyUsage) else { return }
        defaults.set(data, forKey: Key.dailyUsage)
    }

    private func resetDailyUsage() {
        usageLock.lock()
        dailyUsage = DailyUsage(day: Self.dayStamp(now()))
        persistDailyUsageLocked()
        usageLock.unlock()
    }

    // MARK: - Durable outbox

    @discardableResult
    private func enqueue(
        event: String,
        occurredAt: String? = nil,
        status: String? = nil,
        saleID: String? = nil,
        clientDay: String? = nil,
        surface: String? = nil,
        controllerFamily: String? = nil,
        profileOrigin: String? = nil,
        workflow: String? = nil,
        actionCountBucket: String? = nil,
        featureCategories: [String]? = nil,
        complexActionUsed: Bool? = nil,
        result: String? = nil,
        errorCategory: String? = nil
    ) -> Bool {
        guard canCollect else { return false }
        let date = now()
        let payload = QueuedEvent(
            event: event,
            eventID: UUID().uuidString,
            occurredAt: occurredAt ?? Self.iso8601(date),
            schemaVersion: Self.schemaVersion,
            installID: installID,
            appVersion: Self.appVersion,
            build: Self.build,
            osVersion: Self.osVersion,
            arch: Self.arch,
            locale: Locale.current.identifier,
            status: status ?? defaults.string(forKey: Key.lastKnownStatus) ?? "trial",
            trialDay: trialDay(at: date),
            channel: Self.channel,
            saleID: saleID?.isEmpty == false ? saleID : nil,
            funnelVersion: Self.funnelVersion,
            offerVersion: Self.offerVersion,
            clientDay: clientDay,
            surface: surface,
            controllerFamily: controllerFamily,
            profileOrigin: profileOrigin,
            workflow: workflow,
            actionCountBucket: actionCountBucket,
            featureCategories: featureCategories,
            complexActionUsed: complexActionUsed,
            result: result,
            errorCategory: errorCategory
        )

        var events = loadOutbox()
        if events.count >= Self.maximumOutboxCount {
            let lowPriority = Set(["launch", "useful_day", "app_version_first_seen"])
            if let index = events.firstIndex(where: { lowPriority.contains($0.event) }) {
                events.remove(at: index)
            } else {
                events.removeFirst()
            }
        }
        events.append(payload)
        return saveOutbox(events)
    }

    private func flushOutboxIfNeeded() {
        guard canCollect, !isSending else { return }
        let retryAfter = defaults.double(forKey: Key.retryAfter)
        let delay = retryAfter - now().timeIntervalSince1970
        if delay > 0 {
            scheduleRetry(after: delay)
            return
        }

        let outbox = loadOutbox()
        guard !outbox.isEmpty else { return }
        let batch = Array(outbox.prefix(Self.batchSize))
        guard let body = try? JSONEncoder().encode(EventBatch(events: batch)) else { return }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        request.httpBody = body
        isSending = true

        transport(request) { [weak self] statusCode in
            self?.stateQueue.async { [weak self] in
                self?.handleSendResult(statusCode: statusCode, batch: batch)
            }
        }
    }

    private func handleSendResult(statusCode: Int?, batch: [QueuedEvent]) {
        isSending = false
        guard canCollect else { return }
        if let statusCode, (200..<300).contains(statusCode) {
            let sentIDs = Set(batch.map(\.eventID))
            var outbox = loadOutbox()
            outbox.removeAll { sentIDs.contains($0.eventID) }
            _ = saveOutbox(outbox)
            defaults.removeObject(forKey: Key.failureCount)
            defaults.removeObject(forKey: Key.retryAfter)
            retryWorkItem?.cancel()
            retryWorkItem = nil
            flushOutboxIfNeeded()
            return
        }

        if statusCode == 400 || statusCode == 413 {
            let rejectedIDs = Set(batch.map(\.eventID))
            var outbox = loadOutbox()
            outbox.removeAll { rejectedIDs.contains($0.eventID) }
            _ = saveOutbox(outbox)
            NSLog("[Telemetry] Backend rejected %ld queued events with HTTP %ld", batch.count, statusCode ?? 0)
            flushOutboxIfNeeded()
            return
        }

        let failures = min(defaults.integer(forKey: Key.failureCount) + 1, Self.retryDelays.count)
        let delay = Self.retryDelays[max(0, failures - 1)]
        defaults.set(failures, forKey: Key.failureCount)
        defaults.set(now().addingTimeInterval(delay).timeIntervalSince1970, forKey: Key.retryAfter)
        scheduleRetry(after: delay)
    }

    private func scheduleRetry(after delay: TimeInterval) {
        guard schedulesRetries else { return }
        retryWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.flushOutboxIfNeeded()
        }
        retryWorkItem = item
        stateQueue.asyncAfter(deadline: .now() + max(0.1, delay), execute: item)
    }

    private func loadOutbox() -> [QueuedEvent] {
        guard let data = defaults.data(forKey: Key.outbox),
              let events = try? JSONDecoder().decode([QueuedEvent].self, from: data) else { return [] }
        return events
    }

    private func saveOutbox(_ events: [QueuedEvent]) -> Bool {
        guard let data = try? JSONEncoder().encode(events) else { return false }
        defaults.set(data, forKey: Key.outbox)
        return true
    }

    // MARK: - Pseudonymous environment

    private var installID: String {
        if let existing = defaults.string(forKey: Key.installID) { return existing }
        let id = UUID().uuidString
        defaults.set(id, forKey: Key.installID)
        defaults.set(now().timeIntervalSince1970, forKey: Key.installDate)
        return id
    }

    private func trialDay(at date: Date) -> Int {
        let firstLaunch = defaults.double(forKey: Key.installDate)
        guard firstLaunch > 0 else { return 0 }
        return max(0, Int((date.timeIntervalSince1970 - firstLaunch) / 86_400))
    }

    // MARK: - Test synchronization

    func synchronizeForTesting() {
        stateQueue.sync {}
    }

    func pendingEventCountForTesting() -> Int {
        stateQueue.sync { loadOutbox().count }
    }
}
