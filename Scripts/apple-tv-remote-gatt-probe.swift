#!/usr/bin/env swift

import CoreBluetooth
import Foundation

private enum GATTProbeConstants {
    static let hidService = CBUUID(string: "1812")
    static let hidReport = CBUUID(string: "2A4D")
    static let reportReference = CBUUID(string: "2908")
    static let batteryService = CBUUID(string: "180F")
    static let defaultRunSeconds: TimeInterval = 30
    static let defaultNameFilter = "C08"
}

private struct ReportReference {
    let reportID: UInt8
    let reportType: UInt8

    var typeName: String {
        switch reportType {
        case 1: return "input"
        case 2: return "output"
        case 3: return "feature"
        default: return "type\(reportType)"
        }
    }
}

private struct ReportState {
    var reference: ReportReference?
    var notifyStarted = false
    var enableWritten = false
}

private final class AppleTVRemoteGATTProbe: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private let runSeconds: TimeInterval
    private let nameFilter: String
    private let scanAll: Bool
    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var reportStates: [ObjectIdentifier: ReportState] = [:]
    private var retriedAllServiceDiscovery: Set<UUID> = []
    private var didPrintState = false
    private var reportValueCount = 0

    init(runSeconds: TimeInterval, nameFilter: String, scanAll: Bool) {
        self.runSeconds = runSeconds
        self.nameFilter = nameFilter.lowercased()
        self.scanAll = scanAll
    }

    func run() {
        log("Apple TV Remote direct GATT probe starting")
        log("seconds=\(Int(runSeconds)) nameFilter=\(nameFilter) scanAll=\(scanAll ? "yes" : "no")")
        log("For direct ownership, unpair/disconnect the remote from macOS, put it in pairing mode, then run this probe.")
        central = CBCentralManager(delegate: self, queue: nil)
        RunLoop.current.run(until: Date().addingTimeInterval(runSeconds))
        central.stopScan()
        for peripheral in peripherals.values {
            central.cancelPeripheralConnection(peripheral)
        }
        log("summary: peripherals=\(peripherals.count) reportValues=\(reportValueCount)")
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard !didPrintState else { return }
        didPrintState = true
        log("central state=\(stateName(central.state))")
        guard central.state == .poweredOn else { return }

        let connected = central.retrieveConnectedPeripherals(withServices: [
            GATTProbeConstants.hidService,
            GATTProbeConstants.batteryService,
        ])
        log("retrieveConnectedPeripherals count=\(connected.count)")
        for peripheral in connected {
            register(peripheral, source: "connected")
            central.connect(peripheral)
        }

        let services: [CBUUID]? = scanAll ? nil : [GATTProbeConstants.hidService]
        central.scanForPeripherals(
            withServices: services,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        log("scan started \(scanAll ? "for all BLE advertisements" : "for service 0x1812")")
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedServices = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let localName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "").lowercased()
        let serviceHit = advertisedServices.contains(GATTProbeConstants.hidService)
        let nameHit = nameFilter.isEmpty || localName.contains(nameFilter)

        guard serviceHit || nameHit else { return }

        let serviceList = advertisedServices.map(\.uuidString).joined(separator: ",")
        register(
            peripheral,
            source: "scan rssi=\(RSSI) name=\(localName.isEmpty ? "(nil)" : localName) services=[\(serviceList)]"
        )
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("connected \(description(for: peripheral))")
        peripheral.delegate = self
        peripheral.discoverServices([GATTProbeConstants.hidService, GATTProbeConstants.batteryService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log("connect failed \(description(for: peripheral)) error=\(error?.localizedDescription ?? "nil")")
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            log("service discovery failed \(description(for: peripheral)) error=\(error.localizedDescription)")
            return
        }

        let services = peripheral.services ?? []
        log("services \(description(for: peripheral)): \(services.map { $0.uuid.uuidString }.joined(separator: ", "))")
        if !services.contains(where: { $0.uuid == GATTProbeConstants.hidService }) {
            log("HID service 1812 not visible on \(description(for: peripheral))")
            if !retriedAllServiceDiscovery.contains(peripheral.identifier) {
                retriedAllServiceDiscovery.insert(peripheral.identifier)
                log("retrying full service discovery on \(description(for: peripheral))")
                peripheral.discoverServices(nil)
            }
        }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            log("characteristic discovery failed service=\(service.uuid.uuidString) error=\(error.localizedDescription)")
            return
        }

        for characteristic in service.characteristics ?? [] {
            log("char service=\(service.uuid.uuidString) uuid=\(characteristic.uuid.uuidString) props=\(properties(characteristic.properties))")
            peripheral.discoverDescriptors(for: characteristic)
            if characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }
            if characteristic.uuid == GATTProbeConstants.hidReport {
                reportStates[ObjectIdentifier(characteristic)] = ReportState()
                if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                    startNotifyIfNeeded(peripheral: peripheral, characteristic: characteristic)
                }
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            log("descriptor discovery failed char=\(characteristic.uuid.uuidString) error=\(error.localizedDescription)")
            maybeWriteEnable(peripheral: peripheral, characteristic: characteristic)
            return
        }

        let descriptors = characteristic.descriptors ?? []
        log("descriptors char=\(characteristic.uuid.uuidString): \(descriptors.map { $0.uuid.uuidString }.joined(separator: ", "))")
        if characteristic.uuid == GATTProbeConstants.hidReport, descriptors.isEmpty {
            maybeWriteEnable(peripheral: peripheral, characteristic: characteristic)
        }
        for descriptor in descriptors {
            if descriptor.uuid == GATTProbeConstants.reportReference {
                peripheral.readValue(for: descriptor)
            } else if descriptor.uuid != CBUUID(string: "2902") {
                peripheral.readValue(for: descriptor)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
        guard let characteristic = descriptor.characteristic else { return }
        if let error {
            log("descriptor read failed char=\(characteristic.uuid.uuidString) descriptor=\(descriptor.uuid.uuidString) error=\(error.localizedDescription)")
            maybeWriteEnable(peripheral: peripheral, characteristic: characteristic)
            return
        }

        if descriptor.uuid == GATTProbeConstants.reportReference,
           let data = descriptor.value as? Data,
           data.count >= 2 {
            let reference = ReportReference(reportID: data[0], reportType: data[1])
            var state = reportStates[ObjectIdentifier(characteristic)] ?? ReportState()
            state.reference = reference
            reportStates[ObjectIdentifier(characteristic)] = state
            log("report reference id=0x\(hexByte(reference.reportID)) type=\(reference.typeName) charProps=\(properties(characteristic.properties))")
        } else {
            log("descriptor value uuid=\(descriptor.uuid.uuidString) value=\(String(describing: descriptor.value))")
        }

        maybeWriteEnable(peripheral: peripheral, characteristic: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        log("notify state uuid=\(characteristic.uuid.uuidString) notifying=\(characteristic.isNotifying) error=\(error?.localizedDescription ?? "nil")")
        maybeWriteEnable(peripheral: peripheral, characteristic: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        let state = reportStates[ObjectIdentifier(characteristic)]
        let ref = state?.reference.map { "id=0x\(hexByte($0.reportID)) type=\($0.typeName)" } ?? "id=? type=?"
        log("write complete \(ref) error=\(error?.localizedDescription ?? "nil")")
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            log("value error uuid=\(characteristic.uuid.uuidString) error=\(error.localizedDescription)")
            return
        }

        guard characteristic.uuid == GATTProbeConstants.hidReport else {
            let bytes = [UInt8](characteristic.value ?? Data())
            log(
                "value service=\(characteristic.service?.uuid.uuidString ?? "?") uuid=\(characteristic.uuid.uuidString) len=\(bytes.count) bytes=\(hex(bytes, limit: 64))"
            )
            return
        }

        let state = reportStates[ObjectIdentifier(characteristic)]
        let reference = state?.reference
        let bytes = [UInt8](characteristic.value ?? Data())
        reportValueCount += 1
        log(
            "REPORT id=\(reference.map { "0x" + hexByte($0.reportID) } ?? "?") type=\(reference?.typeName ?? "?") len=\(bytes.count) bytes=\(hex(bytes, limit: 48))"
        )
    }

    private func register(_ peripheral: CBPeripheral, source: String) {
        let firstSeen = peripherals[peripheral.identifier] == nil
        peripherals[peripheral.identifier] = peripheral
        peripheral.delegate = self
        if firstSeen {
            log("\(source) \(description(for: peripheral))")
        }
    }

    private func startNotifyIfNeeded(peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        let key = ObjectIdentifier(characteristic)
        var state = reportStates[key] ?? ReportState()
        guard !state.notifyStarted else { return }
        state.notifyStarted = true
        reportStates[key] = state
        peripheral.setNotifyValue(true, for: characteristic)
    }

    private func maybeWriteEnable(peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        guard characteristic.uuid == GATTProbeConstants.hidReport else { return }
        guard characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) else { return }

        let key = ObjectIdentifier(characteristic)
        var state = reportStates[key] ?? ReportState()
        guard !state.enableWritten else { return }

        if let reference = state.reference, reference.reportType == 1 {
            return
        }

        state.enableWritten = true
        reportStates[key] = state

        let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        let refID = state.reference?.reportID
        let refDesc = state.reference.map { "id=0x\(hexByte($0.reportID)) type=\($0.typeName)" } ?? "id=? type=?"
        log("writing 0xAF to \(refDesc) writeType=\(writeType == .withResponse ? "withResponse" : "withoutResponse")")
        peripheral.writeValue(Data([0xAF]), for: characteristic, type: writeType)
        if let refID {
            peripheral.writeValue(Data([refID, 0xAF]), for: characteristic, type: writeType)
        }
    }

    private func description(for peripheral: CBPeripheral) -> String {
        "name=\(peripheral.name ?? "(nil)") id=\(peripheral.identifier.uuidString)"
    }

    private func stateName(_ state: CBManagerState) -> String {
        switch state {
        case .unknown: return "unknown"
        case .resetting: return "resetting"
        case .unsupported: return "unsupported"
        case .unauthorized: return "unauthorized"
        case .poweredOff: return "poweredOff"
        case .poweredOn: return "poweredOn"
        @unknown default: return "unknown"
        }
    }

    private func properties(_ properties: CBCharacteristicProperties) -> String {
        var names: [String] = []
        if properties.contains(.broadcast) { names.append("broadcast") }
        if properties.contains(.read) { names.append("read") }
        if properties.contains(.writeWithoutResponse) { names.append("writeWithoutResponse") }
        if properties.contains(.write) { names.append("write") }
        if properties.contains(.notify) { names.append("notify") }
        if properties.contains(.indicate) { names.append("indicate") }
        if properties.contains(.authenticatedSignedWrites) { names.append("authenticatedSignedWrites") }
        return names.isEmpty ? "[]" : names.joined(separator: "|")
    }
}

private func hex(_ bytes: [UInt8], limit: Int) -> String {
    let shown = bytes.prefix(limit).map { String(format: "%02X", $0) }.joined(separator: " ")
    return bytes.count > limit ? shown + " ..." : shown
}

private func hexByte(_ byte: UInt8) -> String {
    String(format: "%02X", byte)
}

private func log(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    FileHandle.standardOutput.write("[\(timestamp)] \(message)\n".data(using: .utf8)!)
}

private func usage() -> Never {
    FileHandle.standardError.write("""
    Usage: swift Scripts/apple-tv-remote-gatt-probe.swift [--seconds N] [--name SUBSTRING] [--scan-all]

    --seconds N       Capture window length. Default: 30.
    --name SUBSTRING  Connect to advertisements whose name contains this. Default: C08.
    --scan-all        Scan all BLE advertisements instead of only advertised HID service 1812.

    """.data(using: .utf8)!)
    exit(2)
}

var seconds = GATTProbeConstants.defaultRunSeconds
var nameFilter = GATTProbeConstants.defaultNameFilter
var scanAll = true
var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let arg = args.removeFirst()
    switch arg {
    case "--seconds":
        guard let value = args.first, let parsed = TimeInterval(value), parsed > 0 else { usage() }
        seconds = parsed
        args.removeFirst()
    case "--name":
        guard let value = args.first else { usage() }
        nameFilter = value
        args.removeFirst()
    case "--scan-all":
        scanAll = true
    case "--hid-only":
        scanAll = false
    default:
        usage()
    }
}

AppleTVRemoteGATTProbe(runSeconds: seconds, nameFilter: nameFilter, scanAll: scanAll).run()
