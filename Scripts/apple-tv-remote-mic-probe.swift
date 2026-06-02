#!/usr/bin/env swift

import Foundation
import IOKit
import IOKit.hid

private enum ProbeConstants {
    static let appleVendorID = 0x05AC
    static let appleBluetoothCompanyID = 76
    static let knownBluetoothRemoteProductIDs: Set<Int> = [614, 621, 788, 789]
    static let consumerUsagePage = 0x0C
    static let microphoneUsage = 0x04
    static let inputEnableByte: UInt8 = 0xAF
    static let micReportID: UInt32 = 0xFA
    static let defaultReportBufferSize = 512
}

private final class ProbeRegistration {
    let device: IOHIDDevice
    let key: String
    let isAudioDevice: Bool
    let buffer: UnsafeMutablePointer<UInt8>
    let bufferSize: Int

    init(device: IOHIDDevice, key: String, isAudioDevice: Bool, buffer: UnsafeMutablePointer<UInt8>, bufferSize: Int) {
        self.device = device
        self.key = key
        self.isAudioDevice = isAudioDevice
        self.buffer = buffer
        self.bufferSize = bufferSize
    }
}

private final class AppleTVRemoteMicProbe {
    private let duration: TimeInterval
    private let seize: Bool
    private var manager: IOHIDManager?
    private var registrations: [ProbeRegistration] = []
    private var enableDevices: [String: IOHIDDevice] = [:]
    private var micFrameCount = 0
    private var audioReportCount = 0
    private var otherRemoteReportCount = 0
    private var valueCount = 0
    private var anyReportCount = 0

    init(duration: TimeInterval, seize: Bool) {
        self.duration = duration
        self.seize = seize
    }

    func run() {
        log("Apple TV Remote mic probe starting")
        log("duration=\(Int(duration))s seize=\(seize ? "yes" : "no")")
        log("Quit ControllerKeys first if this probe cannot open the remote audio HID child.")

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager

        let matching = Self.matchingCriteria()
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, probeDeviceMatchedCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, probeDeviceRemovedCallback, context)
        IOHIDManagerRegisterInputValueCallback(manager, probeInputValueCallback, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        let options = seize ? IOOptionBits(kIOHIDOptionsTypeSeizeDevice) : IOOptionBits(kIOHIDOptionsTypeNone)
        let openResult = IOHIDManagerOpen(manager, options)
        log(String(format: "IOHIDManagerOpen result=0x%08X", openResult))

        if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !devices.isEmpty {
            for device in devices {
                deviceMatched(device)
            }
        } else {
            log("No matching Apple TV Remote microphone HID device is currently visible.")
        }

        writeInputEnableToAllRemoteChildren()
        log("Hold the Siri/mic button on the remote during this window.")
        RunLoop.current.run(until: Date().addingTimeInterval(duration))
        stop()

        log("summary: reports=\(anyReportCount) values=\(valueCount) micReport0xFA=\(micFrameCount) audioReport0xFF=\(audioReportCount) otherRemoteReports=\(otherRemoteReportCount)")
        if micFrameCount == 0 && audioReportCount == 0 && otherRemoteReportCount == 0 && valueCount == 0 {
            log("No remote reports or HID values reached user-space IOHID.")
            log("If PacketLogger sees mic traffic on-air at the same time, macOS is consuming the stream before apps can read it.")
        }
    }

    private func stop() {
        for registration in registrations {
            IOHIDDeviceRegisterInputReportCallback(
                registration.device,
                registration.buffer,
                registration.bufferSize,
                nil,
                nil
            )
            IOHIDDeviceUnscheduleFromRunLoop(
                registration.device,
                CFRunLoopGetCurrent(),
                CFRunLoopMode.defaultMode.rawValue
            )
            IOHIDDeviceClose(registration.device, seize ? IOOptionBits(kIOHIDOptionsTypeSeizeDevice) : IOOptionBits(kIOHIDOptionsTypeNone))
            registration.buffer.deallocate()
        }
        registrations.removeAll()
        enableDevices.removeAll()

        if let manager {
            IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
            IOHIDManagerRegisterInputValueCallback(manager, nil, nil)
            IOHIDManagerClose(manager, seize ? IOOptionBits(kIOHIDOptionsTypeSeizeDevice) : IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        }
        manager = nil
    }

    fileprivate func deviceMatched(_ device: IOHIDDevice) {
        let key = Self.deviceKey(device)
        guard enableDevices[key] == nil else { return }
        guard Self.isAppleTVRemoteHIDChild(device) else {
            log("Ignoring non-remote HID device: \(Self.deviceName(device))")
            return
        }

        enableDevices[key] = device
        let isAudioDevice = Self.isAppleTVRemoteAudioDevice(device)
        log("Matched Apple TV Remote \(isAudioDevice ? "audio" : "child") HID device: \(Self.deviceName(device))")
        log(Self.deviceSummary(device))
        log(Self.reportIDSummary(device))

        let openResult = IOHIDDeviceOpen(device, seize ? IOOptionBits(kIOHIDOptionsTypeSeizeDevice) : IOOptionBits(kIOHIDOptionsTypeNone))
        log(String(format: "IOHIDDeviceOpen result=0x%08X", openResult))

        let bufferSize = max(Self.intProperty(device, kIOHIDMaxInputReportSizeKey as String) ?? 0, ProbeConstants.defaultReportBufferSize)
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        buffer.initialize(repeating: 0, count: bufferSize)
        registrations.append(ProbeRegistration(device: device, key: key, isAudioDevice: isAudioDevice, buffer: buffer, bufferSize: bufferSize))

        IOHIDDeviceRegisterInputReportCallback(
            device,
            buffer,
            bufferSize,
            probeInputReportCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    }

    fileprivate func deviceRemoved(_ device: IOHIDDevice) {
        log("Device removed: \(Self.deviceName(device))")
    }

    fileprivate func inputReport(reportID: UInt32, report: UnsafeMutablePointer<UInt8>, length: Int) {
        anyReportCount += 1
        let startsWithMicReportID = length > 0 && report[0] == UInt8(ProbeConstants.micReportID)
        if reportID == ProbeConstants.micReportID || startsWithMicReportID {
            micFrameCount += 1
            log("MIC reportID=0xFA len=\(length) bytes=\(hex(report, count: length, limit: 32))")
        } else if reportID == 0xFF {
            audioReportCount += 1
            log("AUDIO? reportID=0xFF len=\(length) bytes=\(hex(report, count: length, limit: 32))")
        } else {
            otherRemoteReportCount += 1
            log(String(format: "REMOTE reportID=0x%02X len=%d bytes=%@", reportID, length, hex(report, count: length, limit: 32)))
        }
    }

    fileprivate func inputValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)
        guard Self.isAppleTVRemoteHIDChild(device) else { return }

        valueCount += 1
        let reportID = IOHIDElementGetReportID(element)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let length = IOHIDValueGetLength(value)
        let bytes = IOHIDValueGetBytePtr(value)
        let intValue = IOHIDValueGetIntegerValue(value)
        if length > 8 {
            log(String(
                format: "VALUE reportID=0x%02X usagePage=0x%X usage=0x%X len=%d bytes=%@",
                reportID,
                usagePage,
                usage,
                length,
                hex(bytes, count: length, limit: 32)
            ))
        } else {
            log(String(
                format: "VALUE reportID=0x%02X usagePage=0x%X usage=0x%X int=%lld len=%d",
                reportID,
                usagePage,
                usage,
                intValue,
                length
            ))
        }
    }

    private func writeInputEnableToAllRemoteChildren() {
        log("Writing 0xAF enable to \(enableDevices.count) Apple TV Remote HID child device(s)")
        for device in enableDevices.values.sorted(by: { Self.deviceKey($0) < Self.deviceKey($1) }) {
            writeInputEnable(to: device)
        }
    }

    private func writeInputEnable(to device: IOHIDDevice) {
        var featureIDs = Self.reportIDs(for: device, types: [kIOHIDElementTypeFeature])
        var outputIDs = Self.reportIDs(for: device, types: [kIOHIDElementTypeOutput])
        if featureIDs.isEmpty, (Self.intProperty(device, kIOHIDMaxFeatureReportSizeKey as String) ?? 0) > 0 {
            featureIDs = [0xFF, 0x00]
        }
        if outputIDs.isEmpty, (Self.intProperty(device, kIOHIDMaxOutputReportSizeKey as String) ?? 0) > 0 {
            outputIDs = [0xFF, 0x00]
        }
        let featureCandidates = featureIDs.isEmpty ? [UInt8(0)] : Array(featureIDs.prefix(16))
        let outputCandidates = Array(outputIDs.prefix(16))

        var attempts: [(IOHIDReportType, UInt8, [UInt8])] = []
        for reportID in featureCandidates {
            attempts.append((kIOHIDReportTypeFeature, reportID, [ProbeConstants.inputEnableByte]))
            attempts.append((kIOHIDReportTypeFeature, reportID, [reportID, ProbeConstants.inputEnableByte]))
        }
        for reportID in outputCandidates {
            attempts.append((kIOHIDReportTypeOutput, reportID, [ProbeConstants.inputEnableByte]))
            attempts.append((kIOHIDReportTypeOutput, reportID, [reportID, ProbeConstants.inputEnableByte]))
        }

        if attempts.isEmpty {
            attempts = [(kIOHIDReportTypeFeature, 0, [ProbeConstants.inputEnableByte])]
        }

        for (type, reportID, payload) in attempts {
            let result = payload.withUnsafeBufferPointer { buffer in
                IOHIDDeviceSetReport(
                    device,
                    type,
                    CFIndex(reportID),
                    buffer.baseAddress!,
                    buffer.count
                )
            }
            log(String(
                format: "enable write device=%@ usagePage=0x%X usage=0x%X type=%@ reportID=0x%02X payload=%@ result=0x%08X",
                Self.deviceName(device),
                Self.intProperty(device, "PrimaryUsagePage") ?? -1,
                Self.intProperty(device, "PrimaryUsage") ?? -1,
                Self.reportTypeName(type),
                reportID,
                payload.map { String(format: "%02X", $0) }.joined(separator: " "),
                result
            ))
        }
    }

    private static func matchingCriteria() -> CFArray {
        knownRemoteProductCriteria() as CFArray
    }

    private static func knownRemoteProductCriteria() -> [CFDictionary] {
        ProbeConstants.knownBluetoothRemoteProductIDs.map { productID in
            [
                kIOHIDVendorIDKey as String: ProbeConstants.appleBluetoothCompanyID,
                kIOHIDProductIDKey as String: productID,
            ] as CFDictionary
        }
    }

    private static func isAppleTVRemoteHIDChild(_ device: IOHIDDevice) -> Bool {
        let vendorID = intProperty(device, kIOHIDVendorIDKey as String)
        let productID = intProperty(device, kIOHIDProductIDKey as String)
        let product = stringProperty(device, kIOHIDProductKey as String).lowercased()
        let serial = stringProperty(device, kIOHIDSerialNumberKey as String).lowercased()
        let bundleID = stringProperty(device, kCFBundleIdentifierKey as String).lowercased()
        let kernelBundleID = stringProperty(device, "CFBundleIdentifierKernel").lowercased()
        let appleBluetoothRemote = boolProperty(device, "AppleBluetoothRemote")

        let knownBluetoothRemote = vendorID == ProbeConstants.appleBluetoothCompanyID
            && productID.map(ProbeConstants.knownBluetoothRemoteProductIDs.contains) == true
        let namedRemote = product.contains("remote")
            || serial.contains("c08")
            || bundleID.contains("applebluetoothremote")
            || kernelBundleID.contains("applebluetoothremote")
            || appleBluetoothRemote
        return knownBluetoothRemote || namedRemote
    }

    private static func isAppleTVRemoteAudioDevice(_ device: IOHIDDevice) -> Bool {
        let primaryUsagePage = intProperty(device, "PrimaryUsagePage")
            ?? intProperty(device, kIOHIDDeviceUsagePageKey as String)
        let primaryUsage = intProperty(device, "PrimaryUsage")
            ?? intProperty(device, kIOHIDDeviceUsageKey as String)
        return isAppleTVRemoteHIDChild(device)
            && primaryUsagePage == ProbeConstants.consumerUsagePage
            && primaryUsage == ProbeConstants.microphoneUsage
    }

    private static func reportIDs(for device: IOHIDDevice, types: Set<IOHIDElementType>) -> [UInt8] {
        guard let elements = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] else {
            return []
        }
        let ids = elements.compactMap { element -> UInt8? in
            guard types.contains(IOHIDElementGetType(element)) else { return nil }
            let reportID = IOHIDElementGetReportID(element)
            guard reportID >= 0 && reportID <= UInt8.max else { return nil }
            return UInt8(reportID)
        }
        return Array(Set(ids)).sorted()
    }

    private static func reportIDSummary(_ device: IOHIDDevice) -> String {
        let inputIDs = reportIDs(for: device, types: [kIOHIDElementTypeInput_Button, kIOHIDElementTypeInput_Misc, kIOHIDElementTypeInput_Axis, kIOHIDElementTypeInput_ScanCodes])
        let outputIDs = reportIDs(for: device, types: [kIOHIDElementTypeOutput])
        let featureIDs = reportIDs(for: device, types: [kIOHIDElementTypeFeature])
        return "reportIDs input=\(formatIDs(inputIDs)) output=\(formatIDs(outputIDs)) feature=\(formatIDs(featureIDs))"
    }

    private static func formatIDs(_ ids: [UInt8]) -> String {
        if ids.isEmpty { return "[]" }
        return "[" + ids.map { String(format: "0x%02X", $0) }.joined(separator: ", ") + "]"
    }

    private static func deviceSummary(_ device: IOHIDDevice) -> String {
        let keys = [
            kIOHIDTransportKey as String,
            kIOHIDManufacturerKey as String,
            kIOHIDProductKey as String,
            kIOHIDVendorIDKey as String,
            kIOHIDProductIDKey as String,
            "PrimaryUsagePage",
            "PrimaryUsage",
            kIOHIDMaxInputReportSizeKey as String,
            kIOHIDMaxOutputReportSizeKey as String,
            kIOHIDMaxFeatureReportSizeKey as String,
            "Privileged",
            "AppleBluetoothRemote",
            kCFBundleIdentifierKey as String,
            "CFBundleIdentifierKernel",
        ]
        return keys.compactMap { key in
            guard let value = property(device, key) else { return nil }
            return "\(key)=\(value)"
        }.joined(separator: " ")
    }

    private static func deviceName(_ device: IOHIDDevice) -> String {
        let manufacturer = stringProperty(device, kIOHIDManufacturerKey as String)
        let product = stringProperty(device, kIOHIDProductKey as String)
        return [manufacturer, product]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func deviceKey(_ device: IOHIDDevice) -> String {
        [
            stringProperty(device, "PhysicalDeviceUniqueID"),
            stringProperty(device, kIOHIDSerialNumberKey as String),
            String(intProperty(device, kIOHIDVendorIDKey as String) ?? -1),
            String(intProperty(device, kIOHIDProductIDKey as String) ?? -1),
            String(intProperty(device, "PrimaryUsagePage") ?? -1),
            String(intProperty(device, "PrimaryUsage") ?? -1),
            String(intProperty(device, kIOHIDLocationIDKey as String) ?? -1),
        ].joined(separator: "|")
    }

    private static func property(_ device: IOHIDDevice, _ key: String) -> Any? {
        IOHIDDeviceGetProperty(device, key as CFString)
    }

    private static func intProperty(_ device: IOHIDDevice, _ key: String) -> Int? {
        property(device, key) as? Int
    }

    private static func boolProperty(_ device: IOHIDDevice, _ key: String) -> Bool {
        property(device, key) as? Bool ?? false
    }

    private static func stringProperty(_ device: IOHIDDevice, _ key: String) -> String {
        property(device, key) as? String ?? ""
    }

    private static func reportTypeName(_ type: IOHIDReportType) -> String {
        switch type {
        case kIOHIDReportTypeInput: return "input"
        case kIOHIDReportTypeOutput: return "output"
        case kIOHIDReportTypeFeature: return "feature"
        default: return "unknown"
        }
    }
}

private func probeDeviceMatchedCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context else { return }
    let probe = Unmanaged<AppleTVRemoteMicProbe>.fromOpaque(context).takeUnretainedValue()
    probe.deviceMatched(device)
}

private func probeDeviceRemovedCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context else { return }
    let probe = Unmanaged<AppleTVRemoteMicProbe>.fromOpaque(context).takeUnretainedValue()
    probe.deviceRemoved(device)
}

private func probeInputReportCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    type: IOHIDReportType,
    reportID: UInt32,
    report: UnsafeMutablePointer<UInt8>,
    reportLength: CFIndex
) {
    guard let context else { return }
    let probe = Unmanaged<AppleTVRemoteMicProbe>.fromOpaque(context).takeUnretainedValue()
    probe.inputReport(reportID: reportID, report: report, length: Int(reportLength))
}

private func probeInputValueCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    value: IOHIDValue
) {
    guard let context else { return }
    let probe = Unmanaged<AppleTVRemoteMicProbe>.fromOpaque(context).takeUnretainedValue()
    probe.inputValue(value)
}

private func hex(_ pointer: UnsafePointer<UInt8>, count: Int, limit: Int) -> String {
    let shown = min(count, limit)
    let body = (0..<shown)
        .map { String(format: "%02X", pointer[$0]) }
        .joined(separator: " ")
    if count > shown {
        return body + " ..."
    }
    return body
}

private func log(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    FileHandle.standardOutput.write("[\(timestamp)] \(message)\n".data(using: .utf8)!)
}

private func usage(exitCode: Int32 = 2) -> Never {
    FileHandle.standardError.write("""
    Usage: swift Scripts/apple-tv-remote-mic-probe.swift [--seconds N] [--seize]

    --seconds N   Capture window length. Default: 20.
    --seize       Try kIOHIDOptionsTypeSeizeDevice. This may disrupt normal remote handling.

    """.data(using: .utf8)!)
    exit(exitCode)
}

var seconds: TimeInterval = 20
var seize = false
var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let arg = args.removeFirst()
    switch arg {
    case "--seconds":
        guard let value = args.first, let parsed = TimeInterval(value), parsed > 0 else {
            usage()
        }
        seconds = parsed
        args.removeFirst()
    case "--seize":
        seize = true
    case "--help", "-h":
        usage(exitCode: 0)
    default:
        usage()
    }
}

AppleTVRemoteMicProbe(duration: seconds, seize: seize).run()
