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

        if let controller = connected.first(where: { $0.name?.localizedCaseInsensitiveContains("Xbox") == true }) {
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
        // Check if it's likely an Xbox controller
        if let name = peripheral.name, name.localizedCaseInsensitiveContains("Xbox") {
            centralManager.stopScan()
            connect(to: peripheral)
        }
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

            DispatchQueue.main.async {
                self.batteryLevel = level
                // Assuming not charging if on BLE, or we can't tell.
                // Xbox controllers often just report level.
            }
        }
    }
}