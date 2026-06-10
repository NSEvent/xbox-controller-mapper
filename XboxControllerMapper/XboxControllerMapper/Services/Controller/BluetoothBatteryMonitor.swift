import Foundation
import CoreBluetooth
import Combine

/// A monitor that uses CoreBluetooth to read battery levels from the standard GATT Battery Service (0x180F).
/// This acts as a workaround for the GameController framework often reporting -1/0 for Xbox controllers.
class BluetoothBatteryMonitor: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var batteryLevel: Int? // 0-100
    @Published var isCharging: Bool = false // Note: BLE Battery Service doesn't explicitly support "charging" state usually, just level.
    
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var batteryCharacteristic: CBCharacteristic?
    
    private let batteryServiceUUID = CBUUID(string: "180F")
    private let batteryLevelUUID = CBUUID(string: "2A19")
	private let targetNameFragments = [
		"xbox",
		"apple tv remote",
		"siri remote",
		"control center remote",
		"universal electronics"
	]

	/// The Siri Remote's Bluetooth name is its serial number (e.g. "C08QMZ6M2330"),
	/// so name-fragment matching can never identify it. When ControllerService
	/// detects an Apple TV remote as the active controller, it sets this flag so
	/// the monitor also accepts connected peripherals whose name looks like a
	/// bare serial number.
	var allowsSerialNamedPeripherals = false
    
    override init() {
        super.init()
        // Initialize Central Manager
        // Note: We don't start scanning immediately until requested
    }
    
    func startMonitoring() {
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        } else if centralManager.state == .poweredOn {
            scanForControllers()
        }
    }
    
    func stopMonitoring() {
        if let peripheral = connectedPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        if centralManager?.isScanning == true {
            centralManager?.stopScan()
        }
        batteryLevel = nil
    }

    /// Resets the cached battery level (call when controller disconnects)
    func resetBatteryLevel() {
        batteryLevel = nil
    }

    /// Refreshes the battery level by re-reading from the connected peripheral
    func refreshBatteryLevel() {
        if let peripheral = connectedPeripheral, let characteristic = batteryCharacteristic {
            peripheral.readValue(for: characteristic)
        } else {
            // Not connected yet, trigger a scan
            if centralManager?.state == .poweredOn {
                scanForControllers()
            }
        }
    }
    
    private func scanForControllers() {
        // First, check for already connected devices (common for controllers)
        let connected = centralManager.retrieveConnectedPeripherals(withServices: [batteryServiceUUID])

		if let controller = connected.first(where: isTargetControllerPeripheral) {
            connect(to: controller)
        } else {
            // Scan for new devices
            centralManager.scanForPeripherals(withServices: [batteryServiceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
    }
    
    private func connect(to peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
    }
    
    // MARK: - CBCentralManagerDelegate
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            scanForControllers()
        case .poweredOff, .resetting, .unauthorized, .unknown, .unsupported:
            stopMonitoring()
        @unknown default:
            break
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
		if isTargetControllerPeripheral(peripheral) {
            centralManager.stopScan()
            connect(to: peripheral)
        }
    }

	private func isTargetControllerPeripheral(_ peripheral: CBPeripheral) -> Bool {
		guard let name = peripheral.name?.lowercased(), !name.isEmpty else { return false }
		if targetNameFragments.contains(where: { name.contains($0) }) {
			return true
		}
		return allowsSerialNamedPeripherals && Self.isSerialLikeName(name)
	}

	/// True for names that look like a bare device serial number: one run of
	/// 8-20 alphanumerics with at least one digit and no spaces (the Siri
	/// Remote advertises e.g. "C08QMZ6M2330"). Names like "Magic Keyboard" or
	/// "Xbox Wireless Controller" never match.
	static func isSerialLikeName(_ name: String) -> Bool {
		guard name.count >= 8, name.count <= 20 else { return false }
		guard name.allSatisfy({ $0.isLetter || $0.isNumber }) else { return false }
		return name.contains { $0.isNumber }
	}
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([batteryServiceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        // Connection failed, will retry on next scan
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectedPeripheral = nil
        batteryCharacteristic = nil
        batteryLevel = nil

        // Retry scanning
        if central.state == .poweredOn {
            scanForControllers()
        }
    }
    
    // MARK: - CBPeripheralDelegate
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        
        for service in services {
            if service.uuid == batteryServiceUUID {
                peripheral.discoverCharacteristics([batteryLevelUUID], for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            if characteristic.uuid == batteryLevelUUID {
                batteryCharacteristic = characteristic
                peripheral.readValue(for: characteristic)
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            return
        }

        if characteristic.uuid == batteryLevelUUID, let value = characteristic.value {
            // Battery level is a single byte (0-100)
            let level = Int(value.first ?? 0)

            DispatchQueue.main.async { [weak self] in
                self?.batteryLevel = level
            }
        }
    }
}
