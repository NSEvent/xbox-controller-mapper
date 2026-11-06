import Combine
import Foundation
import IOBluetooth
import IOKit

/// In-app Wii Remote pairing. System Settings cannot pair a Wiimote on modern
/// macOS (legacy raw-byte PIN, ignored by the public API), so this drives the
/// private-API flow: inquiry until a peripheral-class device answers, then
/// IOBluetoothDevicePair with setUserDefinedPincode + the coordinator's
/// pairPeer carrying the host address reversed as a little-endian UInt64.
///
/// The user taps the remote's red SYNC button (under the battery cover)
/// while this scans; each tap opens a ~20 s discoverable window.
@MainActor
final class WiimotePairingService: NSObject, ObservableObject {
	enum Phase: Equatable {
		case idle
		case scanning
		case pairing
		case connecting
		case paired
		case failed(String)
	}

	@Published private(set) var phase: Phase = .idle

	private var inquiry: IOBluetoothDeviceInquiry?
	private var pairingAgent: IOBluetoothDevicePair?
	private var timedOut = false
	private var timeoutWorkItem: DispatchWorkItem?
	private var connectionTask: Task<Void, Never>?

	var statusText: String {
		switch phase {
		case .idle: return ""
		case .scanning: return "Scanning — tap the red SYNC button under the battery cover every few seconds…"
		case .pairing: return "Wii Remote found — pairing…"
		case .connecting: return "Paired — connecting controller input. Keep the remote awake…"
		case .paired: return "Connected! The Wii Remote is ready to use."
		case .failed(let reason): return reason
		}
	}

	var isBusy: Bool {
		phase == .scanning || phase == .pairing || phase == .connecting
	}

	func startPairing() {
		guard !isBusy else { return }
		NSLog("[WiiPair] Starting pairing scan")
		timedOut = false
		phase = .scanning

		let inquiry = IOBluetoothDeviceInquiry(delegate: self)
		inquiry?.inquiryLength = 6
		inquiry?.updateNewDeviceNames = true
		self.inquiry = inquiry
		let result = inquiry?.start()
		NSLog("[WiiPair] Inquiry start result: %@", result.map { String(format: "0x%08X", $0) } ?? "no inquiry")

		// Overall window: the user may need several sync taps. Cancellable so
		// a stale timer from a cancelled session can't kill a later scan.
		timeoutWorkItem?.cancel()
		let workItem = DispatchWorkItem { [weak self] in
			guard let self, self.isBusy else { return }
			self.timedOut = true
			self.stop(failure: "No Wii Remote answered in 90s — check batteries, tap SYNC, and try again.")
		}
		timeoutWorkItem = workItem
		DispatchQueue.main.asyncAfter(deadline: .now() + 90, execute: workItem)
	}

	func stop(failure: String? = nil) {
		NSLog("[WiiPair] Stop: %@", failure ?? "cancelled")
		// Invalidate state before stop() can synchronously call our delegates.
		if let failure {
			phase = .failed(failure)
		} else if isBusy {
			phase = .idle
		}
		timeoutWorkItem?.cancel()
		timeoutWorkItem = nil
		connectionTask?.cancel()
		connectionTask = nil
		let previousInquiry = inquiry
		inquiry = nil
		let previousAgent = pairingAgent
		pairingAgent = nil
		previousInquiry?.stop()
		previousAgent?.stop()
	}
}

extension WiimotePairingService: IOBluetoothDeviceInquiryDelegate {
    nonisolated static func isWiiRemoteName(_ name: String?) -> Bool {
        name == "Nintendo RVL-CNT-01" || name == "Nintendo RVL-CNT-01-TR"
    }

    @objc func deviceInquiryDeviceNameUpdated(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!, devicesRemaining: UInt32) {
        deviceInquiryDeviceFound(sender, device: device)
    }

	@objc func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!) {
        // Never attempt the private pairing flow on a keyboard or other gamepad.
        // Name resolution may finish after the first device-found callback.
        guard sender === inquiry, phase == .scanning, let device,
              Self.isWiiRemoteName(device.name) else { return }
        phase = .pairing
		NSLog("[WiiPair] Found %@; stopping inquiry before pairing", device.name ?? "Wii Remote")
        sender.stop()

		let agent = IOBluetoothDevicePair(device: device)
		agent?.delegate = self
		agent?.setUserDefinedPincode(true)
		pairingAgent = agent
		let result = agent?.start()
		NSLog("[WiiPair] Pair start result: %@", result.map { String(format: "0x%08X", $0) } ?? "no agent")
		if result != kIOReturnSuccess {
			pairingAgent = nil
			agent?.stop()
			phase = .scanning
			restartInquiry(sender)
		}
	}

	@objc func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool) {
		NSLog("[WiiPair] Inquiry complete: error=0x%08X aborted=%d phase=%@", error, aborted, String(describing: phase))
		guard let sender, sender === inquiry, phase == .scanning, !timedOut, !aborted else { return }
		// Tahoe can resolve a name without delivering deviceNameUpdated. Its
		// duplicate discovery also skips deviceFound, so revisit the retained
		// devices before clearing this inquiry's deduplication cache.
		for case let device as IOBluetoothDevice in sender.foundDevices() ?? [] {
			deviceInquiryDeviceFound(sender, device: device)
			if phase != .scanning { return }
		}
		restartInquiry(sender)
	}

	private func restartInquiry(_ sender: IOBluetoothDeviceInquiry) {
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self, weak sender] in
			guard let self, let sender, sender === self.inquiry,
				  self.phase == .scanning, !self.timedOut else { return }
			sender.clearFoundDevices()
			let result = sender.start()
			NSLog("[WiiPair] Inquiry restart result: 0x%08X", result)
		}
	}
}

extension WiimotePairingService: IOBluetoothDevicePairDelegate {
	@objc func devicePairingPINCodeRequest(_ sender: Any!) {
		NSLog("[WiiPair] PIN callback: phase=%@", String(describing: phase))
		guard let pair = sender as? IOBluetoothDevicePair,
              pair === pairingAgent, phase == .pairing,
			  let device = pair.device() else {
			NSLog("[WiiPair] Ignoring PIN callback from inactive pairing agent")
			return
		}
		guard let hostAddrStr = IOBluetoothHostController.default()?.addressAsString() else {
			NSLog("[WiiPair] PIN unavailable: host Bluetooth address is nil")
			return
		}

		var hostAddr = BluetoothDeviceAddress()
		let addressResult = IOBluetoothNSStringToDeviceAddress(hostAddrStr, &hostAddr)
		NSLog("[WiiPair] Host address parse result: 0x%08X", addressResult)
		let d = hostAddr.data
		// Sync-button pairing PIN = host BT address bytes reversed, packed LE.
		let bytes: [UInt8] = [d.5, d.4, d.3, d.2, d.1, d.0]
        let key = bytes.enumerated().reduce(UInt64(0)) { value, entry in
            value | (UInt64(entry.element) << (entry.offset * 8))
        }

		guard let coordinator = IOBluetoothCoreBluetoothCoordinator.sharedInstance(),
			  let peer = device.classicPeer() else {
			NSLog("[WiiPair] PIN unavailable: coordinator or classic peer is nil")
			return
		}
		NSLog("[WiiPair] Sending PIN for pairing type %lu", pair.currentPairingType())
		coordinator.pairPeer(peer, forType: pair.currentPairingType(), withKey: NSNumber(value: key))
	}

	@objc func devicePairingFinished(_ sender: Any!, error: IOReturn) {
		NSLog("[WiiPair] Pair finished: error=0x%08X phase=%@", error, String(describing: phase))
        guard let pair = sender as? IOBluetoothDevicePair,
              pair === pairingAgent, phase == .pairing else { return }
		let device = pair.device()
		// A failed agent otherwise keeps reacting to discovery and reconnects
		// independently of our state machine (observed after error 31).
		pairingAgent = nil
		pair.stop()
		if error == kIOReturnSuccess {
			stop()
			NSLog("[ControllerKeys] In-app Wii Remote pairing succeeded")
			guard let address = device?.addressString else {
				phase = .failed("Paired, but the remote's address is unavailable. Try pairing again.")
				return
			}
			connectHID(address: address)
		} else {
			// Wrong window timing is common — resume scanning for another tap.
			guard !timedOut else { return }
			phase = .scanning
			if let inquiry { restartInquiry(inquiry) }
		}
	}

	private func connectHID(address: String) {
		phase = .connecting
		let normalized = address.replacingOccurrences(of: "-", with: ":").uppercased()
		connectionTask = Task { @MainActor [weak self] in
			var attempt = WiimoteHIDConnectionAttempt(startedAt: ProcessInfo.processInfo.systemUptime)
			while !Task.isCancelled {
				guard let self, self.phase == .connecting else { return }
				let now = ProcessInfo.processInfo.systemUptime
				switch attempt.advance(at: now, hasHIDDevice: Self.hasHIDDevice(address: normalized)) {
				case .wait: break
				case .request:
					let requested = CKConnectWiiHIDDevice(normalized)
					NSLog("[WiiPair] HID service connection requested: %d", requested)
				case .connected:
					self.phase = .paired
					self.connectionTask = nil
					NSLog("[WiiPair] HID input device connected and stable")
					return
				case .timedOut:
					self.phase = .failed("Paired, but controller input did not connect. Tap red SYNC and try Pair Wii Remote again.")
					self.connectionTask = nil
					NSLog("[WiiPair] HID connection timed out after pairing")
					return
				}
				do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
			}
		}
	}

	private static func hasHIDDevice(address: String) -> Bool {
		var iterator: io_iterator_t = 0
		guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDUserDevice"), &iterator) == KERN_SUCCESS else { return false }
		defer { IOObjectRelease(iterator) }
		while case let service = IOIteratorNext(iterator), service != 0 {
			defer { IOObjectRelease(service) }
			let vendor = IORegistryEntryCreateCFProperty(service, "VendorID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
			let product = IORegistryEntryCreateCFProperty(service, "ProductID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
			let serial = IORegistryEntryCreateCFProperty(service, "SerialNumber" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
			if vendor == 0x057e, product == 0x0306 || product == 0x0330,
			   serial?.replacingOccurrences(of: "-", with: ":").uppercased() == address { return true }
		}
		return false
	}
}

/// Bounded service retries; a baseband connection alone never counts as input.
struct WiimoteHIDConnectionAttempt {
	enum Action: Equatable { case wait, request, connected, timedOut }
	let startedAt: TimeInterval
	private var lastRequest: TimeInterval?
	private var attachedSince: TimeInterval?
	private var terminal: Action?

	init(startedAt: TimeInterval) { self.startedAt = startedAt }

	mutating func advance(at now: TimeInterval, hasHIDDevice: Bool) -> Action {
		if let terminal { return terminal }
		// macOS drops the pairing ACL immediately after authentication.
		guard now - startedAt >= 0.5 else { return .wait }
		if hasHIDDevice {
			if attachedSince == nil { attachedSince = now }
			if now - (attachedSince ?? now) >= 0.75 {
				terminal = .connected
				return .connected
			}
		} else { attachedSince = nil }
		if now - startedAt >= 15 {
			terminal = .timedOut
			return .timedOut
		}
		if !hasHIDDevice, lastRequest == nil || now - (lastRequest ?? now) >= 2 {
			lastRequest = now
			return .request
		}
		return .wait
	}
}
