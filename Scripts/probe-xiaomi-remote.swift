import Foundation
import IOKit.hid

// Exact-device HID capture: no other keyboards or controllers are opened.
// Usage: swift Scripts/probe-xiaomi-remote.swift [seconds] [--shared]
// Default exclusive capture prevents remote keys reaching the frontmost app.
let duration = Double(CommandLine.arguments.dropFirst().first ?? "900") ?? 900
let options = CommandLine.arguments.contains("--shared")
    ? IOOptionBits(kIOHIDOptionsTypeNone) : IOOptionBits(kIOHIDOptionsTypeSeizeDevice)
let started = Date()
func emit(_ fields: [String: Any]) {
    var record = fields
    record["seconds"] = Date().timeIntervalSince(started)
    guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else { return }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([10]))
}

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, [
    kIOHIDVendorIDKey as String: 0x2717,
    kIOHIDProductIDKey as String: 0x32B8,
] as CFDictionary)
IOHIDManagerRegisterDeviceMatchingCallback(manager, { _, result, _, device in
    var fields: [String: Any] = ["event": "connected", "result": result]
    for key in [kIOHIDProductKey, kIOHIDManufacturerKey, kIOHIDTransportKey,
                kIOHIDVendorIDKey, kIOHIDProductIDKey, kIOHIDMaxInputReportSizeKey] {
        if let value = IOHIDDeviceGetProperty(device, key as CFString) { fields[key] = value }
    }
    if let descriptor = IOHIDDeviceGetProperty(device, kIOHIDReportDescriptorKey as CFString) as? Data {
        fields["descriptor"] = descriptor.map { String(format: "%02x", $0) }.joined()
    }
    emit(fields)
}, nil)
IOHIDManagerRegisterDeviceRemovalCallback(manager, { _, result, _, _ in
    emit(["event": "disconnected", "result": result])
}, nil)
IOHIDManagerRegisterInputReportCallback(manager, { _, result, _, type, reportID, report, length in
    let bytes = Array(UnsafeBufferPointer(start: report, count: length))
    var fields: [String: Any] = ["event": "report", "result": result,
                               "type": type.rawValue, "reportID": reportID,
                               "hex": bytes.map { String(format: "%02x", $0) }.joined(separator: " ")]
    if reportID == 1 {
        // macOS includes the report ID byte in raw interrupt reports.
        let payload = bytes.count == 7 && bytes.first == 1 ? Array(bytes.dropFirst()) : bytes
        if payload.count == 6 {
            fields["keys"] = stride(from: 0, to: 6, by: 2).map {
                UInt16(payload[$0]) | UInt16(payload[$0 + 1]) << 8
            }
        }
    }
    emit(fields)
}, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
let result = IOHIDManagerOpen(manager, options)
emit(["event": "open", "result": result, "exclusive": options != 0,
      "inputMonitoringAccess": IOHIDCheckAccess(kIOHIDRequestTypeListenEvent).rawValue])
guard result == kIOReturnSuccess else {
    NSLog("Xiaomi remote capture failed: 0x%08X", result)
    exit(1)
}
defer {
    IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    IOHIDManagerClose(manager, options)
}
NSLog("Xiaomi remote capture ready; bounded to %.0f seconds", duration)
RunLoop.current.run(until: Date().addingTimeInterval(min(max(duration, 1), 1800)))
emit(["event": "finished"])
