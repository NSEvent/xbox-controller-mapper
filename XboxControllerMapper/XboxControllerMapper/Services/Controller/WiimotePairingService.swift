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

	var statusText: String {
		switch phase {
		case .idle: return ""
		case .scanning: return "Scanning — tap the red SYNC button under the battery cover every few seconds…"
		case .pairing: return "Wii Remote found — pairing…"
		case .paired: return "Paired! The remote connects automatically from now on."
		case .failed(let reason): return reason
		}
	}

	var isBusy: Bool {
		phase == .scanning || phase == .pairing
	}

	func startPairing() {
		guard !isBusy else { return }
		timedOut = false
		phase = .scanning

		let inquiry = IOBluetoothDeviceInquiry(delegate: self)
		inquiry?.inquiryLength = 6
		inquiry?.updateNewDeviceNames = false
		self.inquiry = inquiry
		inquiry?.start()

		// Overall window: the user may need several sync taps.
		DispatchQueue.main.asyncAfter(deadline: .now() + 90) { [weak self] in
			guard let self, self.isBusy else { return }
			self.timedOut = true
			self.stop(failure: "No Wii Remote answered in 90s — check batteries, tap SYNC, and try again.")
		}
	}

	func stop(failure: String? = nil) {
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
	@objc func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!) {
		// During a sync window the Wiimote is typically the only discoverable
		// peripheral-class (joystick/gamepad) device around.
		guard phase == .scanning,
			  device.deviceClassMajor == kBluetoothDeviceClassMajorPeripheral else { return }
		sender.stop()
		phase = .pairing

		let agent = IOBluetoothDevicePair(device: device)
		agent?.delegate = self
		agent?.setUserDefinedPincode(true)
		pairingAgent = agent
		if agent?.start() != kIOReturnSuccess {
			phase = .scanning
			inquiry?.start()
		}
	}

	@objc func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool) {
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
		guard let pair = sender as? IOBluetoothDevicePair,
			  let device = pair.device(),
			  let hostAddrStr = IOBluetoothHostController.default()?.addressAsString() else { return }

		var hostAddr = BluetoothDeviceAddress()
		IOBluetoothNSStringToDeviceAddress(hostAddrStr, &hostAddr)
		let d = hostAddr.data
		// Sync-button pairing PIN = host BT address bytes reversed, packed LE.
		let bytes: [UInt8] = [d.5, d.4, d.3, d.2, d.1, d.0]
		var key: UInt64 = 0
		Data(bytes + [0, 0]).withUnsafeBytes { key = $0.load(as: UInt64.self) }

		guard let coordinator = IOBluetoothCoreBluetoothCoordinator.sharedInstance(),
			  let peer = device.classicPeer() else { return }
		coordinator.pairPeer(peer, forType: pair.currentPairingType(), withKey: NSNumber(value: key))
	}

	@objc func devicePairingFinished(_ sender: Any!, error: IOReturn) {
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
