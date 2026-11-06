import Combine
import Foundation
import IOBluetooth

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
		case paired
		case failed(String)
	}

	@Published private(set) var phase: Phase = .idle

	private var inquiry: IOBluetoothDeviceInquiry?
	private var pairingAgent: IOBluetoothDevicePair?
	private var timedOut = false
	private var timeoutWorkItem: DispatchWorkItem?

	var statusText: String {
		switch phase {
		case .idle: return ""
		case .scanning: return "Scanning — tap the red SYNC button under the battery cover every few seconds…"
		case .pairing: return "Wii Remote found — pairing…"
		case .paired: return "Paired! Press a button to wake the remote. If it does not reconnect, pair here again."
		case .failed(let reason): return reason
		}
	}

	var isBusy: Bool {
		phase == .scanning || phase == .pairing
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
		timeoutWorkItem?.cancel()
		timeoutWorkItem = nil
		inquiry?.stop()
		inquiry = nil
		pairingAgent?.stop()
		pairingAgent = nil
		if let failure {
			phase = .failed(failure)
		} else if isBusy {
			phase = .idle
		}
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
			phase = .scanning
			inquiry?.start()
		}
	}

	@objc func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool) {
		NSLog("[WiiPair] Inquiry complete: error=0x%08X aborted=%d phase=%@", error, aborted, String(describing: phase))
		// Keep scanning until something answers or the overall window expires.
		guard phase == .scanning, !timedOut else { return }
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
			guard let self, self.phase == .scanning, !self.timedOut else { return }
			self.inquiry?.start()
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
		if error == kIOReturnSuccess {
			phase = .paired
			// Bring the HID connection up; the Wiimote backend attaches from here.
			if let device = pairingAgent?.device(), !device.isConnected() {
				device.openConnection()
			}
			pairingAgent = nil
			inquiry = nil
			NSLog("[ControllerKeys] In-app Wii Remote pairing succeeded")
		} else {
			// Wrong window timing is common — resume scanning for another tap.
			guard !timedOut else { return }
			phase = .scanning
			inquiry?.start()
		}
	}
}
