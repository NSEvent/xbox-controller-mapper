import Foundation
import Network
import AppKit
import CoreGraphics
import Security
import Darwin
import SwiftUI

@MainActor
private final class UniversalControlPairingCodePanel: NSPanel {
	override var canBecomeKey: Bool { true }
	override var canBecomeMain: Bool { false }
}

@MainActor
private final class UniversalControlPairingCodePresenter {
	static let shared = UniversalControlPairingCodePresenter()

	private var panel: NSPanel?
	private var hostingView: NSHostingView<UniversalControlPairingCodeToast>?
	private var hideWorkItem: DispatchWorkItem?

	private init() {}

	func show(code: String, peerID: String, duration: TimeInterval = 60) {
		hideWorkItem?.cancel()

		let view = UniversalControlPairingCodeToast(code: code, peerID: peerID) { [weak self] in
			self?.hide()
		}
		if panel == nil {
			createPanel(with: view)
		} else {
			hostingView?.rootView = view
		}

		guard let panel, let hostingView else { return }
		let size = hostingView.fittingSize
		hostingView.frame = NSRect(origin: .zero, size: size)
		panel.setContentSize(size)
		position(panel)

		if !panel.isVisible {
			panel.alphaValue = 0
			panel.orderFrontRegardless()
		}

		NSAnimationContext.runAnimationGroup { context in
			context.duration = 0.12
			panel.animator().alphaValue = 1
		}

		let workItem = DispatchWorkItem { [weak self] in
			Task { @MainActor in
				self?.hide()
			}
		}
		hideWorkItem = workItem
		DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
	}

	private func hide() {
		hideWorkItem?.cancel()
		hideWorkItem = nil
		guard let panel, panel.isVisible else { return }
		NSAnimationContext.runAnimationGroup { context in
			context.duration = 0.16
			panel.animator().alphaValue = 0
		} completionHandler: {
			panel.orderOut(nil)
		}
	}

	private func createPanel(with view: UniversalControlPairingCodeToast) {
		let hostingView = NSHostingView(rootView: view)
		let panel = UniversalControlPairingCodePanel(
			contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
			styleMask: [.borderless, .nonactivatingPanel],
			backing: .buffered,
			defer: false
		)
		panel.isOpaque = false
		panel.backgroundColor = .clear
		panel.hasShadow = true
		panel.ignoresMouseEvents = false
		panel.level = .floating
		panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
		panel.hidesOnDeactivate = false
		panel.contentView = hostingView

		self.panel = panel
		self.hostingView = hostingView
	}

	private func position(_ panel: NSPanel) {
		let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
			?? CGRect(x: 0, y: 0, width: 1728, height: 1117)
		let size = panel.frame.size
		panel.setFrameOrigin(NSPoint(
			x: screenFrame.midX - size.width * 0.5,
			y: screenFrame.maxY - size.height - 72
		))
	}
}

private struct UniversalControlPairingCodeToast: View {
	let code: String
	let peerID: String
	let onDismiss: () -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 10) {
				Text("ControllerKeys Pairing Code")
					.font(.headline)

				Spacer(minLength: 8)

				Button {
					onDismiss()
				} label: {
					Image(systemName: "xmark")
						.font(.system(size: 11, weight: .bold))
						.foregroundStyle(.secondary)
						.frame(width: 24, height: 24)
						.contentShape(Circle())
				}
				.buttonStyle(.plain)
				.keyboardShortcut(.cancelAction)
				.accessibilityLabel("Dismiss pairing code")
			}

			Text(code)
				.font(.system(size: 34, weight: .bold, design: .monospaced))
				.monospacedDigit()
				.lineLimit(1)
				.minimumScaleFactor(0.7)

			Text("Enter this code on \(peerID).")
				.font(.caption)
				.foregroundStyle(.secondary)
		}
		.padding(.horizontal, 18)
		.padding(.vertical, 14)
		.frame(width: 320, alignment: .leading)
		.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
		.overlay {
			RoundedRectangle(cornerRadius: 12, style: .continuous)
				.stroke(Color(nsColor: .separatorColor), lineWidth: 1)
		}
		.accessibilityElement(children: .contain)
	}
}

final class UniversalControlMouseRelay: @unchecked Sendable {
    static let shared = UniversalControlMouseRelay()
    private static let bonjourServiceType = "_controllerkeys._tcp"

    enum HandoffEdge: String, Codable {
        case left
        case right
        case top
        case bottom

        var opposite: HandoffEdge {
            switch self {
            case .left: return .right
            case .right: return .left
            case .top: return .bottom
            case .bottom: return .top
            }
        }

        var outwardDelta: CGPoint {
            switch self {
            case .left: return CGPoint(x: -1, y: 0)
            case .right: return CGPoint(x: 1, y: 0)
            case .top: return CGPoint(x: 0, y: -1)
            case .bottom: return CGPoint(x: 0, y: 1)
            }
        }
    }

    struct HandoffZone: Codable {
        var localDisplayID: UInt32?
        var localEdge: HandoffEdge
        /// Display-local axis range. For left/right edges this is y; for top/bottom this is x.
        var localRangeMin: CGFloat?
        var localRangeMax: CGFloat?
        var remoteHost: String
        var remotePort: UInt16
        var remoteEntryEdge: HandoffEdge
        var remoteReturnEdge: HandoffEdge
    }

    struct HandoffDecision {
        let zone: HandoffZone
        let localDisplayID: CGDirectDisplayID
        let localEdgePoint: CGPoint
    }

    private struct LocalDisplay {
        let id: CGDirectDisplayID
        let bounds: CGRect
    }

    private struct RemoteCursorStatus {
        let point: CGPoint
        let displays: [CGRect]
        let receivedAt: Date
    }

    struct RemoteOverlayState {
        let keyboardVisible: Bool
        let keyboardNavigationModeActive: Bool
        let directoryNavigatorVisible: Bool
        let swipePredictionsVisible: Bool
    }

    private let queue = DispatchQueue(label: "com.controllerkeys.uc-relay", qos: .userInteractive)
    private let subprocessQueue = DispatchQueue(label: "com.controllerkeys.uc-relay-subprocess", qos: .utility)
    private let port: NWEndpoint.Port = 38383
	private let remoteMouseEventSource: CGEventSource? = {
		let source = CGEventSource(stateID: .hidSystemState)
		source?.localEventsSuppressionInterval = 0.0
		return source
	}()
    private let lock = NSLock()
    private let maxIncomingConnections = 4
    private let maxLineLength = 16 * 1024
    private let maxCommandsPerSecond = 240
    private let relaySecretKey = "universal-control-relay-secret"
    private let relaySecretKeychainService = "com.controllerkeys.relay-auth"
    private let relayPeerIDDefaultsKey = "universalControlRelayPeerID"
    private let relaySharedSecretDefaultsKey = "universalControlRelaySharedSecret"

    private struct IncomingConnectionState {
        var buffer = ""
        var commandWindowStart = Date()
        var commandCount = 0
        var lastUIStatePayload: String?
    }

    private struct RelayPingTarget {
        let host: String
        let port: NWEndpoint.Port
        let endpoint: NWEndpoint?
        let source: String

        var label: String {
            "\(host):\(port.rawValue)"
        }

        var connectionEndpoint: NWEndpoint {
            endpoint ?? .hostPort(host: NWEndpoint.Host(host), port: port)
        }
    }

    private final class RelayPairingCheckBuffer {
        var text = ""
    }

    private struct OutgoingCodePairing {
        let target: RelayPingTarget
        let connection: NWConnection
        let code: String
        let keyData: Data
    }

    private struct IncomingCodePairing {
        let peerID: String
        let keyData: Data
        let expiresAt: Date
        var attempts: Int
    }

    private struct IncomingPairingPrompt {
        let peerID: String
		let remotePublicKeyBase64: String
		let remoteNonce: String
        let code: String
		let keyData: Data
		let responseLine: String
        let expiresAt: Date
    }

    private var listener: NWListener?
    private var pairingBrowser: NWBrowser?
    private var incomingConnections: [NWConnection] = []
    private var incomingStates: [ObjectIdentifier: IncomingConnectionState] = [:]
    private var receiverInput: InputSimulatorProtocol?
    private var client: NWConnection?
    private var clientHost: String?
    private var clientReceiveBuffer = ""
    private var peerSupportsKP2 = false
    private var authenticator: UniversalControlRelayAuthenticator?
    private var pendingRelayPings: [String: (Bool, String) -> Void] = [:]
    private var pendingOutgoingCodePairing: OutgoingCodePairing?
    private var pendingOutgoingPairingFinalizers: [ObjectIdentifier: NWConnection] = [:]
    private var pendingIncomingCodePairings: [ObjectIdentifier: IncomingCodePairing] = [:]
    private var activeIncomingPairingPrompt: IncomingPairingPrompt?
    private var activeCodePairingSearchID: String?
    private var remoteCursorStatus: RemoteCursorStatus?
	private var remoteSessionReceivedCursorStatus = false
    private var activeHandoffZone: HandoffZone?
    private var pendingHandoffPortal: HandoffDecision?
    private var remoteFocusModeSent: Bool?
    private var remoteKeyboardVisible = false
    private var remoteKeyboardNavigationModeActive = false
    private var remoteKeyboardButton: ControllerButton?
    private var remoteKeyboardHoldMode = false
    private var remoteDirectoryNavigatorVisible = false
    private var remoteDirectoryNavigatorButton: ControllerButton?
    private var remoteDirectoryNavigatorHoldMode = false
    private var remoteSwipePredictionsVisible = false
    private var acceptsRemoteInput = false
    private var pairedRemoteEndpoint: NWEndpoint?
    private var pairedRemoteEndpointKey: String?
    private var isRemoteSessionActive = false
    private var outgoingRemoteMouseButtonsHeld: Set<CGMouseButton> = []
    private var remoteMouseButtonsHeld: Set<CGMouseButton> = []
    private var remoteMouseEventNumber: Int64 = 0
    private var remoteClickCounts: [CGMouseButton: Int64] = [:]
    private var remoteLastClickTime: [CGMouseButton: Date] = [:]
    private var didLogSendFailure = false
    private var didLogFirstSend = false
    private var didLogFirstReceive = false
    private var lastHandoffSkipLog = Date.distantPast
    private var remoteHandoffSuppressedUntil = Date.distantPast
    private var remoteControllerInputRoutingGraceUntil = Date.distantPast
    private var lastRemoteCursorVisibilityRestoreAt: CFTimeInterval?

    // Hot-path caches for the 120 Hz mouse path. Guarded by cacheLock (never
    // taken while cacheLock is already held; lock -> cacheLock ordering only).
    private let cacheLock = NSLock()
    private var cachedHandoffZones: [HandoffZone]?
    private var cachedLocalDisplays: [LocalDisplay]?
    private var cachedDefaultRemoteHost: String?
    private var cachedDefaultRemotePort: NWEndpoint.Port?
    private var cachedRelayTargetDefaultsConfigured: Bool?
    private var cacheInvalidationObservers: [NSObjectProtocol] = []

    private init() {
        cacheInvalidationObservers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.invalidateDefaultsBackedCaches()
        })
        cacheInvalidationObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.invalidateLocalDisplayCache()
        })
    }

    private func invalidateDefaultsBackedCaches() {
        cacheLock.lock()
        cachedHandoffZones = nil
        cachedDefaultRemoteHost = nil
        cachedDefaultRemotePort = nil
        cachedRelayTargetDefaultsConfigured = nil
        cacheLock.unlock()
    }

    private func invalidateLocalDisplayCache() {
        cacheLock.lock()
        cachedLocalDisplays = nil
        cacheLock.unlock()
    }

    var canSendToRemote: Bool {
        lock.lock()
        defer { lock.unlock() }
		return UniversalControlRelayRolePolicy.canSendToRemote(
			acceptsRemoteInput: acceptsRemoteInput
		)
    }

    var canStartRemoteHandoff: Bool {
        lock.lock()
        defer { lock.unlock() }
		return UniversalControlRelayRolePolicy.canStartRemoteHandoff(
			hasConfiguredRelayTarget: hasConfiguredRelayTargetLocked(),
			remoteHandoffSuppressed: Date() < remoteHandoffSuppressedUntil
		)
    }

    var hasRecentRemoteCursorStatus: Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let remoteCursorStatus else { return false }
        return Date().timeIntervalSince(remoteCursorStatus.receivedAt) < 2.0
    }

	var hasReceivedRemoteCursorStatus: Bool {
		lock.lock()
		defer { lock.unlock() }
		return remoteSessionReceivedCursorStatus
	}

    var hasActiveRemoteSession: Bool {
        lock.lock()
        defer { lock.unlock() }
		return isRemoteSessionActive
    }

    var isRoutingToRemote: Bool {
		lock.lock()
		defer { lock.unlock() }
		return UniversalControlRelaySessionPolicy.shouldRouteMovementToRemote(
			sessionActive: isRemoteSessionActive,
			hasReceivedCursorStatus: remoteSessionReceivedCursorStatus
		)
    }

    var shouldRouteControllerInputToRemote: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRemoteSessionActive || Date() < remoteControllerInputRoutingGraceUntil
    }

    var isOutgoingRemoteLeftMouseButtonHeld: Bool {
        lock.lock()
        defer { lock.unlock() }
        return outgoingRemoteMouseButtonsHeld.contains(.left)
    }

    func remoteOverlayState() -> RemoteOverlayState {
        lock.lock()
        defer { lock.unlock() }
		guard isRemoteSessionActive else {
            return RemoteOverlayState(
                keyboardVisible: false,
                keyboardNavigationModeActive: false,
                directoryNavigatorVisible: false,
                swipePredictionsVisible: false
            )
        }
        return RemoteOverlayState(
            keyboardVisible: remoteKeyboardVisible,
            keyboardNavigationModeActive: remoteKeyboardNavigationModeActive,
            directoryNavigatorVisible: remoteDirectoryNavigatorVisible,
            swipePredictionsVisible: remoteSwipePredictionsVisible
        )
    }

    func setRemoteSessionActive(_ active: Bool) {
        lock.lock()
        isRemoteSessionActive = active
        if !active {
            remoteCursorStatus = nil
			remoteSessionReceivedCursorStatus = false
            activeHandoffZone = nil
            pendingHandoffPortal = nil
            remoteControllerInputRoutingGraceUntil = Date.distantPast
            remoteFocusModeSent = nil
			resetRemoteCursorVisibilityRestoreStateLocked()
            outgoingRemoteMouseButtonsHeld.removeAll()
            remoteKeyboardVisible = false
            remoteKeyboardNavigationModeActive = false
            remoteKeyboardButton = nil
            remoteKeyboardHoldMode = false
            remoteDirectoryNavigatorVisible = false
            remoteDirectoryNavigatorButton = nil
            remoteDirectoryNavigatorHoldMode = false
            remoteSwipePredictionsVisible = false
        }
        lock.unlock()
        if !active {
            NSLog("[UCMouseRelay] Handoff ended")
        }
    }

    func cancelUnconfirmedRemoteSession() {
        lock.lock()
        isRemoteSessionActive = false
		remoteCursorStatus = nil
		remoteSessionReceivedCursorStatus = false
        activeHandoffZone = nil
        pendingHandoffPortal = nil
        remoteControllerInputRoutingGraceUntil = Date.distantPast
        remoteFocusModeSent = nil
		resetRemoteCursorVisibilityRestoreStateLocked()
        outgoingRemoteMouseButtonsHeld.removeAll()
        lock.unlock()
    }

    func suppressRemoteHandoff(reason: String, duration: TimeInterval = 5.0) {
		let until = Date().addingTimeInterval(duration)
		lock.lock()
		if until > remoteHandoffSuppressedUntil {
			remoteHandoffSuppressedUntil = until
		}
		lock.unlock()
		NSLog("[UCMouseRelay] Remote handoff suppressed for %.1fs: %@", duration, reason)
    }

    func beginRemoteSession(zone: HandoffZone) {
        lock.lock()
        activeHandoffZone = zone
		remoteCursorStatus = nil
		remoteSessionReceivedCursorStatus = false
        remoteControllerInputRoutingGraceUntil = Date().addingTimeInterval(UniversalControlRelaySessionPolicy.confirmationTimeout)
		resetRemoteCursorVisibilityRestoreStateLocked()
        isRemoteSessionActive = true
        lock.unlock()
        NSLog(
            "[UCMouseRelay] Handoff started localEdge=%@ remote=%@:%d returnEdge=%@",
            zone.localEdge.rawValue,
            zone.remoteHost,
            zone.remotePort,
            zone.remoteReturnEdge.rawValue
        )
    }

	#if DEBUG
	func confirmRemoteSessionForTesting(
		point: CGPoint = .zero,
		displays: [CGRect] = [CGRect(x: 0, y: 0, width: 100, height: 100)]
	) {
		lock.lock()
		remoteCursorStatus = RemoteCursorStatus(
			point: point,
			displays: displays,
			receivedAt: Date()
		)
		remoteSessionReceivedCursorStatus = true
		lock.unlock()
	}
	#endif

    func showLocalHandoffPortal(for decision: HandoffDecision) {
        lock.lock()
        pendingHandoffPortal = decision
        lock.unlock()
    }

    private func showConfirmedHandoffPortal(for decision: HandoffDecision) {
        Task { @MainActor in
            UniversalControlPortalIndicator.shared.flash(
                edge: decision.zone.localEdge,
                displayID: decision.localDisplayID
            )
            UniversalControlPortalIndicator.shared.showInactiveCursor(
                at: decision.localEdgePoint,
                displayID: decision.localDisplayID
            )
        }
        _ = sendLine("portal \(decision.zone.remoteEntryEdge.rawValue) \(decision.zone.remoteReturnEdge.rawValue)")
    }

    func endRemoteSession() {
        _ = sendControllerInputReset()
        _ = sendFocusMode(active: false)
        if let returnEdge = activeRemoteReturnEdge() {
            _ = sendLine("portalExit \(returnEdge.rawValue)")
        } else {
            _ = sendLine("portalEnd")
        }
        Task { @MainActor in
            UniversalControlPortalIndicator.shared.flashActiveCursor()
        }
        setRemoteSessionActive(false)
    }

    private func activeRemoteReturnEdge() -> HandoffEdge? {
        lock.lock()
        defer { lock.unlock() }
        return activeHandoffZone?.remoteReturnEdge
    }

    func shouldReturnFromRemote(dx: Int, dy: Int) -> Bool {
        lock.lock()
        let status = remoteCursorStatus
        let zone = activeHandoffZone
        lock.unlock()
        guard let status, let zone else { return false }

        guard isMovingOutward(dx: dx, dy: dy, through: zone.remoteReturnEdge) else {
            return false
        }

        return status.displays.contains { display in
            isPoint(status.point, on: zone.remoteReturnEdge, of: display)
        }
    }

    func handoffDecision(current: CGPoint, proposed: CGPoint, delta: CGPoint) -> HandoffDecision? {
        guard canStartRemoteHandoff else {
            logHandoffSkip("cannot start remote handoff without a configured peer")
            return nil
        }

        let dx = Int(delta.x)
        let dy = Int(delta.y)
        let displays = localDisplays()
        let unionBounds = displays.reduce(CGRect.null) { result, display in
            result.union(display.bounds)
        }
        var inspectedZones = 0
        for zone in configuredHandoffZones() where isMovingOutward(dx: dx, dy: dy, through: zone.localEdge) {
            inspectedZones += 1
            for display in displays where zone.localDisplayID == nil || zone.localDisplayID == display.id {
                if zone.localDisplayID == nil && !isOuterDesktopEdge(zone.localEdge, displayBounds: display.bounds, unionBounds: unionBounds) {
                    continue
                }
                let axisPoint = clampedPoint(current, to: display.bounds)
                guard shouldStartHandoff(edge: zone.localEdge, from: current, to: proposed, in: display.bounds),
                      axisPosition(for: axisPoint, edge: zone.localEdge, displayBounds: display.bounds, zone: zone) != nil else {
                    continue
                }
                return HandoffDecision(
                    zone: zone,
                    localDisplayID: display.id,
                    localEdgePoint: edgePoint(for: axisPoint, edge: zone.localEdge, displayBounds: display.bounds)
                )
            }
        }

        if inspectedZones > 0 {
            logHandoffSkip(
                "no edge crossing current=\(Int(current.x)),\(Int(current.y)) proposed=\(Int(proposed.x)),\(Int(proposed.y)) delta=\(dx),\(dy)"
            )
        }
        return nil
    }

    private func logHandoffSkip(_ message: String) {
        let now = Date()
        lock.lock()
        guard now.timeIntervalSince(lastHandoffSkipLog) > 1 else {
            lock.unlock()
            return
        }
        lastHandoffSkipLog = now
        lock.unlock()
        NSLog("[UCMouseRelay] Handoff skipped: %@", message)
    }

    private var defaultRemoteHost: String {
        cacheLock.lock()
        if let cachedDefaultRemoteHost {
            cacheLock.unlock()
            return cachedDefaultRemoteHost
        }
        cacheLock.unlock()

        let host = UserDefaults.standard.string(forKey: "universalControlRelayHost") ?? "kmacstudio"
        cacheLock.lock()
        cachedDefaultRemoteHost = host
        cacheLock.unlock()
        return host
    }

    private var defaultRemotePort: NWEndpoint.Port {
        cacheLock.lock()
        if let cachedDefaultRemotePort {
            cacheLock.unlock()
            return cachedDefaultRemotePort
        }
        cacheLock.unlock()

        let rawValue = UserDefaults.standard.integer(forKey: "universalControlRelayPort")
        let resolved: NWEndpoint.Port
        if rawValue > 0, rawValue <= Int(UInt16.max),
           let port = NWEndpoint.Port(rawValue: UInt16(rawValue)) {
            resolved = port
        } else {
            resolved = self.port
        }
        cacheLock.lock()
        cachedDefaultRemotePort = resolved
        cacheLock.unlock()
        return resolved
    }

    var relayPairingSecret: String {
        relaySharedSecretBase64()
    }

    @discardableResult
    func configureRelayPairingSecret(_ secret: String) -> Bool {
        guard let data = Self.decodeRelaySecret(secret) else { return false }
		return storeRelaySharedSecret(data)
    }

    func configureRelayPairingSecretAndCheck(
        _ secret: String,
        completion: @escaping (Bool, String) -> Void
    ) {
		guard let data = Self.decodeRelaySecret(secret) else {
            DispatchQueue.main.async {
                completion(false, "Invalid secret. Paste the full base64 or hex secret from the other Mac.")
            }
            return
        }
		guard storeRelaySharedSecret(data) else {
			DispatchQueue.main.async {
				completion(false, "Could not save pairing secret to Keychain. Check Keychain access and try again.")
			}
			return
		}

        pingConfiguredRemote(completion: completion)
    }

    func checkRelayPairing(completion: @escaping (Bool, String) -> Void) {
        pingConfiguredRemote(completion: completion)
    }

    func startRelayCodePairing(completion: @escaping (Bool, String) -> Void) {
        discoverRelayPingTargets { [weak self] targets in
            guard let self else { return }
            guard !targets.isEmpty else {
                DispatchQueue.main.async {
                    completion(false, "No ControllerKeys peer found on the local network or tailnet.")
                }
                return
            }

            let searchID = UUID().uuidString
            self.lock.lock()
            self.pendingOutgoingCodePairing = nil
            self.activeCodePairingSearchID = searchID
            self.lock.unlock()

            let session = UniversalControlRelayPairingSession(localPeerID: self.localRelayPeerID())
            for target in targets {
                self.sendPairingHello(to: target, session: session, completion: completion)
            }

            let targetList = targets.map(\.label).joined(separator: ", ")
            self.queue.asyncAfter(deadline: .now() + 6.0) { [weak self] in
                guard let self else { return }
                self.lock.lock()
                let shouldFail = self.activeCodePairingSearchID == searchID
                if shouldFail {
                    self.activeCodePairingSearchID = nil
                }
                self.lock.unlock()
                if shouldFail {
                    DispatchQueue.main.async {
                        completion(false, "No ControllerKeys peer started pairing. Tried: \(targetList).")
                    }
                }
            }
        }
    }

    func completeRelayCodePairing(code: String, completion: @escaping (Bool, String) -> Void) {
        let normalized = code.filter(\.isNumber)
        guard normalized.count == UniversalControlRelayPairingSession.codeDigits else {
            completion(false, "Enter the 6-digit code shown on the other Mac.")
            return
        }

        lock.lock()
        guard let pending = pendingOutgoingCodePairing else {
            lock.unlock()
            completion(false, "No pairing request is waiting. Start pairing again.")
            return
        }
        guard pending.code == normalized else {
            lock.unlock()
            completion(false, "Code did not match. Check the code on the other Mac and try again.")
            return
        }
        pendingOutgoingCodePairing = nil
		pendingOutgoingPairingFinalizers[ObjectIdentifier(pending.connection)] = pending.connection
        lock.unlock()

		let buffer = RelayPairingCheckBuffer()
		receivePairingFinalizeResponse(
			on: pending.connection,
			target: pending.target,
			keyData: pending.keyData,
			buffer: buffer,
			completion: completion
		)

		guard sendAuthenticatedLine("pairFinish \(localRelayPeerID())", secretData: pending.keyData, on: pending.connection) else {
			finishOutgoingPairing(
				connectionKey: ObjectIdentifier(pending.connection),
				target: pending.target,
				keyData: nil,
				success: false,
				message: "Could not send pairing confirmation to \(pending.target.label). Start pairing again.",
				completion: completion
			)
			return
		}

		queue.asyncAfter(deadline: .now() + 6.0) { [weak self] in
			self?.finishOutgoingPairing(
				connectionKey: ObjectIdentifier(pending.connection),
				target: pending.target,
				keyData: nil,
				success: false,
				message: "\(pending.target.label) did not confirm pairing. Start pairing again.",
				completion: completion
			)
        }
    }

    func resetRelayPairingSecret() {
        UserDefaults.standard.removeObject(forKey: relaySharedSecretDefaultsKey)
        UserDefaults.standard.removeObject(forKey: "universalControlRelayHost")
        UserDefaults.standard.removeObject(forKey: "universalControlRelayPort")
        KeychainService.deletePassword(
            key: relaySecretKey,
            service: relaySecretKeychainService
        )
        lock.lock()
        pendingOutgoingCodePairing = nil
		pendingOutgoingPairingFinalizers.values.forEach { $0.cancel() }
		pendingOutgoingPairingFinalizers.removeAll()
        activeCodePairingSearchID = nil
        pendingIncomingCodePairings.removeAll()
        activeIncomingPairingPrompt = nil
        pairedRemoteEndpoint = nil
        pairedRemoteEndpointKey = nil
		peerSupportsKP2 = false
		remoteHandoffSuppressedUntil = .distantPast
        lock.unlock()
        resetAuthenticator(secretData: relaySharedSecretData())
    }

    func startListening(inputSimulator: InputSimulatorProtocol) {
        lock.lock()
        receiverInput = inputSimulator
        if authenticator == nil {
            authenticator = UniversalControlRelayAuthenticator(
                secretData: relaySharedSecretData(),
                peerID: localRelayPeerID()
            )
        }
        let alreadyListening = listener != nil
        lock.unlock()
        guard !alreadyListening else { return }

        lock.lock()
		acceptsRemoteInput = true
        lock.unlock()

        do {
            let listener = try NWListener(using: .tcp, on: port)
            listener.service = NWListener.Service(
                name: Self.localBonjourServiceName(),
                type: Self.bonjourServiceType
            )
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleIncoming(connection)
            }
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    NSLog("[UCMouseRelay] Listener failed: %@", String(describing: error))
                }
            }

            lock.lock()
            self.listener = listener
            lock.unlock()

            listener.start(queue: queue)
			NSLog("[UCMouseRelay] Listening on TCP %d; acceptsRemoteInput=true", port.rawValue)
        } catch {
            NSLog("[UCMouseRelay] Could not listen on TCP %d: %@", port.rawValue, String(describing: error))
        }
    }

    private static func localBonjourServiceName() -> String {
        var raw = Host.current().name ?? ProcessInfo.processInfo.hostName
        if raw.lowercased().hasSuffix(".local") {
            raw.removeLast(".local".count)
        }
        return raw.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    func sendMove(dx: Int, dy: Int) -> Bool {
        guard canSendToRemote else { return false }
        guard dx != 0 || dy != 0 else { return true }

        guard let sealed = sealOutgoingLine("m \(dx) \(dy)") else { return false }
        let message = "\(sealed)\n"
        guard let data = message.data(using: .utf8) else { return false }
        let connection = ensureClientForActiveZone()

        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let error else { return }
            self?.logSendFailureOnce(error)
        })
        logFirstSend(dx: dx, dy: dy)
        return true
    }

    func sendKeyPress(_ keyCode: CGKeyCode, modifiers: CGEventFlags) -> Bool {
		sendLine(UniversalControlRelayKeyPressEncoding.line(keyCode: keyCode, modifiers: modifiers))
    }

    func sendKeyPress(_ keyCode: CGKeyCode, modifiers: ModifierFlags) -> Bool {
		lock.lock()
		let supportsKP2 = peerSupportsKP2
		lock.unlock()

		return sendLine(
			UniversalControlRelayKeyPressEncoding.line(
				keyCode: keyCode,
				modifiers: modifiers,
				peerSupportsKP2: supportsKP2
			)
		)
    }

    private static func modifierSide(from wireValue: Substring) -> ModifierSide? {
		switch Int(wireValue) {
		case 1: return .left
		case 2: return .right
		default: return nil
		}
    }

    func sendControllerButtonPressed(_ button: ControllerButton) -> Bool {
        guard hasActiveRemoteSession else { return false }
        return sendLine("bp \(button.rawValue)")
    }

    func sendControllerButtonReleased(_ button: ControllerButton, holdDuration: TimeInterval) -> Bool {
        guard hasActiveRemoteSession else { return false }
        return sendLine("br \(button.rawValue) \(holdDuration)")
    }

    func sendControllerChord(_ buttons: Set<ControllerButton>) -> Bool {
        guard hasActiveRemoteSession else { return false }
        let payload = buttons
            .map(\.rawValue)
            .sorted()
            .joined(separator: " ")
        guard !payload.isEmpty else { return false }
        return sendLine("bc \(payload)")
    }

    func sendControllerInputReset() -> Bool {
        guard hasActiveRemoteSession else { return false }
        return sendLine("bclear")
    }

    func sendKeyDown(_ keyCode: CGKeyCode, modifiers: CGEventFlags) -> Bool {
        let sent = sendLine("kd \(keyCode) \(modifiers.rawValue)")
        if sent {
            updateOutgoingRemoteMouseButtonState(keyCode: keyCode, isDown: true)
        }
        return sent
    }

    func sendKeyUp(_ keyCode: CGKeyCode) -> Bool {
        let sent = sendLine("ku \(keyCode)")
        if sent {
            updateOutgoingRemoteMouseButtonState(keyCode: keyCode, isDown: false)
        }
        return sent
    }

    func sendHoldModifier(_ modifier: CGEventFlags) -> Bool {
        sendLine("hm \(modifier.rawValue)")
    }

    func sendReleaseModifier(_ modifier: CGEventFlags) -> Bool {
        sendLine("rm \(modifier.rawValue)")
    }

    func sendReleaseAllModifiers() -> Bool {
        sendLine("ra")
    }

    func sendUIEvent(_ name: String, button: ControllerButton, holdMode: Bool = false) -> Bool {
        guard hasActiveRemoteSession else { return false }
        updateRemoteOverlayStateForSentUIEvent(name, button: button, holdMode: holdMode)
        return sendLine("ui \(name) \(button.rawValue) \(holdMode ? 1 : 0)")
    }

    func sendOnScreenKeyboardNavigation(_ button: ControllerButton) -> Bool {
        guard hasActiveRemoteSession else { return false }
        markRemoteKeyboardNavigationActive()
        return sendUIEvent("oskNavigate", button: button)
    }

    func sendOnScreenKeyboardActivate() -> Bool {
        guard hasActiveRemoteSession else { return false }
        return sendUIEvent("oskActivate", button: .a)
    }

    func sendSwipePredictionNavigation(_ button: ControllerButton) -> Bool {
        guard hasActiveRemoteSession else { return false }
        return sendUIEvent("swipeNavigate", button: button)
    }

    func sendSwipePredictionConfirm() -> Bool {
        guard hasActiveRemoteSession else { return false }
        return sendUIEvent("swipeConfirm", button: .a)
    }

    func sendSwipePredictionCancel() -> Bool {
        guard hasActiveRemoteSession else { return false }
        return sendUIEvent("swipeCancel", button: .b)
    }

    func sendSwipeMode(active: Bool) -> Bool {
        guard hasActiveRemoteSession else { return false }
        return sendLine("swipeMode \(active ? 1 : 0)")
    }

    func sendSwipeBegin() -> Bool {
        guard hasActiveRemoteSession else { return false }
        return sendLine("swipeBegin")
    }

    func sendSwipeEnd() -> Bool {
        guard hasActiveRemoteSession else { return false }
        return sendLine("swipeEnd")
    }

    func sendSwipeJoystick(x: Double, y: Double, sensitivity: Double) -> Bool {
        guard hasActiveRemoteSession else { return false }
        return sendLine("swipeStick \(x) \(y) \(sensitivity)")
    }

    func sendSwipeTouchpadDelta(dx: Double, dy: Double, sensitivity: Double) -> Bool {
        guard hasActiveRemoteSession else { return false }
        return sendLine("swipeTouch \(dx) \(dy) \(sensitivity)")
    }

    func sendDirectoryNavigation(_ button: ControllerButton) -> Bool {
        guard hasActiveRemoteSession else { return false }
        return sendUIEvent("dirNavigate", button: button)
    }

    func sendDirectoryConfirm() -> Bool {
        guard hasActiveRemoteSession else { return false }
        return sendUIEvent("dirConfirm", button: .a)
    }

    func sendDirectoryDismiss() -> Bool {
        guard hasActiveRemoteSession else { return false }
        return sendUIEvent("dirDismiss", button: .y)
    }

    func sendCommandWheelUpdate(stick: CGPoint, alternateHeld: Bool) -> Bool {
        guard hasActiveRemoteSession else { return false }
        return sendLine("wheel \(Double(stick.x)) \(Double(stick.y)) \(alternateHeld ? 1 : 0)")
    }

    func sendFocusMode(active: Bool) -> Bool {
        lock.lock()
		guard isRemoteSessionActive else {
            lock.unlock()
            return false
        }
        if remoteFocusModeSent == active {
            lock.unlock()
            return true
        }
        remoteFocusModeSent = active
        lock.unlock()
        return sendLine("focus \(active ? 1 : 0)")
    }

    func sendScroll(
        dx: CGFloat,
        dy: CGFloat,
        phase: CGScrollPhase?,
        momentumPhase: CGMomentumScrollPhase?,
        isContinuous: Bool,
        flags: CGEventFlags
    ) -> Bool {
        let phaseRaw = phase.map { Int($0.rawValue) } ?? -1
        let momentumRaw = momentumPhase.map { Int($0.rawValue) } ?? -1
        return sendLine("sc \(Double(dx)) \(Double(dy)) \(phaseRaw) \(momentumRaw) \(isContinuous ? 1 : 0) \(flags.rawValue)")
    }

    func sendTypeText(_ text: String, speed: Int, pressEnter: Bool) -> Bool {
        let encoded = Data(text.utf8).base64EncodedString()
        return sendLine("tt \(encoded) \(speed) \(pressEnter ? 1 : 0)")
    }

    func sendFeedback(action: String, type: InputEventType, isHeld: Bool) -> Bool {
        guard hasActiveRemoteSession else { return false }
        let encoded = Data(action.utf8).base64EncodedString()
        let encodedType = Data(type.rawValue.utf8).base64EncodedString()
        return sendLine("fb \(encoded) \(encodedType) \(isHeld ? 1 : 0)")
    }

    func sendDismissFeedback(action: String?) -> Bool {
        guard hasActiveRemoteSession else { return false }
        let encoded = action.map { Data($0.utf8).base64EncodedString() } ?? "-"
        return sendLine("fd \(encoded)")
    }

    private func sendLine(_ line: String) -> Bool {
        guard canSendToRemote else { return false }
        return sendAuthenticatedLine(line, on: ensureClientForActiveZone())
    }

    private func sendAuthenticatedLine(_ line: String, on connection: NWConnection) -> Bool {
        guard let sealed = sealOutgoingLine(line),
              let data = "\(sealed)\n".data(using: .utf8) else { return false }
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let error else { return }
            self?.logSendFailureOnce(error)
        })
        return true
    }

    private func sendAuthenticatedLine(_ line: String, secretData: Data, on connection: NWConnection) -> Bool {
        var authenticator = UniversalControlRelayAuthenticator(
            secretData: secretData,
            peerID: localRelayPeerID()
        )
        guard let sealed = authenticator.seal(line),
              let data = "\(sealed)\n".data(using: .utf8) else { return false }
        connection.send(content: data, completion: .contentProcessed { error in
            if let error {
                NSLog("[UCMouseRelay] Pairing finish send failed: %@", String(describing: error))
            }
        })
        return true
    }

    private func sealOutgoingLine(_ line: String) -> String? {
        lock.lock()
        if authenticator == nil {
            authenticator = UniversalControlRelayAuthenticator(
                secretData: relaySharedSecretData(),
                peerID: localRelayPeerID()
            )
        }
        let sealed = authenticator?.seal(line)
        lock.unlock()
        return sealed
    }

    private func openIncomingLine(_ line: String) -> String? {
        lock.lock()
        if authenticator == nil {
            authenticator = UniversalControlRelayAuthenticator(
                secretData: relaySharedSecretData(),
                peerID: localRelayPeerID()
            )
        }
        let payload = authenticator?.open(line)
        lock.unlock()
        return payload
    }

    private func openIncomingLine(_ line: String, secretData: Data) -> String? {
        var authenticator = UniversalControlRelayAuthenticator(
            secretData: secretData,
            peerID: localRelayPeerID()
        )
        return authenticator.open(line)
    }

    private func resetAuthenticator(secretData: Data) {
        lock.lock()
        authenticator = UniversalControlRelayAuthenticator(
            secretData: secretData,
            peerID: localRelayPeerID()
        )
        lock.unlock()
    }

    private func updateRemoteOverlayStateForSentUIEvent(_ name: String, button: ControllerButton, holdMode: Bool) {
        lock.lock()
        switch name {
        case "oskPress":
            remoteDirectoryNavigatorVisible = false
            remoteDirectoryNavigatorButton = nil
            remoteDirectoryNavigatorHoldMode = false
            remoteKeyboardButton = button
            remoteKeyboardHoldMode = holdMode
            if holdMode {
                remoteKeyboardVisible = true
            } else {
                remoteKeyboardVisible.toggle()
            }
            if !remoteKeyboardVisible {
                remoteKeyboardNavigationModeActive = false
                remoteKeyboardButton = nil
                remoteKeyboardHoldMode = false
                remoteSwipePredictionsVisible = false
            }
        case "oskRelease":
            if remoteKeyboardButton == button, remoteKeyboardHoldMode {
                remoteKeyboardVisible = false
                remoteKeyboardNavigationModeActive = false
                remoteKeyboardButton = nil
                remoteKeyboardHoldMode = false
                remoteSwipePredictionsVisible = false
            }
        case "navPress":
            remoteKeyboardVisible = false
            remoteKeyboardNavigationModeActive = false
            remoteKeyboardButton = nil
            remoteKeyboardHoldMode = false
            remoteSwipePredictionsVisible = false
            remoteDirectoryNavigatorButton = button
            remoteDirectoryNavigatorHoldMode = holdMode
            if holdMode {
                remoteDirectoryNavigatorVisible = true
            } else {
                remoteDirectoryNavigatorVisible.toggle()
            }
            if !remoteDirectoryNavigatorVisible {
                remoteDirectoryNavigatorButton = nil
                remoteDirectoryNavigatorHoldMode = false
            }
        case "navRelease":
            if remoteDirectoryNavigatorButton == button, remoteDirectoryNavigatorHoldMode {
                remoteDirectoryNavigatorVisible = false
                remoteDirectoryNavigatorButton = nil
                remoteDirectoryNavigatorHoldMode = false
            }
        case "dirConfirm", "dirDismiss":
            remoteDirectoryNavigatorVisible = false
            remoteDirectoryNavigatorButton = nil
            remoteDirectoryNavigatorHoldMode = false
        default:
            break
        }
        lock.unlock()
    }

    private func markRemoteKeyboardNavigationActive() {
        lock.lock()
        remoteKeyboardNavigationModeActive = true
        lock.unlock()
    }

    private func ensureClientForActiveZone() -> NWConnection {
        lock.lock()
        let zone = activeHandoffZone
        let pairedEndpoint = pairedRemoteEndpoint
        let pairedEndpointKey = pairedRemoteEndpointKey
        lock.unlock()
        let host = zone?.remoteHost ?? defaultRemoteHost
        let remotePort = zone.flatMap { NWEndpoint.Port(rawValue: $0.remotePort) } ?? defaultRemotePort
        let key = "\(host):\(remotePort.rawValue)"
        if let pairedEndpoint, pairedEndpointKey == key {
            return ensureClient(endpoint: pairedEndpoint, key: key, label: host, port: remotePort)
        }
        return ensureClient(host: host, port: remotePort)
    }

    private func ensureClient(host: String, port remotePort: NWEndpoint.Port) -> NWConnection {
        let clientKey = "\(host):\(remotePort.rawValue)"
        return ensureClient(
            endpoint: .hostPort(host: NWEndpoint.Host(host), port: remotePort),
            key: clientKey,
            label: host,
            port: remotePort
        )
    }

    private func ensureClient(endpoint: NWEndpoint, key clientKey: String, label host: String, port remotePort: NWEndpoint.Port) -> NWConnection {
        lock.lock()
        if let client, clientHost == clientKey {
            lock.unlock()
            return client
        }

        let staleClient = client
        let connection = NWConnection(to: endpoint, using: .tcp)
        client = connection
        clientHost = clientKey
		peerSupportsKP2 = false
        didLogSendFailure = false
        didLogFirstSend = false
        clientReceiveBuffer = ""
        lock.unlock()

        staleClient?.cancel()

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let connection else { return }
            switch state {
            case .failed(let error):
                NSLog("[UCMouseRelay] Client failed: %@", String(describing: error))
                self?.clearClient(ifCurrent: connection)
            case .cancelled:
                self?.clearClient(ifCurrent: connection)
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveNextFromClient(on: connection)

        NSLog("[UCMouseRelay] Sending to %@:%d", host, remotePort.rawValue)
        return connection
    }

    private func clearClient(ifCurrent connection: NWConnection) {
        lock.lock()
        guard client === connection else {
            lock.unlock()
            return
        }
        client = nil
        clientHost = nil
        peerSupportsKP2 = false
        clientReceiveBuffer = ""
        lock.unlock()
        connection.cancel()
    }

    private func pingConfiguredRemote(completion: @escaping (Bool, String) -> Void) {
        discoverRelayPingTargets { [weak self] targets in
            guard let self else { return }
            let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")

            guard !targets.isEmpty else {
                DispatchQueue.main.async {
                    completion(
                        false,
                        "No ControllerKeys peer found on the local network or tailnet."
                    )
                }
                return
            }

            self.lock.lock()
            self.pendingRelayPings[nonce] = completion
            self.lock.unlock()

            for target in targets {
                self.sendPairingPing(to: target, nonce: nonce)
            }

            let targetList = targets.map(\.label).joined(separator: ", ")
            self.queue.asyncAfter(deadline: .now() + 6.0) { [weak self] in
                self?.completeRelayPing(
                    nonce,
                    success: false,
                    message: "No discovered ControllerKeys peer returned an authenticated pairing response. Tried: \(targetList)."
                )
            }
        }
    }

    private func discoverRelayPingTargets(completion: @escaping ([RelayPingTarget]) -> Void) {
        // The tailscale CLI subprocess blocks; keep it off the queue that
        // services the listener and live connections.
        subprocessQueue.async { [weak self] in
            guard let self else { return }
            let tailscaleTargets = self.tailscaleRelayPingTargets()
            self.queue.async { [weak self] in
                guard let self else { return }
                var targets = self.configuredRelayPingTargets()
                targets.append(contentsOf: tailscaleTargets)
                self.discoverBonjourRelayPingTargets(timeout: 1.5) { bonjourTargets in
                    targets.append(contentsOf: bonjourTargets)
                    completion(self.deduplicateRelayPingTargets(targets))
                }
            }
        }
    }

    private func configuredRelayPingTargets() -> [RelayPingTarget] {
        var targets: [RelayPingTarget] = []
        var seen = Set<String>()

        func append(host: String, port: NWEndpoint.Port, source: String) {
            let key = "\(host):\(port.rawValue)"
            guard !seen.contains(key) else { return }
            guard !isSelfTarget(host: host) else {
                NSLog("[UCMouseRelay] Skipping self pairing target %@", key)
                return
            }
            seen.insert(key)
            targets.append(RelayPingTarget(host: host, port: port, endpoint: nil, source: source))
        }

        lock.lock()
        let activeZone = activeHandoffZone
        lock.unlock()

        if let activeZone,
           let port = NWEndpoint.Port(rawValue: activeZone.remotePort) {
            append(host: activeZone.remoteHost, port: port, source: "active")
        }

        for zone in configuredHandoffZones() {
            if let port = NWEndpoint.Port(rawValue: zone.remotePort) {
                append(host: zone.remoteHost, port: port, source: "configured")
            }
        }

        append(host: defaultRemoteHost, port: defaultRemotePort, source: "configured")
        return targets
    }

    private func tailscaleRelayPingTargets() -> [RelayPingTarget] {
        let hosts = tailscalePeerHosts()
        return hosts.compactMap { host in
            guard !isSelfTarget(host: host) else { return nil }
            return RelayPingTarget(host: host, port: port, endpoint: nil, source: "tailscale")
        }
    }

    private func discoverBonjourRelayPingTargets(
        timeout: TimeInterval,
        completion: @escaping ([RelayPingTarget]) -> Void
    ) {
        let descriptor = NWBrowser.Descriptor.bonjour(type: Self.bonjourServiceType, domain: nil)
        let browser = NWBrowser(for: descriptor, using: .tcp)
        var targets: [RelayPingTarget] = []

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            var updated: [RelayPingTarget] = []
            for result in results {
                guard case .service(let name, _, _, _) = result.endpoint else { continue }
                let host = "\(name).local"
                guard !self.isSelfTarget(host: host) else { continue }
                updated.append(
                    RelayPingTarget(
                        host: host,
                        port: self.port,
                        endpoint: result.endpoint,
                        source: "bonjour"
                    )
                )
            }
            targets = updated
        }

        browser.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                NSLog("[UCMouseRelay] Bonjour discovery failed: %@", String(describing: error))
            }
        }

        lock.lock()
        pairingBrowser = browser
        lock.unlock()
        browser.start(queue: queue)

        queue.asyncAfter(deadline: .now() + timeout) { [weak self, weak browser] in
            browser?.cancel()
            self?.lock.lock()
            if self?.pairingBrowser === browser {
                self?.pairingBrowser = nil
            }
            self?.lock.unlock()
            completion(targets)
        }
    }

    private func deduplicateRelayPingTargets(_ targets: [RelayPingTarget]) -> [RelayPingTarget] {
        var seen = Set<String>()
        var result: [RelayPingTarget] = []
        for target in targets {
            let key = target.label
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(target)
        }
        return result
    }

    private func storeRelayTarget(_ target: RelayPingTarget) {
        UserDefaults.standard.set(target.host, forKey: "universalControlRelayHost")
        UserDefaults.standard.set(Int(target.port.rawValue), forKey: "universalControlRelayPort")
        lock.lock()
        pairedRemoteEndpoint = target.endpoint
        pairedRemoteEndpointKey = target.label
        lock.unlock()
        NSLog("[UCMouseRelay] Stored relay target %@ over %@", target.label, target.source)
    }

    private func hasConfiguredRelayTargetLocked() -> Bool {
        if pairedRemoteEndpointKey != nil { return true }

        cacheLock.lock()
        if let cachedRelayTargetDefaultsConfigured {
            cacheLock.unlock()
            return cachedRelayTargetDefaultsConfigured
        }
        cacheLock.unlock()

        let configured = UserDefaults.standard.object(forKey: "universalControlRelayHost") != nil
            || UserDefaults.standard.object(forKey: "universalControlRelayPort") != nil
        cacheLock.lock()
        cachedRelayTargetDefaultsConfigured = configured
        cacheLock.unlock()
        return configured
    }

    private func tailscalePeerHosts() -> [String] {
        let candidates = [
            "/usr/local/bin/tailscale",
            "/opt/homebrew/bin/tailscale",
            "/Applications/Tailscale.app/Contents/MacOS/Tailscale"
        ]
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return []
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["status", "--json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            NSLog("[UCMouseRelay] Could not run tailscale status: %@", String(describing: error))
            return []
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let peers = object["Peer"] as? [String: Any] else {
            return []
        }

        var hosts: [String] = []
        for value in peers.values {
            guard let peer = value as? [String: Any] else { continue }
            if let os = peer["OS"] as? String, os.lowercased() != "macos" {
                continue
            }
            if let dnsName = peer["DNSName"] as? String, !dnsName.isEmpty {
                hosts.append(dnsName.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
            }
            if let hostName = peer["HostName"] as? String, !hostName.isEmpty {
                hosts.append(hostName)
            }
            if let ips = peer["TailscaleIPs"] as? [String] {
                hosts.append(contentsOf: ips)
            }
        }
        return hosts
    }

    private func isSelfTarget(host: String) -> Bool {
        let trimmed = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let lowercased = trimmed.lowercased()
        let hostNames = [
            Host.current().localizedName,
            Host.current().name,
            ProcessInfo.processInfo.hostName
        ]
        .compactMap { $0?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
        .filter { !$0.isEmpty }

        if lowercased == "localhost" || lowercased == "127.0.0.1" || lowercased == "::1" {
            return true
        }
        if hostNames.contains(lowercased.trimmingCharacters(in: CharacterSet(charactersIn: "."))) {
            return true
        }

        let localAddresses = localInterfaceAddresses()
        guard !localAddresses.isEmpty else { return false }
        let resolved = resolvedAddresses(for: trimmed)
        return !resolved.isDisjoint(with: localAddresses)
    }

    private func localInterfaceAddresses() -> Set<String> {
        var result = Set<String>()
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return result }
        defer { freeifaddrs(interfaces) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            guard let address = current.pointee.ifa_addr else { continue }
            let family = Int32(address.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }
            if let numeric = numericHost(from: address, length: socklen_t(address.pointee.sa_len)) {
                result.insert(numeric)
            }
        }

        return result
    }

    private func resolvedAddresses(for host: String) -> Set<String> {
        var result = Set<String>()
        var hints = addrinfo(
            ai_flags: 0,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &info) == 0, let first = info else { return result }
        defer { freeaddrinfo(info) }

        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let current = cursor {
            defer { cursor = current.pointee.ai_next }
            guard let address = current.pointee.ai_addr else { continue }
            if let numeric = numericHost(from: address, length: current.pointee.ai_addrlen) {
                result.insert(numeric)
            }
        }

        return result
    }

    private func numericHost(from address: UnsafePointer<sockaddr>, length: socklen_t) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let status = getnameinfo(
            address,
            length,
            &host,
            socklen_t(host.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        guard status == 0 else { return nil }
        return String(cString: host).components(separatedBy: "%").first
    }

    private func sendPairingPing(to target: RelayPingTarget, nonce: String) {
        let connection = NWConnection(to: target.connectionEndpoint, using: .tcp)
        let buffer = RelayPairingCheckBuffer()
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                NSLog("[UCMouseRelay] Sending pairing check to %@", target.label)
                receivePairingCheckResponse(on: connection, nonce: nonce, target: target, buffer: buffer)
                guard sendAuthenticatedLine("ping \(nonce)", on: connection) else {
                    connection.cancel()
                    NSLog("[UCMouseRelay] Could not send pairing check to %@", target.label)
                    return
                }
            case .failed(let error):
                connection.cancel()
                NSLog("[UCMouseRelay] Pairing check failed to %@: %@", target.label, error.localizedDescription)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func sendPairingHello(
        to target: RelayPingTarget,
        session: UniversalControlRelayPairingSession,
        completion: @escaping (Bool, String) -> Void
    ) {
        let connection = NWConnection(to: target.connectionEndpoint, using: .tcp)
        let buffer = RelayPairingCheckBuffer()
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                NSLog("[UCMouseRelay] Sending code pairing hello to %@", target.label)
                receivePairingHelloResponse(
                    on: connection,
                    target: target,
                    session: session,
                    buffer: buffer,
                    completion: completion
                )
                guard let data = "\(session.helloLine())\n".data(using: .utf8) else {
                    connection.cancel()
                    return
                }
                connection.send(content: data, completion: .contentProcessed { error in
                    if let error {
                        NSLog("[UCMouseRelay] Could not send code pairing hello: %@", String(describing: error))
                    }
                })
            case .failed(let error):
                connection.cancel()
                NSLog("[UCMouseRelay] Code pairing failed to %@: %@", target.label, error.localizedDescription)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receivePairingHelloResponse(
        on connection: NWConnection,
        target: RelayPingTarget,
        session: UniversalControlRelayPairingSession,
        buffer: RelayPairingCheckBuffer,
        completion: @escaping (Bool, String) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection else { return }
            if error != nil {
                return
            }
            if let data, !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                buffer.text += text
                if buffer.text.count > maxLineLength {
                    connection.cancel()
                    return
                }
                while let newline = buffer.text.firstIndex(of: "\n") {
                    let line = String(buffer.text[..<newline])
                    buffer.text.removeSubrange(...newline)
                    guard let response = parsePairingResponse(line),
                          let result = session.derive(
                            remotePeerID: response.peerID,
                            remotePublicKeyBase64: response.publicKeyBase64,
                            remoteNonce: response.nonce
                          ) else {
                        continue
                    }

                    lock.lock()
                    let alreadyPending = pendingOutgoingCodePairing != nil
                    if !alreadyPending {
                        pendingOutgoingCodePairing = OutgoingCodePairing(
                            target: target,
                            connection: connection,
                            code: result.code,
                            keyData: result.keyData
                        )
                        activeCodePairingSearchID = nil
                    }
                    lock.unlock()

                    if alreadyPending {
                        connection.cancel()
                    } else {
                        DispatchQueue.main.async {
                            completion(true, "Enter the 6-digit code shown on \(target.label).")
                        }
                    }
                    return
                }
            }
            if !isComplete {
                receivePairingHelloResponse(on: connection, target: target, session: session, buffer: buffer, completion: completion)
            }
        }
    }

    private func parsePairingResponse(_ line: String) -> (peerID: String, publicKeyBase64: String, nonce: String)? {
        let parts = line.split(separator: " ").map(String.init)
        guard parts.count == 5,
              parts[0] == UniversalControlRelayPairingSession.version,
              parts[1] == "response" else {
            return nil
        }
        return (parts[2], parts[3], parts[4])
    }

    private func receivePairingCheckResponse(
        on connection: NWConnection,
        nonce: String,
        target: RelayPingTarget,
        buffer: RelayPairingCheckBuffer
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection else { return }
            if error != nil {
                return
            }
            if let data, !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                buffer.text += text
                if buffer.text.count > maxLineLength {
                    connection.cancel()
                    return
                }
                while let newline = buffer.text.firstIndex(of: "\n") {
                    let line = String(buffer.text[..<newline])
                    buffer.text.removeSubrange(...newline)
                    guard let payload = openIncomingLine(line) else {
                        NSLog("[UCMouseRelay] Pairing check received unauthenticated response from %@", target.label)
                        continue
                    }
                    let parts = payload.split(separator: " ")
                    if parts.count == 2, parts[0] == "pong", String(parts[1]) == nonce {
                        storeRelayTarget(target)
                        connection.cancel()
                        completeRelayPing(
                            nonce,
                            success: true,
                            message: "Paired with \(target.label) over \(target.source)."
                        )
                        return
                    }
                }
            }
            if !isComplete {
                receivePairingCheckResponse(on: connection, nonce: nonce, target: target, buffer: buffer)
            }
        }
    }

    private func receivePairingFinalizeResponse(
		on connection: NWConnection,
		target: RelayPingTarget,
		keyData: Data,
		buffer: RelayPairingCheckBuffer,
		completion: @escaping (Bool, String) -> Void
    ) {
		connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self, weak connection] data, _, isComplete, error in
			guard let self, let connection else { return }
			if let error {
				NSLog("[UCMouseRelay] Pairing finalization receive failed: %@", String(describing: error))
				finishOutgoingPairing(
					connectionKey: ObjectIdentifier(connection),
					target: target,
					keyData: nil,
					success: false,
					message: "Pairing confirmation failed for \(target.label). Start pairing again.",
					completion: completion
				)
				return
			}
			if let data, !data.isEmpty, let text = String(data: data, encoding: .utf8) {
				buffer.text += text
				if buffer.text.count > maxLineLength {
					finishOutgoingPairing(
						connectionKey: ObjectIdentifier(connection),
						target: target,
						keyData: nil,
						success: false,
						message: "Pairing confirmation from \(target.label) was invalid. Start pairing again.",
						completion: completion
					)
					return
				}
				while let newline = buffer.text.firstIndex(of: "\n") {
					let line = String(buffer.text[..<newline])
					buffer.text.removeSubrange(...newline)
					guard let payload = openIncomingLine(line, secretData: keyData) else {
						NSLog("[UCMouseRelay] Pairing finalization received unauthenticated response from %@", target.label)
						continue
					}
					let parts = payload.split(separator: " ")
					guard parts.count == 2, parts[0] == "pairDone" else { continue }
					finishOutgoingPairing(
						connectionKey: ObjectIdentifier(connection),
						target: target,
						keyData: keyData,
						success: true,
						message: "Paired with \(target.label). Future connections will not need a code.",
						completion: completion
					)
					NSLog("[UCMouseRelay] Pairing confirmed by %@", String(parts[1]))
					return
				}
			}
			if !isComplete {
				receivePairingFinalizeResponse(
					on: connection,
					target: target,
					keyData: keyData,
					buffer: buffer,
					completion: completion
				)
			}
		}
    }

    private func finishOutgoingPairing(
		connectionKey: ObjectIdentifier,
		target: RelayPingTarget,
		keyData: Data?,
		success: Bool,
		message: String,
		completion: @escaping (Bool, String) -> Void
    ) {
		lock.lock()
		let connection = pendingOutgoingPairingFinalizers.removeValue(forKey: connectionKey)
		lock.unlock()
		guard let connection else { return }

		if success, let keyData {
			guard storeRelaySharedSecret(keyData) else {
				connection.cancel()
				DispatchQueue.main.async {
					completion(false, "Could not save pairing secret to Keychain. Start pairing again.")
				}
				return
			}
			storeRelayTarget(target)
		}
		connection.cancel()
		DispatchQueue.main.async {
			completion(success, message)
		}
    }

    private func receiveNextFromClient(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection else { return }
            if let error {
                NSLog("[UCMouseRelay] Client receive failed: %@", String(describing: error))
                return
            }
            if let data, !data.isEmpty, let text = String(data: data, encoding: .utf8) {
				appendClientIncoming(text, from: connection)
            }
            if !isComplete {
                receiveNextFromClient(on: connection)
            }
        }
    }

    private func appendClientIncoming(_ text: String, from connection: NWConnection) {
        var lines: [String] = []
        lock.lock()
        clientReceiveBuffer += text
        if clientReceiveBuffer.count > maxLineLength {
            clientReceiveBuffer = ""
            lock.unlock()
            NSLog("[UCMouseRelay] Dropped oversized client frame")
            return
        }
        while let newline = clientReceiveBuffer.firstIndex(of: "\n") {
            lines.append(String(clientReceiveBuffer[..<newline]))
            clientReceiveBuffer.removeSubrange(...newline)
        }
        lock.unlock()

        for line in lines {
			handleClient(line: line, from: connection)
        }
    }

    private func completeRelayPing(_ nonce: String, success: Bool, message: String) {
        lock.lock()
        let completion = pendingRelayPings.removeValue(forKey: nonce)
        lock.unlock()

        guard let completion else { return }
        DispatchQueue.main.async {
            completion(success, message)
        }
    }

    private func handleIncoming(_ connection: NWConnection) {
        lock.lock()
        guard incomingConnections.count < maxIncomingConnections else {
            lock.unlock()
            NSLog("[UCMouseRelay] Rejected extra incoming connection")
            connection.cancel()
            return
        }
        guard UniversalControlRelayNetworkPolicy.isAllowed(endpoint: connection.endpoint) else {
            lock.unlock()
            NSLog("[UCMouseRelay] Rejected non-local incoming connection: %@", String(describing: connection.endpoint))
            connection.cancel()
            return
        }
        incomingConnections.append(connection)
        incomingStates[ObjectIdentifier(connection)] = IncomingConnectionState()
        lock.unlock()

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let connection else { return }
            if case .ready = state {
				self?.sendConnectionCapabilities(on: connection)
                self?.receiveNext(on: connection)
            } else if case .failed(let error) = state {
                NSLog("[UCMouseRelay] Receive connection failed: %@", String(describing: error))
                self?.removeIncoming(connection)
            } else if case .cancelled = state {
                self?.removeIncoming(connection)
            }
        }
        connection.start(queue: queue)
    }

    private func receiveNext(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection else { return }
            if let error {
                NSLog("[UCMouseRelay] Receive failed: %@", String(describing: error))
                removeIncoming(connection)
                return
            }
            if let data, !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                appendIncoming(text, from: connection)
            }
            if isComplete {
                removeIncoming(connection)
            } else {
                receiveNext(on: connection)
            }
        }
    }

    private func appendIncoming(_ text: String, from connection: NWConnection) {
        let key = ObjectIdentifier(connection)

        lock.lock()
        var state = incomingStates[key] ?? IncomingConnectionState()
        var buffer = state.buffer + text
        if buffer.count > maxLineLength {
            incomingStates.removeValue(forKey: key)
            lock.unlock()
            NSLog("[UCMouseRelay] Closing connection with oversized frame")
            connection.cancel()
            return
        }
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: "\n") {
            lines.append(String(buffer[..<newline]))
            buffer.removeSubrange(...newline)
        }
        state.buffer = buffer
        incomingStates[key] = state
        lock.unlock()

        for line in lines {
            guard allowCommand(from: connection) else {
                NSLog("[UCMouseRelay] Closing rate-limited connection")
                connection.cancel()
                return
            }
            handle(line: line, from: connection)
        }
    }

    private func removeIncoming(_ connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        lock.lock()
        incomingConnections.removeAll { $0 === connection }
        incomingStates.removeValue(forKey: key)
        pendingIncomingCodePairings.removeValue(forKey: key)
        lock.unlock()
    }

    private func allowCommand(from connection: NWConnection) -> Bool {
        let key = ObjectIdentifier(connection)
        let now = Date()

        lock.lock()
        var state = incomingStates[key] ?? IncomingConnectionState()
        if now.timeIntervalSince(state.commandWindowStart) >= 1 {
            state.commandWindowStart = now
            state.commandCount = 0
        }
        state.commandCount += 1
        let allowed = state.commandCount <= maxCommandsPerSecond
        incomingStates[key] = state
        lock.unlock()

        return allowed
    }

    private func handle(line: String, from connection: NWConnection) {
        guard let payload = openIncomingLine(line) else {
            if handlePairingLine(line, from: connection) {
                return
            }
            NSLog("[UCMouseRelay] Rejected unauthenticated incoming command")
            return
        }
        let parts = payload.split(separator: " ")
        guard let command = parts.first else {
            return
        }

        if command == "ping" {
            guard parts.count == 2 else { return }
            _ = sendAuthenticatedLine("pong \(parts[1])", on: connection)
            NSLog("[UCMouseRelay] Replied to pairing ping")
            return
        }

		if command == "caps" {
			return
		}

        lock.lock()
        let input = receiverInput
		let handlesIncomingRemoteInput = UniversalControlRelayRolePolicy.handlesIncomingRemoteInput(
			acceptsRemoteInput: acceptsRemoteInput
		)
        let hasMouseButtonHeld = !remoteMouseButtonsHeld.isEmpty
        lock.unlock()
        defer {
			if handlesIncomingRemoteInput {
                sendRemoteUIState(on: connection)
            }
        }

        switch command {
        case "m":
            guard parts.count == 3,
                  let dx = Int(parts[1]),
                  let dy = Int(parts[2]) else { return }
			if handlesIncomingRemoteInput && !hasMouseButtonHeld {
				postRemoteMouseMove(dx: dx, dy: dy)
			} else if handlesIncomingRemoteInput {
                postRemoteMouseDrag(dx: dx, dy: dy)
            } else {
                input?.moveMouseNative(dx: dx, dy: dy)
            }
			if handlesIncomingRemoteInput {
                sendRemoteCursorStatus(on: connection)
            }
            logFirstReceive("move dx=\(dx) dy=\(dy)")
        case "bp":
			guard handlesIncomingRemoteInput,
                  parts.count == 2,
                  let button = ControllerButton(rawValue: String(parts[1])) else { return }
            Task { @MainActor in
                ServiceContainer.shared.mappingEngine.handleRemoteControllerButtonPressed(button)
            }
            logFirstReceive("button press \(button.rawValue)")
        case "br":
			guard handlesIncomingRemoteInput,
                  parts.count == 3,
                  let button = ControllerButton(rawValue: String(parts[1])),
                  let holdDuration = TimeInterval(String(parts[2])) else { return }
            Task { @MainActor in
                ServiceContainer.shared.mappingEngine.handleRemoteControllerButtonReleased(button, holdDuration: holdDuration)
            }
            logFirstReceive("button release \(button.rawValue)")
        case "bc":
			guard handlesIncomingRemoteInput, parts.count >= 3 else { return }
            var buttons = Set<ControllerButton>()
            for rawButton in parts.dropFirst() {
                guard let button = ControllerButton(rawValue: String(rawButton)) else { return }
                buttons.insert(button)
            }
            guard buttons.count == parts.count - 1 else { return }
            Task { @MainActor in
                ServiceContainer.shared.mappingEngine.handleRemoteControllerChord(buttons)
            }
            logFirstReceive("button chord")
        case "bclear":
			guard handlesIncomingRemoteInput, parts.count == 1 else { return }
            Task { @MainActor in
                ServiceContainer.shared.mappingEngine.resetRemoteControllerInputState()
            }
            logFirstReceive("button clear")
        case "kp":
            guard parts.count == 3,
                  let keyCode = UInt16(parts[1]),
                  let flagsRaw = UInt64(parts[2]) else { return }
			if handlesIncomingRemoteInput && KeyCodeMapping.isMouseButton(CGKeyCode(keyCode)) {
                postRemoteMouseButton(keyCode: CGKeyCode(keyCode), down: true)
                postRemoteMouseButton(keyCode: CGKeyCode(keyCode), down: false)
            } else {
                input?.pressKey(CGKeyCode(keyCode), modifiers: CGEventFlags(rawValue: flagsRaw))
            }
            logFirstReceive("key press \(keyCode)")
		case "kp2":
			guard parts.count == 7,
				  let keyCode = UInt16(parts[1]),
				  let flagsRaw = UInt64(parts[2]) else { return }
			let flags = CGEventFlags(rawValue: flagsRaw)
			let modifiers = ModifierFlags(
				command: flags.contains(.maskCommand),
				option: flags.contains(.maskAlternate),
				shift: flags.contains(.maskShift),
				control: flags.contains(.maskControl),
				commandSide: Self.modifierSide(from: parts[3]),
				optionSide: Self.modifierSide(from: parts[4]),
				shiftSide: Self.modifierSide(from: parts[5]),
				controlSide: Self.modifierSide(from: parts[6])
			)
			if handlesIncomingRemoteInput && KeyCodeMapping.isMouseButton(CGKeyCode(keyCode)) {
				postRemoteMouseButton(keyCode: CGKeyCode(keyCode), down: true)
				postRemoteMouseButton(keyCode: CGKeyCode(keyCode), down: false)
			} else {
				input?.pressKey(CGKeyCode(keyCode), modifiers: modifiers)
			}
			logFirstReceive("side-aware key press \(keyCode)")
        case "kd":
            guard parts.count == 3,
                  let keyCode = UInt16(parts[1]),
                  let flagsRaw = UInt64(parts[2]) else { return }
			if handlesIncomingRemoteInput && KeyCodeMapping.isMouseButton(CGKeyCode(keyCode)) {
                postRemoteMouseButton(keyCode: CGKeyCode(keyCode), down: true)
            } else {
				let cgKeyCode = CGKeyCode(keyCode)
				updateRemoteMouseButtonState(keyCode: cgKeyCode, isDown: true)
				if KeyCodeMapping.isModifierKey(cgKeyCode) {
					input?.holdModifierKey(cgKeyCode)
				} else {
					input?.keyDown(cgKeyCode, modifiers: CGEventFlags(rawValue: flagsRaw))
				}
            }
            logFirstReceive("key down \(keyCode)")
        case "ku":
            guard parts.count == 2,
                  let keyCode = UInt16(parts[1]) else { return }
			if handlesIncomingRemoteInput && KeyCodeMapping.isMouseButton(CGKeyCode(keyCode)) {
                postRemoteMouseButton(keyCode: CGKeyCode(keyCode), down: false)
            } else {
				let cgKeyCode = CGKeyCode(keyCode)
				updateRemoteMouseButtonState(keyCode: cgKeyCode, isDown: false)
				if KeyCodeMapping.isModifierKey(cgKeyCode) {
					input?.releaseModifierKey(cgKeyCode)
				} else {
					input?.keyUp(cgKeyCode)
				}
            }
            logFirstReceive("key up \(keyCode)")
        case "hm":
            guard parts.count == 2,
                  let flagsRaw = UInt64(parts[1]) else { return }
            input?.holdModifier(CGEventFlags(rawValue: flagsRaw))
            logFirstReceive("hold modifier")
        case "rm":
            guard parts.count == 2,
                  let flagsRaw = UInt64(parts[1]) else { return }
            input?.releaseModifier(CGEventFlags(rawValue: flagsRaw))
            logFirstReceive("release modifier")
        case "ra":
            input?.releaseAllModifiers()
            logFirstReceive("release all modifiers")
        case "sc":
            guard parts.count == 7,
                  let dx = Double(parts[1]),
                  let dy = Double(parts[2]),
                  let phaseRaw = Int32(parts[3]),
                  let momentumRaw = Int32(parts[4]),
                  let continuousRaw = Int(parts[5]),
                  let flagsRaw = UInt64(parts[6]) else { return }
            input?.scroll(event: ScrollEvent(
                dx: CGFloat(dx),
                dy: CGFloat(dy),
                phase: phaseRaw >= 0 ? CGScrollPhase(rawValue: UInt32(phaseRaw)) : nil,
                momentumPhase: momentumRaw >= 0 ? CGMomentumScrollPhase(rawValue: UInt32(momentumRaw)) : nil,
                isContinuous: continuousRaw != 0,
                flags: CGEventFlags(rawValue: flagsRaw)
            ))
            logFirstReceive("scroll dx=\(dx) dy=\(dy)")
        case "tt":
            guard parts.count == 4,
                  let data = Data(base64Encoded: String(parts[1])),
                  let text = String(data: data, encoding: .utf8),
                  let speed = Int(parts[2]),
                  let enterRaw = Int(parts[3]) else { return }
            input?.typeText(text, speed: speed, pressEnter: enterRaw != 0)
            logFirstReceive("type text")
        case "sys":
            NSLog("[UCMouseRelay] Ignored remote system command")
            return
        case "ui":
            guard parts.count == 4,
                  let button = ControllerButton(rawValue: String(parts[2])),
                  let holdRaw = Int(parts[3]) else { return }
            let action = String(parts[1])
            let holdMode = holdRaw != 0
            Task { @MainActor in
                let engine = ServiceContainer.shared.mappingEngine
                switch action {
                case "oskPress":
                    engine.handleOnScreenKeyboardPressed(button, holdMode: holdMode)
                case "oskRelease":
                    engine.handleOnScreenKeyboardReleased(button)
                case "oskNavigate":
                    OnScreenKeyboardManager.shared.handleDPadNavigation(button)
                case "oskActivate":
                    OnScreenKeyboardManager.shared.activateHighlightedKey()
                case "swipeNavigate":
                    if button == .dpadRight {
                        SwipeTypingEngine.shared.selectNextPrediction()
                    } else if button == .dpadLeft {
                        SwipeTypingEngine.shared.selectPreviousPrediction()
                    }
                case "swipeConfirm":
                    if let word = SwipeTypingEngine.shared.confirmSelection() {
                        OnScreenKeyboardManager.shared.typeSwipedWord(word)
                    }
                case "swipeCancel":
                    SwipeTypingEngine.shared.deactivateMode()
                case "laserPress":
                    engine.handleLaserPointerPressed(button, holdMode: holdMode)
                case "laserRelease":
                    engine.handleLaserPointerReleased(button)
                case "navPress":
                    engine.handleDirectoryNavigatorPressed(button, holdMode: holdMode)
                case "navRelease":
                    engine.handleDirectoryNavigatorReleased(button)
                case "dirNavigate":
                    DirectoryNavigatorManager.shared.handleDPadNavigation(button)
                case "dirConfirm":
                    DirectoryNavigatorManager.shared.dismissAndCd()
                case "dirDismiss":
                    DirectoryNavigatorManager.shared.hide()
                case "wheelPress":
                    engine.handleCommandWheelPressed(button, holdMode: holdMode)
                case "wheelRelease":
                    engine.handleCommandWheelReleased(button)
                default:
                    break
                }
                self.sendRemoteUIState(on: connection)
            }
            logFirstReceive("ui \(action)")
        case "wheel":
            guard parts.count == 4,
                  let stickX = Double(parts[1]),
                  let stickY = Double(parts[2]),
                  let alternateRaw = Int(parts[3]) else { return }
            Task { @MainActor in
                CommandWheelManager.shared.setShowingAlternate(alternateRaw != 0)
                CommandWheelManager.shared.updateSelection(stickX: stickX, stickY: stickY)
            }
            logFirstReceive("wheel update")
        case "focus":
            guard parts.count == 2,
                  let activeRaw = Int(parts[1]) else { return }
            Task { @MainActor in
                if activeRaw != 0 {
                    FocusModeIndicator.shared.show()
                } else {
                    FocusModeIndicator.shared.hide()
                }
            }
            logFirstReceive("focus mode")
        case "swipeMode":
            guard parts.count == 2,
                  let activeRaw = Int(parts[1]) else { return }
            if activeRaw != 0 {
                SwipeTypingEngine.shared.activateMode()
            } else {
                SwipeTypingEngine.shared.deactivateMode()
            }
            logFirstReceive("swipe mode")
        case "swipeBegin":
            Task { @MainActor in
                self.beginRemoteSwipe()
            }
            logFirstReceive("swipe begin")
        case "swipeEnd":
            SwipeTypingEngine.shared.endSwipe()
            logFirstReceive("swipe end")
        case "swipeStick":
            guard parts.count == 4,
                  let x = Double(parts[1]),
                  let y = Double(parts[2]),
                  let sensitivity = Double(parts[3]) else { return }
            SwipeTypingEngine.shared.updateCursorFromJoystick(
                x: x,
                y: y,
                sensitivity: sensitivity
            )
            logFirstReceive("swipe stick")
        case "swipeTouch":
            guard parts.count == 4,
                  let dx = Double(parts[1]),
                  let dy = Double(parts[2]),
                  let sensitivity = Double(parts[3]) else { return }
            SwipeTypingEngine.shared.updateCursorFromTouchpadDelta(
                dx: dx,
                dy: dy,
                sensitivity: sensitivity
            )
            logFirstReceive("swipe touch")
        case "fb":
            guard parts.count == 4,
                  let actionData = Data(base64Encoded: String(parts[1])),
                  let action = String(data: actionData, encoding: .utf8),
                  let typeData = Data(base64Encoded: String(parts[2])),
                  let typeRaw = String(data: typeData, encoding: .utf8),
                  let type = InputEventType(rawValue: typeRaw),
                  let heldRaw = Int(parts[3]) else { return }
            Task { @MainActor in
                ActionFeedbackIndicator.shared.show(action: action, type: type, isHeld: heldRaw != 0)
            }
            logFirstReceive("feedback")
        case "fd":
            guard parts.count == 2 else { return }
            let action: String?
            if parts[1] == "-" {
                action = nil
            } else if let data = Data(base64Encoded: String(parts[1])),
                      let decoded = String(data: data, encoding: .utf8) {
                action = decoded
            } else {
                return
            }
            Task { @MainActor in
                ActionFeedbackIndicator.shared.dismissHeld(action: action)
            }
            logFirstReceive("dismiss feedback")
        case "portal":
            guard parts.count == 3,
                  let entryEdge = HandoffEdge(rawValue: String(parts[1])),
                  let returnEdge = HandoffEdge(rawValue: String(parts[2])) else { return }
            Task { @MainActor in
                UniversalControlPortalIndicator.shared.showRemoteEntry(
                    entryEdge: entryEdge,
                    returnEdge: returnEdge
                )
            }
            logFirstReceive("portal")
        case "portalEnd":
            Task { @MainActor in
                UniversalControlPortalIndicator.shared.clearRemoteReturnHint()
            }
            logFirstReceive("portal end")
        case "portalExit":
            guard parts.count == 2,
                  let edge = HandoffEdge(rawValue: String(parts[1])) else { return }
            Task { @MainActor in
                UniversalControlPortalIndicator.shared.showRemoteExit(edge: edge)
            }
            logFirstReceive("portal exit")
        default:
            return
        }
    }

    private func handlePairingLine(_ line: String, from connection: NWConnection) -> Bool {
        if let hello = parsePairingHello(line) {
            handlePairingHello(hello, from: connection)
            return true
        }

        let key = ObjectIdentifier(connection)
        lock.lock()
        let pending = pendingIncomingCodePairings[key]
        lock.unlock()
        guard let pending else { return false }

        guard pending.expiresAt > Date() else {
            lock.lock()
            pendingIncomingCodePairings.removeValue(forKey: key)
            lock.unlock()
            NSLog("[UCMouseRelay] Pairing expired")
            return true
        }

        guard let payload = openIncomingLine(line, secretData: pending.keyData) else {
            var shouldCancel = false
            lock.lock()
            if var updated = pendingIncomingCodePairings[key] {
                updated.attempts += 1
                shouldCancel = updated.attempts >= 3
                if shouldCancel {
                    pendingIncomingCodePairings.removeValue(forKey: key)
                } else {
                    pendingIncomingCodePairings[key] = updated
                }
            }
            lock.unlock()
            if shouldCancel {
                connection.cancel()
            }
            return true
        }

        let parts = payload.split(separator: " ")
        guard parts.count == 2, parts[0] == "pairFinish" else { return true }

		guard storeRelaySharedSecret(pending.keyData) else {
			lock.lock()
			pendingIncomingCodePairings.removeValue(forKey: key)
			if activeIncomingPairingPrompt?.peerID == pending.peerID {
				activeIncomingPairingPrompt = nil
			}
			lock.unlock()
			connection.cancel()
			return true
		}
        lock.lock()
        pendingIncomingCodePairings.removeValue(forKey: key)
        if activeIncomingPairingPrompt?.peerID == pending.peerID {
            activeIncomingPairingPrompt = nil
        }
        lock.unlock()
        _ = sendAuthenticatedLine("pairDone \(localRelayPeerID())", on: connection)
        NSLog("[UCMouseRelay] Pairing completed with %@", String(parts[1]))
        return true
    }

    private func parsePairingHello(_ line: String) -> (peerID: String, publicKeyBase64: String, nonce: String)? {
        let parts = line.split(separator: " ").map(String.init)
        guard parts.count == 5,
              parts[0] == UniversalControlRelayPairingSession.version,
              parts[1] == "hello" else {
            return nil
        }
        return (parts[2], parts[3], parts[4])
    }

    private func handlePairingHello(
        _ hello: (peerID: String, publicKeyBase64: String, nonce: String),
        from connection: NWConnection
    ) {
        let session = UniversalControlRelayPairingSession(localPeerID: localRelayPeerID())
		guard let generatedResponse = session.responseLine(
            remotePeerID: hello.peerID,
            remotePublicKeyBase64: hello.publicKeyBase64,
            remoteNonce: hello.nonce
        ),
				let generatedResult = session.derive(
                remotePeerID: hello.peerID,
                remotePublicKeyBase64: hello.publicKeyBase64,
                remoteNonce: hello.nonce,
                localIsFirst: false
				) else {
            return
        }

		let now = Date()
		var responseLine = generatedResponse
		var code = generatedResult.code
		var keyData = generatedResult.keyData
		var expiresAt = now.addingTimeInterval(60)
        var shouldShowPrompt = true
        lock.lock()
        if let prompt = activeIncomingPairingPrompt,
           prompt.peerID == hello.peerID,
			prompt.remotePublicKeyBase64 == hello.publicKeyBase64,
			prompt.remoteNonce == hello.nonce,
			prompt.expiresAt > now {
			responseLine = prompt.responseLine
			code = prompt.code
			keyData = prompt.keyData
			expiresAt = prompt.expiresAt
            shouldShowPrompt = false
        } else {
            activeIncomingPairingPrompt = IncomingPairingPrompt(
                peerID: hello.peerID,
				remotePublicKeyBase64: hello.publicKeyBase64,
				remoteNonce: hello.nonce,
				code: generatedResult.code,
				keyData: generatedResult.keyData,
				responseLine: generatedResponse,
                expiresAt: expiresAt
            )
        }
		pendingIncomingCodePairings[ObjectIdentifier(connection)] = IncomingCodePairing(
			peerID: hello.peerID,
			keyData: keyData,
			expiresAt: expiresAt,
			attempts: 0
		)
        lock.unlock()

        if shouldShowPrompt {
			showPairingCode(code, peerID: hello.peerID)
		} else {
			NSLog("[UCMouseRelay] Reused active pairing code for %@", hello.peerID)
		}
		guard let data = "\(responseLine)\n".data(using: .utf8) else {
			return
        }
        connection.send(content: data, completion: .contentProcessed { error in
            if let error {
                NSLog("[UCMouseRelay] Could not send pairing response: %@", String(describing: error))
            }
        })
    }

    private func showPairingCode(_ code: String, peerID: String) {
		DispatchQueue.main.async {
			UniversalControlPairingCodePresenter.shared.show(code: code, peerID: peerID)
		}
    }

    private func handleClient(line: String, from connection: NWConnection) {
        guard let payload = openIncomingLine(line) else {
            NSLog("[UCMouseRelay] Rejected unauthenticated client response")
            return
        }
        let parts = payload.split(separator: " ")
        guard let command = parts.first else { return }

		if command == "caps" {
			recordPeerCapabilities(from: parts, on: connection)
			return
		}

        if command == "pong" {
            guard parts.count == 2 else { return }
            completeRelayPing(
                String(parts[1]),
                success: true,
                message: "Secret synced. \(defaultRemoteHost):\(defaultRemotePort.rawValue) returned an authenticated response."
            )
            return
        }

        if command == "uiState" {
            guard parts.count == 5 || parts.count == 6,
                  let keyboardRaw = Int(parts[1]),
                  let navigationRaw = Int(parts[2]),
                  let directoryRaw = Int(parts[3]),
                  let swipeRaw = Int(parts[4]) else { return }
            lock.lock()
            remoteKeyboardVisible = keyboardRaw != 0
            remoteKeyboardNavigationModeActive = navigationRaw != 0
            remoteDirectoryNavigatorVisible = directoryRaw != 0
            remoteSwipePredictionsVisible = swipeRaw != 0
            if !remoteKeyboardVisible {
                remoteKeyboardButton = nil
                remoteKeyboardHoldMode = false
            }
            if !remoteDirectoryNavigatorVisible {
                remoteDirectoryNavigatorButton = nil
                remoteDirectoryNavigatorHoldMode = false
            }
            lock.unlock()
            return
        }

        guard parts.count >= 4,
              command == "pos",
              let x = Double(parts[1]),
              let y = Double(parts[2]),
              let displayCount = Int(parts[3]),
              parts.count == 4 + displayCount * 4 else { return }

        var displays: [CGRect] = []
        for index in 0..<displayCount {
            let offset = 4 + index * 4
            guard let minX = Double(parts[offset]),
                  let maxX = Double(parts[offset + 1]),
                  let minY = Double(parts[offset + 2]),
                  let maxY = Double(parts[offset + 3]) else { return }
            displays.append(CGRect(
                x: minX,
                y: minY,
                width: max(0, maxX - minX),
                height: max(0, maxY - minY)
            ))
        }

        lock.lock()
        remoteCursorStatus = RemoteCursorStatus(
            point: CGPoint(x: x, y: y),
            displays: displays,
            receivedAt: Date()
        )
		remoteSessionReceivedCursorStatus = true
        let pendingPortal = pendingHandoffPortal
        pendingHandoffPortal = nil
        lock.unlock()

        if let pendingPortal {
            showConfirmedHandoffPortal(for: pendingPortal)
        }
    }

	private func sendConnectionCapabilities(on connection: NWConnection) {
		_ = sendAuthenticatedLine(UniversalControlRelayKeyPressEncoding.capabilityLine, on: connection)
	}

	private func recordPeerCapabilities(from parts: [Substring], on connection: NWConnection) {
		guard UniversalControlRelayKeyPressEncoding.supportsSideAwareKeyPress(parts) else {
			return
		}
		lock.lock()
		if client === connection {
			peerSupportsKP2 = true
		}
		lock.unlock()
	}

    private func sendRemoteCursorStatus(on connection: NWConnection) {
		let point = UniversalControlRemoteMouseMovementPolicy.statusPoint(
			current: currentRemoteCGPoint(),
			bounds: remoteScreenBounds()
		)
        let displays = remoteDisplayBounds()
        let displayPayload = displays.map {
            "\(Double($0.minX)) \(Double($0.maxX)) \(Double($0.minY)) \(Double($0.maxY))"
        }.joined(separator: " ")
        guard let sealed = sealOutgoingLine("pos \(Double(point.x)) \(Double(point.y)) \(displays.count) \(displayPayload)"),
              let data = "\(sealed)\n".data(using: .utf8) else { return }
        connection.send(content: data, completion: .contentProcessed { error in
            if let error {
                NSLog("[UCMouseRelay] Could not send cursor status: %@", String(describing: error))
            }
        })
    }

    private func sendRemoteUIState(on connection: NWConnection) {
        let payload = UniversalControlRelayUIStateEchoPolicy.payload(
            keyboardVisible: OnScreenKeyboardManager.shared.threadSafeIsVisible,
            keyboardNavigationActive: OnScreenKeyboardManager.shared.threadSafeNavigationModeActive,
            directoryNavigatorVisible: DirectoryNavigatorManager.shared.threadSafeIsVisible,
            swipePredictionsVisible: SwipeTypingEngine.shared.threadSafeState == .showingPredictions
        )

        let key = ObjectIdentifier(connection)
        lock.lock()
        guard UniversalControlRelayUIStateEchoPolicy.shouldSend(
            payload: payload,
            lastSentPayload: incomingStates[key]?.lastUIStatePayload
        ) else {
            lock.unlock()
            return
        }
        if var state = incomingStates[key] {
            state.lastUIStatePayload = payload
            incomingStates[key] = state
        }
        lock.unlock()

        guard let sealed = sealOutgoingLine(payload),
              let data = "\(sealed)\n".data(using: .utf8) else { return }
        connection.send(content: data, completion: .contentProcessed { error in
            if let error {
                NSLog("[UCMouseRelay] Could not send UI state: %@", String(describing: error))
            }
        })
    }

    @MainActor
    private func beginRemoteSwipe() {
        let letterArea = OnScreenKeyboardManager.shared.threadSafeLetterAreaScreenRect
        if letterArea.width > 0, letterArea.height > 0,
           let mouseEvent = CGEvent(source: nil) {
            let quartz = mouseEvent.location
            let screenHeight = CGFloat(CGDisplayPixelsHigh(CGMainDisplayID()))
            let cocoaX = quartz.x
            let cocoaY = screenHeight - quartz.y
            let normalized = CGPoint(
                x: (cocoaX - letterArea.origin.x) / letterArea.width,
                y: 1.0 - (cocoaY - letterArea.origin.y) / letterArea.height
            )
            SwipeTypingEngine.shared.setCursorPosition(normalized)
        }
        SwipeTypingEngine.shared.beginSwipe()
    }

    private func updateRemoteMouseButtonState(keyCode: CGKeyCode, isDown: Bool) {
        guard KeyCodeMapping.isMouseButton(keyCode) else { return }
        let (_, button) = mouseEventType(for: keyCode, down: isDown)
        lock.lock()
        if isDown {
            remoteMouseButtonsHeld.insert(button)
        } else {
            remoteMouseButtonsHeld.remove(button)
        }
        lock.unlock()
    }

    private func updateOutgoingRemoteMouseButtonState(keyCode: CGKeyCode, isDown: Bool) {
        guard KeyCodeMapping.isMouseButton(keyCode) else { return }
        let (_, button) = mouseEventType(for: keyCode, down: isDown)
        lock.lock()
        if isDown {
            outgoingRemoteMouseButtonsHeld.insert(button)
        } else {
            outgoingRemoteMouseButtonsHeld.remove(button)
        }
        lock.unlock()
    }

    private func mouseEventType(for keyCode: CGKeyCode, down: Bool) -> (CGEventType, CGMouseButton) {
        KeyCodeMapping.mouseEventType(for: keyCode, down: down)
    }

    private func logFirstReceive(_ description: String) {
        lock.lock()
        let shouldLog = !didLogFirstReceive
        didLogFirstReceive = true
        lock.unlock()
        if shouldLog {
            NSLog("[UCMouseRelay] Received first %@", description)
        }
    }

    private func postRemoteMouseMove(dx: Int, dy: Int) {
		let movement = boundedRemoteMovement(dx: dx, dy: dy)
		guard movement.shouldPostEvent else { return }

		CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
		restoreRemoteCursorVisibilityIfNeeded()

		guard let event = CGEvent(
			mouseEventSource: remoteMouseEventSource,
			mouseType: .mouseMoved,
			mouseCursorPosition: movement.point,
			mouseButton: .left
		) else {
			NSLog("[UCMouseRelay] Could not create remote mouse move event")
			CGWarpMouseCursorPosition(movement.point)
			return
		}
		event.setIntegerValueField(.mouseEventDeltaX, value: Int64(movement.dx))
		event.setIntegerValueField(.mouseEventDeltaY, value: Int64(movement.dy))
		event.post(tap: .cghidEventTap)
    }

    private func postRemoteMouseButton(keyCode: CGKeyCode, down: Bool) {
		restoreRemoteCursorVisibilityIfNeeded()

        let (type, button) = mouseEventType(for: keyCode, down: down)
        let location = currentRemoteCGPoint()
        let clickCount: Int64

        lock.lock()
        if down {
            remoteMouseButtonsHeld.insert(button)
            remoteMouseEventNumber += 1

            let now = Date()
            if let lastTime = remoteLastClickTime[button],
               now.timeIntervalSince(lastTime) < Config.multiClickThreshold {
                clickCount = (remoteClickCounts[button] ?? 0) + 1
            } else {
                clickCount = 1
            }
            remoteClickCounts[button] = clickCount
            remoteLastClickTime[button] = now
        } else {
            remoteMouseButtonsHeld.remove(button)
            clickCount = remoteClickCounts[button] ?? 1
        }
        let eventNumber = remoteMouseEventNumber
        lock.unlock()

        CGWarpMouseCursorPosition(location)

        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: location,
            mouseButton: button
        ) else {
            NSLog("[UCMouseRelay] Could not create remote mouse button event")
            return
        }
        event.setIntegerValueField(.mouseEventClickState, value: clickCount)
        event.setIntegerValueField(.mouseEventNumber, value: eventNumber)
        event.setIntegerValueField(.mouseEventDeltaX, value: 0)
        event.setIntegerValueField(.mouseEventDeltaY, value: 0)
        event.setDoubleValueField(.mouseEventPressure, value: down ? 1.0 : 0.0)
        event.post(tap: .cghidEventTap)
    }

    private func postRemoteMouseDrag(dx: Int, dy: Int) {
		restoreRemoteCursorVisibilityIfNeeded()

        lock.lock()
        let button = remoteMouseButtonsHeld.first ?? .left
        let eventNumber = remoteMouseEventNumber
        lock.unlock()

        let type: CGEventType
        switch button {
        case .right:
            type = .rightMouseDragged
        case .center:
            type = .otherMouseDragged
        default:
            type = .leftMouseDragged
        }

		let movement = boundedRemoteMovement(dx: dx, dy: dy)
		guard movement.shouldPostEvent else { return }

		guard let event = CGEvent(
			mouseEventSource: nil,
			mouseType: type,
			mouseCursorPosition: movement.point,
			mouseButton: button
		) else {
			NSLog("[UCMouseRelay] Could not create remote mouse drag event")
			return
		}
		event.setIntegerValueField(.mouseEventNumber, value: eventNumber)
		event.setIntegerValueField(.mouseEventDeltaX, value: Int64(movement.dx))
		event.setIntegerValueField(.mouseEventDeltaY, value: Int64(movement.dy))
		event.setDoubleValueField(.mouseEventPressure, value: 1.0)
		event.post(tap: .cghidEventTap)
		CGWarpMouseCursorPosition(movement.point)
    }

    private func restoreRemoteCursorVisibilityIfNeeded() {
		let now = CFAbsoluteTimeGetCurrent()
		lock.lock()
		let decision = RemoteCursorVisibilityRestorePolicy.decision(
			now: now,
			lastRestoreAt: lastRemoteCursorVisibilityRestoreAt
		)
		guard decision.shouldRestore else {
			lock.unlock()
			return
		}
		lastRemoteCursorVisibilityRestoreAt = now
		lock.unlock()

		Task { @MainActor in
			OnScreenKeyboardManager.shared.restoreCursorVisibilityForRemotePointer(
				repairPotentialStaleHide: decision.shouldRepairPotentialStaleHide
			)
		}
    }

    private func resetRemoteCursorVisibilityRestoreStateLocked() {
		lastRemoteCursorVisibilityRestoreAt = nil
    }

    private func currentRemoteCGPoint() -> CGPoint {
        if let event = CGEvent(source: nil) {
            return event.location
        }

        let bounds = remoteScreenBounds()
        guard bounds != .zero else { return .zero }

        let screenHeight = bounds.height
        let current = NSEvent.mouseLocation
        return CGPoint(x: current.x, y: screenHeight - current.y)
    }

    private func boundedRemoteMovement(dx: Int, dy: Int) -> UniversalControlRemoteMouseMovementPolicy.Movement {
		UniversalControlRemoteMouseMovementPolicy.boundedMovement(
			current: currentRemoteCGPoint(),
			requestedDX: dx,
			requestedDY: dy,
			bounds: remoteScreenBounds()
		)
    }

    private func remoteScreenBounds() -> CGRect {
        let displays = remoteDisplayBounds()
        let bounds = displays.reduce(CGRect.null) { result, display in
            result.union(display)
        }
        if !bounds.isNull {
            return bounds
        }
        return NSScreen.main?.frame ?? .zero
    }

    private func remoteDisplayBounds() -> [CGRect] {
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetActiveDisplayList(displayCount, &displays, &displayCount)

        let bounds = displays.map { CGDisplayBounds($0) }
        if !bounds.isEmpty {
            return bounds
        }
        return NSScreen.screens.map(\.frame)
    }

    private func relaySharedSecretData() -> Data {
        if let configured = UserDefaults.standard.string(forKey: relaySharedSecretDefaultsKey),
           let data = Self.decodeRelaySecret(configured) {
			let normalized = data.base64EncodedString()
			if KeychainService.storePassword(
				normalized,
                key: relaySecretKey,
                service: relaySecretKeychainService
			) != nil {
				UserDefaults.standard.removeObject(forKey: relaySharedSecretDefaultsKey)
			} else {
				NSLog("[UCMouseRelay] Failed to migrate relay secret to Keychain")
			}
            return data
        }

        if let stored = KeychainService.retrievePassword(
            key: relaySecretKey,
            service: relaySecretKeychainService
        ), let data = Data(base64Encoded: stored), data.count >= 32 {
            return data
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let data = Data(bytes)
		if KeychainService.storePassword(
            data.base64EncodedString(),
            key: relaySecretKey,
            service: relaySecretKeychainService
		) == nil {
			NSLog("[UCMouseRelay] Failed to persist generated relay secret to Keychain")
		}
        return data
    }

    @discardableResult
    private func storeRelaySharedSecret(_ data: Data) -> Bool {
        let normalized = data.base64EncodedString()
		guard KeychainService.storePassword(
            normalized,
            key: relaySecretKey,
            service: relaySecretKeychainService
		) != nil else {
			NSLog("[UCMouseRelay] Failed to persist relay secret to Keychain")
			return false
		}
		UserDefaults.standard.removeObject(forKey: relaySharedSecretDefaultsKey)
        resetAuthenticator(secretData: data)
		return true
    }

    private func relaySharedSecretBase64() -> String {
        relaySharedSecretData().base64EncodedString()
    }

    private func localRelayPeerID() -> String {
        if let existing = UserDefaults.standard.string(forKey: relayPeerIDDefaultsKey),
           !existing.isEmpty {
            return existing
        }
        let peerID = UUID().uuidString
        UserDefaults.standard.set(peerID, forKey: relayPeerIDDefaultsKey)
        return peerID
    }

    private static func decodeRelaySecret(_ value: String) -> Data? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = Data(base64Encoded: trimmed), data.count >= 32 {
            return data
        }

        let hex = trimmed.filter { !$0.isWhitespace && $0 != ":" && $0 != "-" }
        guard hex.count >= 64, hex.count.isMultiple(of: 2) else { return nil }

        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }

    private func configuredHandoffZones() -> [HandoffZone] {
        cacheLock.lock()
        if let cachedHandoffZones {
            cacheLock.unlock()
            return cachedHandoffZones
        }
        cacheLock.unlock()

        let zones = loadConfiguredHandoffZones()
        cacheLock.lock()
        cachedHandoffZones = zones
        cacheLock.unlock()
        return zones
    }

    private func loadConfiguredHandoffZones() -> [HandoffZone] {
        if let data = UserDefaults.standard.data(forKey: "universalControlRelayHandoffZones"),
           let zones = try? JSONDecoder().decode([HandoffZone].self, from: data),
           !zones.isEmpty {
            return zones
        }
        if let json = UserDefaults.standard.string(forKey: "universalControlRelayHandoffZones"),
           let data = json.data(using: .utf8),
           let zones = try? JSONDecoder().decode([HandoffZone].self, from: data),
           !zones.isEmpty {
            return zones
        }

        let configuredLocalEdge = UserDefaults.standard.string(forKey: "universalControlRelayLocalEdge")
        let remoteEntryRaw = UserDefaults.standard.string(forKey: "universalControlRelayRemoteEntryEdge")
        let remoteReturnRaw = UserDefaults.standard.string(forKey: "universalControlRelayRemoteReturnEdge")
        let remotePort = UInt16(defaultRemotePort.rawValue)

        func defaultZone(for localEdge: HandoffEdge) -> HandoffZone {
            let remoteEntryEdge = remoteEntryRaw.flatMap(HandoffEdge.init(rawValue:)) ?? localEdge.opposite
            let remoteReturnEdge = remoteReturnRaw.flatMap(HandoffEdge.init(rawValue:)) ?? remoteEntryEdge
            return HandoffZone(
                localDisplayID: nil,
                localEdge: localEdge,
                localRangeMin: nil,
                localRangeMax: nil,
                remoteHost: defaultRemoteHost,
                remotePort: remotePort,
                remoteEntryEdge: remoteEntryEdge,
                remoteReturnEdge: remoteReturnEdge
            )
        }

		return UniversalControlHandoffEdgeDefaults.localEdges(configuredRawValue: configuredLocalEdge)
			.map(defaultZone)
    }

    private func localDisplays() -> [LocalDisplay] {
        cacheLock.lock()
        if let cachedLocalDisplays {
            cacheLock.unlock()
            return cachedLocalDisplays
        }
        cacheLock.unlock()

        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetActiveDisplayList(displayCount, &displayIDs, &displayCount)
        let displays = displayIDs.map { LocalDisplay(id: $0, bounds: CGDisplayBounds($0)) }
        cacheLock.lock()
        cachedLocalDisplays = displays
        cacheLock.unlock()
        return displays
    }

    private func isMovingOutward(dx: Int, dy: Int, through edge: HandoffEdge) -> Bool {
        switch edge {
        case .left: return dx < 0
        case .right: return dx > 0
        case .top: return dy < 0
        case .bottom: return dy > 0
        }
    }

    private func shouldStartHandoff(edge: HandoffEdge, from current: CGPoint, to proposed: CGPoint, in bounds: CGRect) -> Bool {
        switch edge {
        case .left:
            return proposed.x <= bounds.minX || current.x <= bounds.minX
        case .right:
            return proposed.x >= bounds.maxX - 1 || current.x >= bounds.maxX - 1
        case .top:
            return proposed.y <= bounds.minY || current.y <= bounds.minY
        case .bottom:
            return proposed.y >= bounds.maxY - 1 || current.y >= bounds.maxY - 1
        }
    }

    private func clampedPoint(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(
            x: max(bounds.minX, min(bounds.maxX - 1, point.x)),
            y: max(bounds.minY, min(bounds.maxY - 1, point.y))
        )
    }

    private func isOuterDesktopEdge(_ edge: HandoffEdge, displayBounds: CGRect, unionBounds: CGRect) -> Bool {
        let tolerance: CGFloat = 0.5
        switch edge {
        case .left:
            return abs(displayBounds.minX - unionBounds.minX) <= tolerance
        case .right:
            return abs(displayBounds.maxX - unionBounds.maxX) <= tolerance
        case .top:
            return abs(displayBounds.minY - unionBounds.minY) <= tolerance
        case .bottom:
            return abs(displayBounds.maxY - unionBounds.maxY) <= tolerance
        }
    }

    private func axisPosition(
        for point: CGPoint,
        edge: HandoffEdge,
        displayBounds: CGRect,
        zone: HandoffZone
    ) -> CGFloat? {
        let axis: CGFloat
        let maxAxis: CGFloat
        switch edge {
        case .left, .right:
            guard point.y >= displayBounds.minY, point.y < displayBounds.maxY else { return nil }
            axis = point.y - displayBounds.minY
            maxAxis = displayBounds.height
        case .top, .bottom:
            guard point.x >= displayBounds.minX, point.x < displayBounds.maxX else { return nil }
            axis = point.x - displayBounds.minX
            maxAxis = displayBounds.width
        }

        let minRange = zone.localRangeMin ?? 0
        let maxRange = zone.localRangeMax ?? maxAxis
        guard axis >= minRange, axis <= maxRange else { return nil }
        return axis
    }

    private func edgePoint(for point: CGPoint, edge: HandoffEdge, displayBounds: CGRect) -> CGPoint {
        switch edge {
        case .left:
            return CGPoint(
                x: displayBounds.minX,
                y: max(displayBounds.minY, min(displayBounds.maxY - 1, point.y))
            )
        case .right:
            return CGPoint(
                x: displayBounds.maxX - 1,
                y: max(displayBounds.minY, min(displayBounds.maxY - 1, point.y))
            )
        case .top:
            return CGPoint(
                x: max(displayBounds.minX, min(displayBounds.maxX - 1, point.x)),
                y: displayBounds.minY
            )
        case .bottom:
            return CGPoint(
                x: max(displayBounds.minX, min(displayBounds.maxX - 1, point.x)),
                y: displayBounds.maxY - 1
            )
        }
    }

    private func isPoint(_ point: CGPoint, on edge: HandoffEdge, of display: CGRect) -> Bool {
        let tolerance: CGFloat = 1.5
        switch edge {
        case .left:
            return abs(point.x - display.minX) <= tolerance
                && point.y >= display.minY
                && point.y < display.maxY
        case .right:
            return abs(point.x - (display.maxX - 1)) <= tolerance
                && point.y >= display.minY
                && point.y < display.maxY
        case .top:
            return abs(point.y - display.minY) <= tolerance
                && point.x >= display.minX
                && point.x < display.maxX
        case .bottom:
            return abs(point.y - (display.maxY - 1)) <= tolerance
                && point.x >= display.minX
                && point.x < display.maxX
        }
    }

    private func logSendFailureOnce(_ error: NWError) {
        lock.lock()
        if didLogSendFailure {
            lock.unlock()
            return
        }
        didLogSendFailure = true
        lock.unlock()

        NSLog("[UCMouseRelay] Send failed: %@", String(describing: error))
		suppressRemoteHandoff(reason: "send failed")
    }

    private func logFirstSend(dx: Int, dy: Int) {
        lock.lock()
        let shouldLog = !didLogFirstSend
        didLogFirstSend = true
        lock.unlock()

        if shouldLog {
            NSLog("[UCMouseRelay] Sent first move dx=%d dy=%d", dx, dy)
        }
    }
}

struct UniversalControlRelayKeyPressEncoding {
	static let sideAwareCapability = "kp2"
	static let capabilityLine = "caps \(sideAwareCapability)"

	static func line(keyCode: CGKeyCode, modifiers: CGEventFlags) -> String {
		"kp \(keyCode) \(modifiers.rawValue)"
	}

	static func line(
		keyCode: CGKeyCode,
		modifiers: ModifierFlags,
		peerSupportsKP2: Bool
	) -> String {
		guard peerSupportsKP2, hasExplicitSide(modifiers) else {
			return line(keyCode: keyCode, modifiers: modifiers.cgEventFlags)
		}

		return "kp2 \(keyCode) \(modifiers.cgEventFlags.rawValue) " +
			"\(wireValue(for: modifiers.commandSide)) " +
			"\(wireValue(for: modifiers.optionSide)) " +
			"\(wireValue(for: modifiers.shiftSide)) " +
			"\(wireValue(for: modifiers.controlSide))"
	}

	static func supportsSideAwareKeyPress(_ parts: [Substring]) -> Bool {
		guard parts.first == "caps" else { return false }
		return parts.dropFirst().contains { $0 == sideAwareCapability }
	}

	private static func hasExplicitSide(_ modifiers: ModifierFlags) -> Bool {
		modifiers.commandSide != nil ||
			modifiers.optionSide != nil ||
			modifiers.shiftSide != nil ||
			modifiers.controlSide != nil
	}

	private static func wireValue(for side: ModifierSide?) -> Int {
		switch side {
		case .left: return 1
		case .right: return 2
		case .none: return 0
		}
	}
}

struct UniversalControlRelayUIStateEchoPolicy {
	static func payload(
		keyboardVisible: Bool,
		keyboardNavigationActive: Bool,
		directoryNavigatorVisible: Bool,
		swipePredictionsVisible: Bool
	) -> String {
		"uiState \(keyboardVisible ? 1 : 0) \(keyboardNavigationActive ? 1 : 0) \(directoryNavigatorVisible ? 1 : 0) \(swipePredictionsVisible ? 1 : 0)"
	}

	static func shouldSend(payload: String, lastSentPayload: String?) -> Bool {
		payload != lastSentPayload
	}
}

struct UniversalControlHandoffEdgeDefaults {
	static let fallbackLocalEdges: [UniversalControlMouseRelay.HandoffEdge] = [.left, .right]

	static func localEdges(configuredRawValue: String?) -> [UniversalControlMouseRelay.HandoffEdge] {
		if let configuredRawValue,
		   let edge = UniversalControlMouseRelay.HandoffEdge(rawValue: configuredRawValue) {
			return [edge]
		}
		return fallbackLocalEdges
	}
}

struct UniversalControlRemoteMouseMovementPolicy {
	struct Movement: Equatable {
		let point: CGPoint
		let dx: Int
		let dy: Int

		var shouldPostEvent: Bool {
			dx != 0 || dy != 0
		}
	}

	static func boundedMovement(
		current: CGPoint,
		requestedDX: Int,
		requestedDY: Int,
		bounds: CGRect
	) -> Movement {
		guard isUsable(bounds), contains(current, in: bounds) else {
			return Movement(
				point: statusPoint(current: current, bounds: bounds),
				dx: 0,
				dy: 0
			)
		}

		let next = clampedPoint(
			CGPoint(
				x: current.x + CGFloat(requestedDX),
				y: current.y + CGFloat(requestedDY)
			),
			to: bounds
		)
		return Movement(
			point: next,
			dx: Int((next.x - current.x).rounded()),
			dy: Int((next.y - current.y).rounded())
		)
	}

	static func statusPoint(current: CGPoint, bounds: CGRect) -> CGPoint {
		guard isUsable(bounds) else { return current }
		return clampedPoint(current, to: bounds)
	}

	private static func contains(_ point: CGPoint, in bounds: CGRect) -> Bool {
		point.x >= bounds.minX
			&& point.x <= bounds.maxX - 1
			&& point.y >= bounds.minY
			&& point.y <= bounds.maxY - 1
	}

	private static func clampedPoint(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
		CGPoint(
			x: max(bounds.minX, min(bounds.maxX - 1, point.x)),
			y: max(bounds.minY, min(bounds.maxY - 1, point.y))
		)
	}

	private static func isUsable(_ bounds: CGRect) -> Bool {
		!bounds.isNull && !bounds.isInfinite && bounds.width >= 1 && bounds.height >= 1
	}
}
