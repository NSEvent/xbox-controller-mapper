import Foundation

extension TelemetryService {
    struct DeliveryMarker: Equatable {
        enum Value: Equatable { case flag, string(String) }

        let key: String
        let value: Value

        func isDelivered(in defaults: UserDefaults) -> Bool {
            switch value {
            case .flag: return defaults.bool(forKey: key)
            case .string(let expected): return defaults.string(forKey: key) == expected
            }
        }

        func markDelivered(in defaults: UserDefaults) {
            switch value {
            case .flag: defaults.set(true, forKey: key)
            case .string(let value): defaults.set(value, forKey: key)
            }
        }
    }

    func onboardingStepReached(
        _ stage: OnboardingStage,
        accessibilityGranted: Bool,
        inputMonitoringGranted: Bool
    ) {
        enqueueMilestoneAsync(
            event: "onboarding_step_reached",
            marker: "telemetryOnboardingStep.\(stage.rawValue)",
            onboardingStage: stage.rawValue,
            permissionState: permissionState(
                accessibilityGranted: accessibilityGranted,
                inputMonitoringGranted: inputMonitoringGranted
            ).rawValue
        )
    }

    func onboardingCompleted(
        elapsedSeconds: TimeInterval,
        accessibilityGranted: Bool,
        inputMonitoringGranted: Bool,
        useCase: ProductUseCase?
    ) {
        enqueueMilestoneAsync(
            event: "onboarding_completed",
            marker: Key.didReportOnboarding,
            useCase: useCase?.rawValue,
            elapsedTimeBucket: ElapsedTimeBucket(seconds: elapsedSeconds).rawValue,
            permissionState: permissionState(
                accessibilityGranted: accessibilityGranted,
                inputMonitoringGranted: inputMonitoringGranted
            ).rawValue
        )
    }

    func trialWelcomeViewed() {
        enqueueMilestoneAsync(event: "trial_welcome_viewed", marker: Key.didReportTrialWelcome)
    }

    func controllerConnected(family: ControllerFamily) {
        enqueueMilestoneAsync(
            event: "controller_connected_first",
            marker: Key.didReportController,
            controllerFamily: family.rawValue
        )
    }

    func firstMappingReady(origin: ProfileOrigin, mappingKind: MappingKind) {
        enqueueMilestoneAsync(
            event: "first_mapping_ready",
            marker: Key.didReportMapping,
            profileOrigin: origin.rawValue,
            mappingKind: mappingKind.rawValue
        )
    }

    func paywallViewed(surface: String) {
        stateQueue.async { [weak self] in
            guard let self, self.canCollect else { return }
            let safeSurface = Self.safeDimension(surface)
            let marker = DeliveryMarker(
                key: "telemetryPaywallDay.\(safeSurface)",
                value: .string(Self.dayStamp(self.now()))
            )
            if self.enqueueTracked(event: "paywall_viewed", marker: marker, surface: safeSurface) {
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

    @discardableResult
    func enqueueMilestone(
        event: String,
        marker: String,
        status: String? = nil,
        controllerFamily: String? = nil,
        profileOrigin: String? = nil,
        mappingKind: String? = nil,
        useCase: String? = nil,
        onboardingStage: String? = nil,
        elapsedTimeBucket: String? = nil,
        permissionState: String? = nil
    ) -> Bool {
        enqueueTracked(
            event: event,
            marker: DeliveryMarker(key: marker, value: .flag),
            status: status,
            controllerFamily: controllerFamily,
            profileOrigin: profileOrigin,
            mappingKind: mappingKind,
            useCase: useCase,
            onboardingStage: onboardingStage,
            elapsedTimeBucket: elapsedTimeBucket,
            permissionState: permissionState
        )
    }

    @discardableResult
    func enqueueTracked(
        event: String,
        marker: DeliveryMarker,
        status: String? = nil,
        clientDay: String? = nil,
        surface: String? = nil,
        controllerFamily: String? = nil,
        profileOrigin: String? = nil,
        mappingKind: String? = nil,
        useCase: String? = nil,
        onboardingStage: String? = nil,
        elapsedTimeBucket: String? = nil,
        permissionState: String? = nil
    ) -> Bool {
        guard !marker.isDelivered(in: defaults) else { return false }
        guard !loadOutbox().contains(where: { deliveryMarker(for: $0) == marker }) else { return false }
        return enqueue(
            event: event,
            status: status,
            clientDay: clientDay,
            surface: surface,
            controllerFamily: controllerFamily,
            profileOrigin: profileOrigin,
            mappingKind: mappingKind,
            useCase: useCase,
            onboardingStage: onboardingStage,
            elapsedTimeBucket: elapsedTimeBucket,
            permissionState: permissionState
        )
    }

    func deliveryMarker(for event: QueuedEvent) -> DeliveryMarker? {
        let flagKey: String?
        switch event.event {
        case "install": flagKey = Key.didReportInstall
        case "trial_started": flagKey = Key.didReportTrialStarted
        case "trial_welcome_viewed": flagKey = Key.didReportTrialWelcome
        case "onboarding_completed": flagKey = Key.didReportOnboarding
        case "controller_connected_first": flagKey = Key.didReportController
        case "first_mapping_ready": flagKey = Key.didReportMapping
        case "first_action_succeeded": flagKey = Key.didReportFirstAction
        default: flagKey = nil
        }
        if let flagKey { return DeliveryMarker(key: flagKey, value: .flag) }

        switch event.event {
        case "app_version_first_seen":
            return DeliveryMarker(key: Key.lastReportedVersion, value: .string(event.appVersion))
        case "launch":
            guard let day = event.clientDay else { return nil }
            return DeliveryMarker(key: Key.lastLaunchDay, value: .string(day))
        case "trial_expired", "license_valid":
            return DeliveryMarker(key: Key.lastReportedStatus, value: .string(event.status))
        case "paywall_viewed":
            guard let surface = event.surface else { return nil }
            return DeliveryMarker(
                key: "telemetryPaywallDay.\(surface)",
                value: .string(String(event.occurredAt.prefix(10)))
            )
        case "onboarding_step_reached":
            guard let stage = event.onboardingStage else { return nil }
            return DeliveryMarker(key: "telemetryOnboardingStep.\(stage)", value: .flag)
        default:
            return nil
        }
    }

    private func enqueueMilestoneAsync(
        event: String,
        marker: String,
        controllerFamily: String? = nil,
        profileOrigin: String? = nil,
        mappingKind: String? = nil,
        useCase: String? = nil,
        onboardingStage: String? = nil,
        elapsedTimeBucket: String? = nil,
        permissionState: String? = nil
    ) {
        stateQueue.async { [weak self] in
            guard let self, self.canCollect else { return }
            if self.enqueueMilestone(
                event: event,
                marker: marker,
                controllerFamily: controllerFamily,
                profileOrigin: profileOrigin,
                mappingKind: mappingKind,
                useCase: useCase,
                onboardingStage: onboardingStage,
                elapsedTimeBucket: elapsedTimeBucket,
                permissionState: permissionState
            ) {
                self.flushOutboxIfNeeded()
            }
        }
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

    private func permissionState(
        accessibilityGranted: Bool,
        inputMonitoringGranted: Bool
    ) -> PermissionStateBucket {
        guard accessibilityGranted else { return .accessibilityMissing }
        return inputMonitoringGranted ? .accessibilityAndInput : .accessibilityOnly
    }
}
