import Combine
import CommonCrypto
import CoreBluetooth
import CoreGraphics
import Foundation

final class OuraRingCommandCenter {
	static let shared = OuraRingCommandCenter()

	private let lock = NSLock()
	private var centerHandler: (() -> Void)?
	private var toggleMotionHandler: (() -> Void)?

	private init() {}

	func install(center: @escaping () -> Void, toggleMotion: @escaping () -> Void) {
		lock.lock()
		centerHandler = center
		toggleMotionHandler = toggleMotion
		lock.unlock()
	}

	func centerRing() -> Bool {
		lock.lock()
		let handler = centerHandler
		lock.unlock()
		return run(handler)
	}

	func toggleMotionOutput() -> Bool {
		lock.lock()
		let handler = toggleMotionHandler
		lock.unlock()
		return run(handler)
	}

	private func run(_ handler: (() -> Void)?) -> Bool {
		guard let handler else { return false }
		DispatchQueue.main.async(execute: handler)
		return true
	}
}

enum OuraRingConnectionStatus: Equatable {
	case disabled
	case bluetoothUnavailable(String)
	case scanning
	case connecting(String)
	case connected(String)
	case adopting
	case authenticating
	case authenticated(String)
	case authFailed(String)
	case disconnected

	var displayName: String {
		switch self {
		case .disabled: return "Disabled"
		case .bluetoothUnavailable(let reason): return "Bluetooth unavailable: \(reason)"
		case .scanning: return "Scanning"
		case .connecting(let name): return "Connecting to \(name)"
		case .connected(let name): return "Connected to \(name)"
		case .adopting: return "Adopting reset ring"
		case .authenticating: return "Authenticating"
		case .authenticated(let name): return "Authenticated: \(name)"
		case .authFailed(let reason): return "Auth failed: \(reason)"
		case .disconnected: return "Disconnected"
		}
	}
}

private extension CBPeripheralState {
	var diagnosticName: String {
		switch self {
		case .disconnected:
			return "disconnected"
		case .connecting:
			return "connecting"
		case .connected:
			return "connected"
		case .disconnecting:
			return "disconnecting"
		@unknown default:
			return "unknown"
		}
	}
}

@MainActor
final class OuraRingInputService: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
	@Published private(set) var status: OuraRingConnectionStatus = .disabled
	@Published private(set) var lastDiagnosticLine: String = ""

	private let controllerService: ControllerService
	private let profileManager: ProfileManager
	private var cancellables = Set<AnyCancellable>()

	private var centralManager: CBCentralManager?
	private var peripheral: CBPeripheral?
	private var writeCharacteristic: CBCharacteristic?
	private var notifyCharacteristic: CBCharacteristic?
	private var currentSettings: OuraMotionSettings = .default
	private var motionMapper = OuraMotionMapper(settings: .default)
	private var tapDetector = OuraTapDetector()
	private var authKey: Data?
	private var pendingAdoptionKey: Data?
	private var tapReleaseWorkItem: DispatchWorkItem?
	private var tapSequenceWorkItem: DispatchWorkItem?
	private var connectTimeoutWorkItem: DispatchWorkItem?
	private var realtimeRefreshTimer: Timer?
	private var tapSequence = OuraTapSequenceRecognizer()
	private var tapMotionSuppressor = OuraTapMotionSuppressor()
	private var tapHoldRecognizer = OuraTapHoldRecognizer()
	private var flickRecognizer = OuraDirectionalFlickRecognizer()
	private var isMigratingLegacyDeadzone = false
	private var connectAttemptStartTime: CFAbsoluteTime?
	private var lastAccelerometerTapTime: CFAbsoluteTime = 0
	private var lastMotionDiagnosticTime: CFAbsoluteTime = 0
	private var suppressTapDetectionUntil: CFAbsoluteTime = 0
	private let motionTrace = OuraMotionTraceWriter()

	// ML gesture-event path (OuraGestureEventClassifier.swift); falls back to
	// the heuristic recognizers until the model loads or when the
	// ouraGestureClassifierDisabled default is set.
	private var streamingActivity: NSObjectProtocol?
	private var motionWatchdogTimer: Timer?
	private var lastMotionSampleWallTime: CFAbsoluteTime = 0
	private let gestureClassifier = OuraGestureEventClassifier()
	private var motionWindowBuffer = OuraMotionWindowBuffer()
	private var impulseDetector = OuraImpulseDetector()
	private var pendingClassificationPeaks: [CFAbsoluteTime] = []
	private var flickClassificationCooldownUntil: CFAbsoluteTime = 0
	private var tapHoldFedThrough: CFAbsoluteTime = -.greatestFiniteMagnitude
	private let flickClassificationCooldown: CFTimeInterval = 0.65
	private let flickConfidenceThreshold = 0.5
	private var useMLGesturePath: Bool {
		gestureClassifier.isAvailable &&
			!UserDefaults.standard.bool(forKey: "ouraGestureClassifierDisabled")
	}

	private let keychainService = "com.controllerkeys.oura-ring"
	private let authKeyAccount = "oura-auth-key-v1"
	private let legacyDefaultDeadzone = 0.08
	private let connectAttemptTimeout: CFTimeInterval = 20.0
	private let realtimeAccelerometerDurationMinutes: UInt16 = 10
	private let realtimeRefreshInterval: TimeInterval = 9 * 60
	private let tapMotionSuppressionDuration = OuraTapSequenceRecognizer.sequenceWindow + 0.20
	private let tapMotionPostActionSuppressionDuration: CFTimeInterval = 0.18
	private let accelerometerTapRefractory: CFTimeInterval = 0.16
	private var loggedNearbyPeripheralIDs: Set<UUID> = []
	private var diagnosticLogURL: URL {
		FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent("Library", isDirectory: true)
			.appendingPathComponent("Logs", isDirectory: true)
			.appendingPathComponent("ControllerKeys-Oura.log")
	}

	init(controllerService: ControllerService, profileManager: ProfileManager) {
		self.controllerService = controllerService
		self.profileManager = profileManager
		super.init()

		OuraRingCommandCenter.shared.install(
			center: { [weak self] in self?.resetMotionCenter() },
			toggleMotion: { [weak self] in self?.toggleMotionOutputEnabled() }
		)

		profileManager.$activeProfile
			.map { $0?.joystickSettings.ouraMotion ?? .default }
			.removeDuplicates()
			.sink { [weak self] settings in
				self?.apply(settings)
			}
			.store(in: &cancellables)
	}

	func startIfEnabled() {
		guard currentSettings.enabled, !AppRuntime.isRunningTests else { return }
		gestureClassifier.loadIfNeeded()
		if centralManager == nil {
			centralManager = CBCentralManager(delegate: self, queue: .main)
		} else if centralManager?.state == .poweredOn {
			scanForRing()
		}
	}

	func stop() {
		stopInternal(status: .disabled)
	}

	func forgetRingKeyAndReconnect() {
		KeychainService.deletePassword(key: authKeyAccount, service: keychainService)
		authKey = nil
		pendingAdoptionKey = nil
		appendDiagnostic("forgot stored Oura auth key")
		if currentSettings.enabled {
			stopInternal(status: .disconnected)
			startIfEnabled()
		}
	}

	func resetMotionCenter() {
		tapSequenceWorkItem?.cancel()
		tapSequenceWorkItem = nil
		tapSequence.reset()
		tapHoldRecognizer.reset()
		flickRecognizer.reset()
		motionMapper.reset()
		tapDetector.reset()
		// Deliberately NOT resetMLGestureState(): the window buffer and
		// impulse detector track raw motion, which recentering doesn't change,
		// and clearing them blacks out detection for ~1.4s after every
		// recenter (Kevin recenters constantly during normal use). The 0.75s
		// center suppression below already guards against the recenter jolt.
		pendingClassificationPeaks.removeAll()
		releaseOuraMotionSticks()
		appendDiagnostic("motion center will reset on next accelerometer sample")
	}

	func setMotionOutputEnabled(_ enabled: Bool) {
		guard var newSettings = profileManager.activeProfile?.joystickSettings else { return }
		guard newSettings.ouraMotion.motionOutputEnabled != enabled else {
			if !enabled {
				releaseOuraMotionSticks()
			}
			return
		}
		newSettings.ouraMotion.motionOutputEnabled = enabled
		profileManager.updateJoystickSettings(newSettings)
		if !enabled {
			releaseOuraMotionSticks()
		}
	}

	func toggleMotionOutputEnabled() {
		setMotionOutputEnabled(!currentSettings.motionOutputEnabled)
		resetMotionCenter()
	}

	func pauseMotionOutput() {
		setMotionOutputEnabled(false)
	}

	private func apply(_ settings: OuraMotionSettings) {
		if shouldMigrateLegacyDeadzone(settings) {
			migrateLegacyDeadzone()
			return
		}

		let oldSettings = currentSettings
		currentSettings = settings
		motionMapper.settings = settings
		if oldSettings.enabled != settings.enabled || oldSettings.targetStick != settings.targetStick {
			resetMotionCenter()
		} else if oldSettings.motionOutputEnabled != settings.motionOutputEnabled {
			releaseOuraMotionSticks()
			appendDiagnostic(settings.motionOutputEnabled ? "motion output resumed" : "motion output paused")
		}
		if settings.enabled {
			startIfEnabled()
		} else {
			stopInternal(status: .disabled)
		}
	}

	private func shouldMigrateLegacyDeadzone(_ settings: OuraMotionSettings) -> Bool {
		settings.enabled &&
			!isMigratingLegacyDeadzone &&
			abs(settings.deadzone - legacyDefaultDeadzone) < 0.000_001
	}

	private func migrateLegacyDeadzone() {
		guard var newSettings = profileManager.activeProfile?.joystickSettings else { return }
		isMigratingLegacyDeadzone = true
		newSettings.ouraMotion.deadzone = OuraMotionSettings.default.deadzone
		profileManager.updateJoystickSettings(newSettings)
		isMigratingLegacyDeadzone = false
		appendDiagnostic("migrated Oura deadzone to \(String(format: "%.2f", OuraMotionSettings.default.deadzone))")
	}

	private func stopInternal(status newStatus: OuraRingConnectionStatus) {
		tapReleaseWorkItem?.cancel()
		tapReleaseWorkItem = nil
		tapSequenceWorkItem?.cancel()
		tapSequenceWorkItem = nil
		clearConnectAttempt()
		realtimeRefreshTimer?.invalidate()
		realtimeRefreshTimer = nil
		endStreamingActivity()
		stopMotionWatchdog()
		tapSequence.reset()
		tapMotionSuppressor.reset()
		tapHoldRecognizer.reset()
		flickRecognizer.reset()
		motionMapper.reset()
		tapDetector.reset()
		resetMLGestureState()
		releaseOuraMotionSticks()
		releaseOuraGestureButtons()
		controllerService.setOuraRingConnected(false)

		if centralManager?.isScanning == true {
			centralManager?.stopScan()
		}
		if peripheral != nil, writeCharacteristic != nil {
			write(OuraRingProtocol.stopRealtimeCommand())
		}
		if let peripheral {
			centralManager?.cancelPeripheralConnection(peripheral)
		}
		peripheral = nil
		writeCharacteristic = nil
		notifyCharacteristic = nil
		status = newStatus
	}

	private func scanForRing() {
		guard currentSettings.enabled, let centralManager, centralManager.state == .poweredOn else { return }

		let connected = centralManager.retrieveConnectedPeripherals(withServices: [OuraRingProtocol.serviceUUID])
		if let ring = connected.first {
			appendDiagnostic("using already-connected Oura service peripheral \(displayName(for: ring))")
			connect(to: ring)
			return
		}

		status = .scanning
		loggedNearbyPeripheralIDs.removeAll()
		appendDiagnostic("scanning for Oura ring by advertised service or local name")
		centralManager.scanForPeripherals(
			withServices: nil,
			options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
		)
	}

	private func connect(to peripheral: CBPeripheral) {
		let now = CFAbsoluteTimeGetCurrent()
		if let existingPeripheral = self.peripheral,
		   existingPeripheral.identifier == peripheral.identifier {
			switch existingPeripheral.state {
			case .connected:
				appendDiagnostic("already connected to Oura candidate \(displayName(for: existingPeripheral))")
				return
			case .connecting where !connectionAttemptTimedOut(now: now):
				appendDiagnostic("already connecting to Oura candidate \(displayName(for: existingPeripheral))")
				return
			case .connecting:
				appendDiagnostic("retrying stale Oura connection to \(displayName(for: peripheral))")
				centralManager?.cancelPeripheralConnection(existingPeripheral)
				clearConnectAttempt()
			case .disconnecting:
				appendDiagnostic("retrying after disconnecting Oura peripheral \(displayName(for: peripheral))")
				centralManager?.cancelPeripheralConnection(existingPeripheral)
			case .disconnected:
				appendDiagnostic("retrying disconnected Oura peripheral \(displayName(for: peripheral))")
			@unknown default:
				appendDiagnostic("retrying unknown-state Oura peripheral \(displayName(for: peripheral))")
			}
			self.peripheral = nil
		} else if let existingPeripheral = self.peripheral {
			switch existingPeripheral.state {
			case .connected:
				appendDiagnostic(
					"ignored Oura candidate while connected \(displayName(for: existingPeripheral))"
				)
				return
			case .connecting where !connectionAttemptTimedOut(now: now):
				appendDiagnostic(
					"ignored Oura candidate while connecting \(displayName(for: existingPeripheral))"
				)
				return
			case .connecting:
				appendDiagnostic("replacing stale connecting Oura peripheral with \(displayName(for: peripheral))")
				centralManager?.cancelPeripheralConnection(existingPeripheral)
				clearConnectAttempt()
				self.peripheral = nil
			case .disconnecting:
				appendDiagnostic("replacing disconnecting Oura peripheral with \(displayName(for: peripheral))")
				centralManager?.cancelPeripheralConnection(existingPeripheral)
				self.peripheral = nil
			case .disconnected:
				appendDiagnostic("replacing stale Oura peripheral with \(displayName(for: peripheral))")
				self.peripheral = nil
			@unknown default:
				appendDiagnostic("replacing unknown-state Oura peripheral with \(displayName(for: peripheral))")
				self.peripheral = nil
			}
		}
		self.peripheral = peripheral
		peripheral.delegate = self
		status = .connecting(displayName(for: peripheral))
		centralManager?.stopScan()
		appendDiagnostic("connecting to Oura candidate \(displayName(for: peripheral))")
		connectAttemptStartTime = now
		scheduleConnectTimeout(for: peripheral)
		centralManager?.connect(peripheral, options: nil)
	}

	private func connectionAttemptTimedOut(now: CFAbsoluteTime) -> Bool {
		guard let connectAttemptStartTime else { return false }
		return now - connectAttemptStartTime >= connectAttemptTimeout
	}

	private func clearConnectAttempt() {
		connectTimeoutWorkItem?.cancel()
		connectTimeoutWorkItem = nil
		connectAttemptStartTime = nil
	}

	private func scheduleConnectTimeout(for peripheral: CBPeripheral) {
		connectTimeoutWorkItem?.cancel()
		let peripheralID = peripheral.identifier
		let peripheralName = displayName(for: peripheral)
		let workItem = DispatchWorkItem { [weak self, weak peripheral] in
			guard let self else { return }
			guard self.peripheral?.identifier == peripheralID,
			      self.peripheral?.state == .connecting else { return }

			self.appendDiagnostic("connect timeout for Oura candidate \(peripheralName); restarting scan")
			if let peripheral {
				self.centralManager?.cancelPeripheralConnection(peripheral)
			}
			self.clearConnectAttempt()
			self.peripheral = nil
			self.status = .disconnected
			if self.currentSettings.enabled {
				self.scanForRing()
			}
		}
		connectTimeoutWorkItem = workItem
		DispatchQueue.main.asyncAfter(deadline: .now() + connectAttemptTimeout, execute: workItem)
	}

	private func authenticateOrAdopt() {
		guard writeCharacteristic != nil else { return }
		if let key = loadAuthKey() {
			authKey = key
			status = .authenticating
			write(OuraRingProtocol.nonceCommand())
			return
		}

		guard currentSettings.adoptResetRing else {
			status = .authFailed("no stored key; reset the ring or enable reset-ring adoption")
			return
		}

		guard let newKey = OuraRingProtocol.newAuthKey() else {
			status = .authFailed("could not generate auth key")
			return
		}

		pendingAdoptionKey = newKey
		status = .adopting
		write(OuraRingProtocol.installKeyCommand(newKey))
	}

	private func finishAuthentication(peripheral: CBPeripheral) {
		status = .authenticated(displayName(for: peripheral))
		controllerService.setOuraRingConnected(true)
		write(OuraRingProtocol.enableNotificationsCommand())
		write(OuraRingProtocol.readFeatureCommand(OuraRingProtocol.tapToTagFeature))
		write(OuraRingProtocol.enableFeatureCommand(OuraRingProtocol.tapToTagFeature, value: 0x03))
		write(OuraRingProtocol.subscribeFeatureCommand(OuraRingProtocol.tapToTagFeature, value: 0x02))
		startRealtimeAccelerometer()
	}

	private func write(_ data: Data) {
		guard let peripheral, let writeCharacteristic else { return }
		appendDiagnostic("tx \(data.ouraHexString)")
		peripheral.writeValue(data, for: writeCharacteristic, type: .withoutResponse)
	}

	private func startRealtimeAccelerometer() {
		write(OuraRingProtocol.startAccelerometerCommand(durationMinutes: realtimeAccelerometerDurationMinutes))
		realtimeRefreshTimer?.invalidate()
		realtimeRefreshTimer = Timer.scheduledTimer(withTimeInterval: realtimeRefreshInterval, repeats: true) { [weak self] _ in
			Task { @MainActor in
				guard let self, self.currentSettings.enabled, self.writeCharacteristic != nil else { return }
				self.write(OuraRingProtocol.startAccelerometerCommand(durationMinutes: self.realtimeAccelerometerDurationMinutes))
			}
		}
		if let realtimeRefreshTimer {
			RunLoop.main.add(realtimeRefreshTimer, forMode: .common)
		}
		beginStreamingActivity()
		startMotionWatchdog()
	}

	// App Nap freezes BLE delivery and the realtime-refresh timer as soon as
	// ControllerKeys is not the active app — the ring's cursor/gestures die
	// until the app is foregrounded again (observed 2026-07-06: trace went
	// from ~50 samples/s to 0 the moment another app took focus). Hold a
	// user-initiated activity while the ring streams; allow idle system sleep.
	private func beginStreamingActivity() {
		guard streamingActivity == nil else { return }
		streamingActivity = ProcessInfo.processInfo.beginActivity(
			options: .userInitiatedAllowingIdleSystemSleep,
			reason: "Oura ring realtime motion streaming"
		)
	}

	private func endStreamingActivity() {
		if let streamingActivity {
			ProcessInfo.processInfo.endActivity(streamingActivity)
			self.streamingActivity = nil
		}
	}

	// If the stream dies mid-deflection (BLE dropout, ring sleep), the virtual
	// stick would stay latched at its last value and the cursor drifts
	// forever. Watchdog releases the sticks when samples stop arriving.
	private func startMotionWatchdog() {
		guard motionWatchdogTimer == nil else { return }
		let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
			Task { @MainActor in
				guard let self else { return }
				guard self.lastMotionSampleWallTime > 0,
				      CFAbsoluteTimeGetCurrent() - self.lastMotionSampleWallTime > 1.2 else { return }
				self.lastMotionSampleWallTime = 0
				self.releaseOuraMotionSticks()
				self.appendDiagnostic("motion stream stalled — sticks released by watchdog")
			}
		}
		RunLoop.main.add(timer, forMode: .common)
		motionWatchdogTimer = timer
	}

	private func stopMotionWatchdog() {
		motionWatchdogTimer?.invalidate()
		motionWatchdogTimer = nil
		lastMotionSampleWallTime = 0
	}

	private func releaseOuraMotionSticks() {
		for side in JoystickSide.allCases {
			controllerService.updateOuraRingStick(.zero, side: side)
		}
	}

	private func releaseOuraGestureButtons() {
		for button in ControllerButton.ouraRingButtons {
			controllerService.handleButton(button, pressed: false)
		}
	}

	private func handle(_ event: OuraRingDecodedEvent, from peripheral: CBPeripheral) {
		switch event {
		case .nonce(let nonce):
			guard let authKey, let command = OuraRingProtocol.authProofCommand(nonce: nonce, key: authKey) else {
				status = .authFailed("could not build auth proof")
				return
			}
			write(command)
		case .authStatus(let authStatus):
			switch authStatus {
			case .success:
				finishAuthentication(peripheral: peripheral)
			case .inFactoryReset where currentSettings.adoptResetRing:
				guard let newKey = OuraRingProtocol.newAuthKey() else {
					status = .authFailed("could not generate reset-ring key")
					return
				}
				pendingAdoptionKey = newKey
				status = .adopting
				write(OuraRingProtocol.installKeyCommand(newKey))
			case .wrongKey, .inFactoryReset, .notOriginalDevice:
				status = .authFailed(authStatus.displayName)
			}
		case .keyInstallStatus(let success):
			guard success, let key = pendingAdoptionKey else {
				status = .authFailed("ring rejected auth key install")
				return
			}
			saveAuthKey(key)
			authKey = key
			pendingAdoptionKey = nil
			status = .authenticating
			write(OuraRingProtocol.nonceCommand())
		case .tap:
			handleTapCandidate(at: CFAbsoluteTimeGetCurrent(), source: "tap feature")
		case .motion(let sample):
			applyMotion(sample)
		case .unknown(let hex):
			appendDiagnostic("rx unknown \(hex)")
		}
	}

	private func applyMotion(_ sample: OuraMotionSample) {
		lastMotionSampleWallTime = CFAbsoluteTimeGetCurrent()
		let result = motionMapper.mappingResult(forRawSample: sample)
		if result.didEstablishCenter {
			appendDiagnostic(String(format: "motion center %.2f %.2f %.2f", sample.x, sample.y, sample.z))
		}

		let centeredSample = result.centeredSample
		let projectedInput = result.projectedInput
		let stick = result.stick
		motionTrace.recordSample(sample, projected: projectedInput)
		if result.didEstablishCenter {
			suppressTapDetectionUntil = max(suppressTapDetectionUntil, sample.timestamp + 0.75)
			motionTrace.recordEvent("center", timestamp: sample.timestamp)
		}
		if useMLGesturePath {
			applyMotionGesturesML(sample, projectedInput: projectedInput)
		} else {
			let detectedTap = sample.timestamp >= suppressTapDetectionUntil && tapDetector.register(sample)
			if detectedTap {
				motionTrace.recordEvent("tap-detected", timestamp: sample.timestamp)
			}
			if detectedTap {
				handleAccelerometerTapCandidate(at: sample.timestamp, sample: sample)
			} else {
				handleTapHoldCandidate(sample)
				handleDirectionalFlickCandidate(projectedInput: projectedInput, timestamp: sample.timestamp)
			}
		}
		let outputStick = tapMotionSuppressor.isSuppressed(at: sample.timestamp) ? .zero : stick
		controllerService.updateOuraRingStick(outputStick, side: currentSettings.targetStick)

		if sample.timestamp - lastMotionDiagnosticTime > 0.25 {
			lastMotionDiagnosticTime = sample.timestamp
			appendDiagnostic(String(
				format: "motion raw %.2f %.2f %.2f centered %.2f %.2f %.2f input %.2f %.2f stick %.2f %.2f",
				sample.x, sample.y, sample.z,
				centeredSample.x, centeredSample.y, centeredSample.z,
				projectedInput.x, projectedInput.y,
				outputStick.x, outputStick.y
			))
		}
	}

	private func handleAccelerometerTapCandidate(at timestamp: CFAbsoluteTime, sample: OuraMotionSample?) {
		guard timestamp - lastAccelerometerTapTime > accelerometerTapRefractory else { return }

		lastAccelerometerTapTime = timestamp
		handleTapCandidate(at: timestamp, source: "accelerometer spike", sample: sample)
	}

	private func handleTapCandidate(at timestamp: CFAbsoluteTime, source: String, sample: OuraMotionSample? = nil) {
		motionTrace.recordEvent("tap-candidate", detail: source, timestamp: timestamp)
		switch tapSequence.registerTap(at: timestamp) {
		case .duplicate:
			return
		case .pending(let count):
			if count == 1 {
				tapHoldRecognizer.registerTap(at: timestamp, sample: sample)
			} else {
				tapHoldRecognizer.cancel()
			}
			suppressMotionForTap(at: timestamp, duration: tapMotionSuppressionDuration)
			appendDiagnostic("\(count)x tap pending from \(source)")
			scheduleTapSequenceResolution()
		case .completed(let count):
			tapHoldRecognizer.cancel()
			tapSequenceWorkItem?.cancel()
			tapSequenceWorkItem = nil
			suppressMotionForTap(at: timestamp, duration: tapMotionPostActionSuppressionDuration)
			performTapSequenceAction(.tapCount(count))
		}
	}

	private func handleTapHoldCandidate(_ sample: OuraMotionSample) {
		guard tapHoldRecognizer.registerMotion(sample) else { return }
		motionTrace.recordEvent("tap-hold", timestamp: sample.timestamp)
		if fireGestureButton(.ouraTapHold) {
			tapSequenceWorkItem?.cancel()
			tapSequenceWorkItem = nil
			tapSequence.reset()
			suppressMotionForTap(at: sample.timestamp, duration: tapMotionPostActionSuppressionDuration)
			appendDiagnostic("tap hold resolved")
		} else {
			appendDiagnostic("tap hold detected without mapping")
		}
	}

	private func handleDirectionalFlickCandidate(projectedInput: CGPoint, timestamp: CFAbsoluteTime) {
		guard !tapMotionSuppressor.isSuppressed(at: timestamp),
		      let flick = flickRecognizer.register(projectedInput: projectedInput, timestamp: timestamp) else {
			return
		}

		motionTrace.recordEvent("flick", detail: flick.diagnosticName, timestamp: timestamp)
		if fireGestureButton(flick.button) {
			suppressMotionForTap(at: timestamp, duration: tapMotionPostActionSuppressionDuration)
			appendDiagnostic("flick \(flick.diagnosticName) resolved")
		} else {
			appendDiagnostic("flick \(flick.diagnosticName) detected without mapping")
		}
	}

	// MARK: - ML gesture path

	private func applyMotionGesturesML(_ sample: OuraMotionSample, projectedInput: CGPoint) {
		motionWindowBuffer.append(sample, projected: projectedInput)

		while let peak = pendingClassificationPeaks.first,
		      sample.timestamp >= peak + OuraMotionWindowBuffer.postSpan {
			pendingClassificationPeaks.removeFirst()
			classifyImpulsePeak(peak, now: sample.timestamp)
		}

		if let peak = impulseDetector.register(sample),
		   peak >= suppressTapDetectionUntil,
		   peak >= flickClassificationCooldownUntil {
			pendingClassificationPeaks.append(peak)
		}

		// The hold recognizer consumes the motion stream continuously; skip
		// samples the retroactive catch-up in handleMLTapCandidate already fed.
		if sample.timestamp > tapHoldFedThrough {
			tapHoldFedThrough = sample.timestamp
			handleTapHoldCandidate(sample)
		}
	}

	private func classifyImpulsePeak(_ peak: CFAbsoluteTime, now: CFAbsoluteTime) {
		// The enqueue-time cooldown check can't catch peaks that were already
		// queued when a flick fired — a flick's secondary spikes arrive within
		// ~0.3s and would double-fire it. Anything inside the cooldown is the
		// previous flick's echo; drop it outright.
		guard peak >= flickClassificationCooldownUntil else { return }
		guard let window = motionWindowBuffer.window(around: peak),
		      let (event, confidence) = gestureClassifier.classify(window: window) else {
			return
		}
		motionTrace.recordEvent("ml-class",
			detail: "\(event.rawValue) \(String(format: "%.2f", confidence))", timestamp: peak)
		switch event {
		case .noise:
			break
		case .tap:
			handleMLTapCandidate(at: peak)
		case .flickUp, .flickDown, .flickLeft, .flickRight:
			guard let flick = event.directionalFlick else { return }
			// The v0 model can't cleanly separate casual flicks from
			// cursor-motion impulses (measured confidences overlap; Kevin's
			// real flicks ranged 0.35-1.00). 0.5 keeps most real flicks and
			// drops the low tail; retraining with cursor-navigation negatives
			// is the durable fix.
			guard confidence >= flickConfidenceThreshold else {
				appendDiagnostic("flick \(flick.diagnosticName) ignored (ml, conf \(String(format: "%.2f", confidence)))")
				return
			}
			// A pending tap registered within the flick's own window is the
			// flick's outbound spike — consume it so it can't also resolve as
			// a phantom tap. An older pending sequence is a real tap combo;
			// leave it to resolve on its own timer.
			if let lastTap = tapSequence.lastPendingTapTime,
			   peak - lastTap <= OuraMotionWindowBuffer.preSpan + OuraMotionWindowBuffer.postSpan {
				tapSequenceWorkItem?.cancel()
				tapSequenceWorkItem = nil
				tapSequence.reset()
				tapHoldRecognizer.cancel()
			}
			flickClassificationCooldownUntil = peak + flickClassificationCooldown
			motionTrace.recordEvent("flick", detail: flick.diagnosticName, timestamp: now)
			if fireGestureButton(flick.button) {
				tapHoldRecognizer.cancel()
				suppressMotionForTap(at: now, duration: tapMotionPostActionSuppressionDuration)
				appendDiagnostic("flick \(flick.diagnosticName) resolved (ml)")
			} else {
				appendDiagnostic("flick \(flick.diagnosticName) detected without mapping (ml)")
			}
		}
	}

	private func handleMLTapCandidate(at peak: CFAbsoluteTime) {
		motionTrace.recordEvent("tap-candidate", detail: "ml classifier", timestamp: peak)
		switch tapSequence.registerTap(at: peak) {
		case .duplicate:
			return
		case .pending(let count):
			if count == 1 {
				startTapHoldRetroactively(from: peak)
			} else {
				tapHoldRecognizer.cancel()
			}
			suppressMotionForTap(at: peak, duration: tapMotionSuppressionDuration)
			appendDiagnostic("\(count)x tap pending from ml classifier")
			scheduleMLTapSequenceResolution()
		case .completed(let count):
			tapHoldRecognizer.cancel()
			tapSequenceWorkItem?.cancel()
			tapSequenceWorkItem = nil
			suppressMotionForTap(at: peak, duration: tapMotionPostActionSuppressionDuration)
			performTapSequenceAction(.tapCount(count))
		}
	}

	// Classification arrives ~0.4s after the tap peak; anchor the hold
	// candidate back at the peak and replay the buffered samples since, so
	// hold timing (settle at +0.09s, ring-down drift checks) matches the
	// heuristic path.
	private func startTapHoldRetroactively(from peak: CFAbsoluteTime) {
		let history = motionWindowBuffer.entriesAfter(peak)
		guard let anchor = history.first else { return }
		tapHoldRecognizer.registerTap(at: peak, sample: OuraMotionSample(
			x: anchor.x, y: anchor.y, z: anchor.z, timestamp: anchor.timestamp))
		for entry in history.dropFirst() {
			tapHoldFedThrough = max(tapHoldFedThrough, entry.timestamp)
			handleTapHoldCandidate(OuraMotionSample(
				x: entry.x, y: entry.y, z: entry.z, timestamp: entry.timestamp))
		}
	}

	// A candidate mid-classification may extend the tap sequence, so the
	// resolution timer defers until the pending window completes.
	private func scheduleMLTapSequenceResolution() {
		tapSequenceWorkItem?.cancel()
		let workItem = DispatchWorkItem { [weak self] in self?.resolveMLTapSequence() }
		tapSequenceWorkItem = workItem
		DispatchQueue.main.asyncAfter(
			deadline: .now() + OuraTapSequenceRecognizer.sequenceWindow + 0.02,
			execute: workItem
		)
	}

	private func resolveMLTapSequence() {
		if let pending = pendingClassificationPeaks.first {
			let delay = max(0.05, pending + OuraMotionWindowBuffer.postSpan + 0.05 - CFAbsoluteTimeGetCurrent())
			let workItem = DispatchWorkItem { [weak self] in self?.resolveMLTapSequence() }
			tapSequenceWorkItem = workItem
			DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
			return
		}
		guard let action = tapSequence.resolvePending(at: CFAbsoluteTimeGetCurrent()) else { return }
		performTapSequenceAction(action)
	}

	private func resetMLGestureState() {
		motionWindowBuffer.reset()
		impulseDetector.reset()
		pendingClassificationPeaks.removeAll()
		flickClassificationCooldownUntil = 0
		tapHoldFedThrough = -.greatestFiniteMagnitude
	}

	private func scheduleTapSequenceResolution() {
		tapSequenceWorkItem?.cancel()
		let workItem = DispatchWorkItem { [weak self] in
			guard let self else { return }
			guard let action = self.tapSequence.resolvePending(at: CFAbsoluteTimeGetCurrent()) else { return }
			self.performTapSequenceAction(action)
		}
		tapSequenceWorkItem = workItem
		DispatchQueue.main.asyncAfter(
			deadline: .now() + OuraTapSequenceRecognizer.sequenceWindow + 0.02,
			execute: workItem
		)
	}

	private func performTapSequenceAction(_ action: OuraTapSequenceResolvedAction) {
		tapSequenceWorkItem = nil
		tapHoldRecognizer.cancel()
		suppressMotionForTap(at: CFAbsoluteTimeGetCurrent(), duration: tapMotionPostActionSuppressionDuration)
		switch action {
		case .tapCount(let count):
			motionTrace.recordEvent("tap-resolved", detail: String(count))
			appendDiagnostic("\(count)x tap resolved")
			switch count {
			case 1:
				fireGestureButton(.ouraTap)
			case 2:
				fireGestureButton(.ouraDoubleTap, fallback: { [weak self] in
					self?.appendDiagnostic("double tap recentered motion")
					self?.resetMotionCenter()
				})
			case 3:
				fireGestureButton(.ouraTripleTap, fallback: { [weak self] in
					self?.appendDiagnostic("triple tap toggled motion output")
					self?.toggleMotionOutputEnabled()
				})
			case 5:
				fireGestureButton(.ouraFiveTap)
			default:
				appendDiagnostic("\(count)x tap ignored")
			}
		}
	}

	private func suppressMotionForTap(at timestamp: CFAbsoluteTime, duration: CFTimeInterval) {
		tapMotionSuppressor.suppress(at: timestamp, duration: duration)
		releaseOuraMotionSticks()
	}

	@discardableResult
	private func fireGestureButton(_ button: ControllerButton, fallback: (() -> Void)? = nil) -> Bool {
		if !hasExplicitGestureBinding(for: button) {
			fallback?()
			// Still surface the gesture in the Buttons-tab input timeline —
			// the engine resolves it as unmapped, logs "(unmapped)", and
			// executes nothing. Without this, recognized-but-unbound gestures
			// are invisible, which reads as "the ring isn't working".
			controllerService.handleButton(button, pressed: true)
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) { [weak self] in
				self?.controllerService.handleButton(button, pressed: false)
			}
			return false
		}

		tapReleaseWorkItem?.cancel()
		controllerService.handleButton(button, pressed: true)

		let workItem = DispatchWorkItem { [weak self] in
			self?.controllerService.handleButton(button, pressed: false)
		}
		tapReleaseWorkItem = workItem
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.07, execute: workItem)
		return true
	}

	private func hasExplicitGestureBinding(for button: ControllerButton) -> Bool {
		guard let profile = profileManager.activeProfile else { return false }
		return ButtonMappingResolutionPolicy.hasExplicitBinding(for: button, profile: profile)
	}

	private func loadAuthKey() -> Data? {
		guard let stored = KeychainService.retrievePassword(key: authKeyAccount, service: keychainService),
			  let data = Data(base64Encoded: stored),
			  data.count == kCCKeySizeAES128 else {
			return nil
		}
		return data
	}

	private func saveAuthKey(_ key: Data) {
		KeychainService.storePassword(key.base64EncodedString(), key: authKeyAccount, service: keychainService)
	}

	private func displayName(for peripheral: CBPeripheral) -> String {
		peripheral.name?.isEmpty == false ? peripheral.name! : "Oura Ring"
	}

	private func displayName(for peripheral: CBPeripheral, advertisementData: [String: Any]) -> String {
		if let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String,
		   !localName.isEmpty {
			return localName
		}
		return displayName(for: peripheral)
	}

	private func appendDiagnostic(_ message: String) {
		guard currentSettings.diagnosticsEnabled else { return }
		lastDiagnosticLine = message
		NSLog("[ControllerKeys][Oura] %@", message)
		let timestampFormatter = ISO8601DateFormatter()
		timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		let timestamp = timestampFormatter.string(from: Date())
		let line = "\(timestamp) \(message)\n"
		guard let data = line.data(using: .utf8) else { return }
		do {
			try FileManager.default.createDirectory(
				at: diagnosticLogURL.deletingLastPathComponent(),
				withIntermediateDirectories: true
			)
			if FileManager.default.fileExists(atPath: diagnosticLogURL.path) {
				let handle = try FileHandle(forWritingTo: diagnosticLogURL)
				try handle.seekToEnd()
				try handle.write(contentsOf: data)
				try handle.close()
			} else {
				try data.write(to: diagnosticLogURL, options: .atomic)
			}
		} catch {
			NSLog("[ControllerKeys][Oura] diagnostic file write failed: %@", error.localizedDescription)
		}
	}

	// MARK: - CBCentralManagerDelegate

	func centralManagerDidUpdateState(_ central: CBCentralManager) {
		switch central.state {
		case .poweredOn:
			scanForRing()
		case .unauthorized:
			status = .bluetoothUnavailable("permission denied")
		case .poweredOff:
			status = .bluetoothUnavailable("powered off")
		case .unsupported:
			status = .bluetoothUnavailable("unsupported")
		case .resetting, .unknown:
			status = .bluetoothUnavailable("not ready")
		@unknown default:
			status = .bluetoothUnavailable("unknown state")
		}
	}

	func centralManager(
		_ central: CBCentralManager,
		didDiscover peripheral: CBPeripheral,
		advertisementData: [String: Any],
		rssi RSSI: NSNumber
	) {
		let match = OuraRingScanMatcher.match(
			peripheralName: peripheral.name,
			advertisementData: advertisementData
		)
		if match == nil, currentSettings.diagnosticsEnabled, !loggedNearbyPeripheralIDs.contains(peripheral.identifier) {
			loggedNearbyPeripheralIDs.insert(peripheral.identifier)
			let name = displayName(for: peripheral, advertisementData: advertisementData)
			if name != "Oura Ring" {
				appendDiagnostic("nearby BLE \(name), rssi \(RSSI)")
			}
		}
		guard let match else { return }
		appendDiagnostic("discovered Oura candidate \(displayName(for: peripheral, advertisementData: advertisementData)) via \(match), rssi \(RSSI)")
		connect(to: peripheral)
	}

	func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
		clearConnectAttempt()
		status = .connected(displayName(for: peripheral))
		controllerService.setOuraRingConnected(true)
		peripheral.discoverServices([OuraRingProtocol.serviceUUID])
	}

	func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
		clearConnectAttempt()
		appendDiagnostic("connect failed \(error?.localizedDescription ?? "unknown error")")
		self.peripheral = nil
		status = .disconnected
		if currentSettings.enabled {
			scanForRing()
		}
	}

	func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
		appendDiagnostic("disconnected \(error?.localizedDescription ?? "no error")")
		realtimeRefreshTimer?.invalidate()
		realtimeRefreshTimer = nil
		endStreamingActivity()
		stopMotionWatchdog()
		tapDetector.reset()
		motionMapper.reset()
		resetMLGestureState()
		motionTrace.close()
		if self.peripheral?.identifier == peripheral.identifier {
			clearConnectAttempt()
			self.peripheral = nil
			writeCharacteristic = nil
			notifyCharacteristic = nil
			controllerService.setOuraRingConnected(false)
		}
		status = .disconnected
		if currentSettings.enabled {
			scanForRing()
		}
	}

	// MARK: - CBPeripheralDelegate

	func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
		guard error == nil, let services = peripheral.services else {
			status = .authFailed(error?.localizedDescription ?? "service discovery failed")
			return
		}

		guard let service = services.first(where: { $0.uuid == OuraRingProtocol.serviceUUID }) else {
			status = .authFailed("Oura service not found")
			return
		}

		peripheral.discoverCharacteristics(
			[OuraRingProtocol.writeCharacteristicUUID, OuraRingProtocol.notifyCharacteristicUUID],
			for: service
		)
	}

	func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
		guard error == nil, let characteristics = service.characteristics else {
			status = .authFailed(error?.localizedDescription ?? "characteristic discovery failed")
			return
		}

		for characteristic in characteristics {
			if characteristic.uuid == OuraRingProtocol.writeCharacteristicUUID {
				writeCharacteristic = characteristic
			} else if characteristic.uuid == OuraRingProtocol.notifyCharacteristicUUID {
				notifyCharacteristic = characteristic
				peripheral.setNotifyValue(true, for: characteristic)
			}
		}

		if writeCharacteristic != nil, notifyCharacteristic != nil {
			authenticateOrAdopt()
		}
	}

	func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
		guard error == nil, characteristic.uuid == OuraRingProtocol.notifyCharacteristicUUID, let data = characteristic.value else {
			if let error {
				appendDiagnostic("notify error \(error.localizedDescription)")
			}
			return
		}

		if data.first != OuraRingProtocol.realtimeAccelerometerResponseTag {
			appendDiagnostic("rx \(data.ouraHexString)")
		}
		for event in OuraRingPacketDecoder.decode(data) {
			handle(event, from: peripheral)
		}
	}
}
