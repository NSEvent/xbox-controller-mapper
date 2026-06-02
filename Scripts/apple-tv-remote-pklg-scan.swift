#!/usr/bin/env swift

import Foundation

private enum Endian {
    case big
    case little
}

private struct HCIRecord {
    let sequence: Int
    let direction: String
    let timestampDescription: String
    let bytes: [UInt8]
}

private struct PKLGParseResult {
    let endian: Endian
    let records: [HCIRecord]
    let parsedRecordCount: Int
    let usefulRecordCount: Int
}

struct ScanOptions {
    var maxEvents = 80
    var allATT = false
}

private struct EventLine {
    let sequence: Int
    let text: String
}

private struct PendingL2CAPPacket {
    let expectedLength: Int
    let cid: UInt16
    var payload: [UInt8]
}

private final class ATTScanner {
    private let options: ScanOptions
    private var pendingReadByConnectionHandle: [UInt16: UInt16] = [:]
    private var pendingL2CAPByConnectionHandle: [UInt16: PendingL2CAPPacket] = [:]
    private var events: [EventLine] = []

    private(set) var aclCount = 0
    private(set) var reassembledL2CAPCount = 0
    private(set) var attCount = 0
    private(set) var notificationCount = 0
    private(set) var indicationCount = 0
    private(set) var writeCount = 0
    private(set) var inputEnableWriteCount = 0
    private(set) var reportReferenceCount = 0
    private(set) var micCandidateCount = 0
    private(set) var faPrefixedCount = 0

    init(options: ScanOptions) {
        self.options = options
    }

    func scan(records: [HCIRecord]) {
        for record in records {
            scan(record: record)
        }
    }

    func printEvents() {
        for event in events {
            print("#\(event.sequence) \(event.text)")
        }
        if events.count == options.maxEvents {
            print("event output capped at \(options.maxEvents); rerun with --max-events N for more")
        }
    }

    private func scan(record: HCIRecord) {
        let bytes = record.bytes
        guard bytes.count >= 5, bytes[0] == 0x02 else { return }
        aclCount += 1

        let handlePBBC = readUInt16LE(bytes, 1)
        let connectionHandle = handlePBBC & 0x0FFF
        let pb = UInt8((handlePBBC >> 12) & 0x03)
        let aclLength = Int(readUInt16LE(bytes, 3))
        guard bytes.count >= 5 + aclLength else { return }

        let aclPayload = Array(bytes[5 ..< 5 + aclLength])
        guard !aclPayload.isEmpty else { return }

        if pb == 0x01 {
            guard var pending = pendingL2CAPByConnectionHandle[connectionHandle] else { return }
            pending.payload.append(contentsOf: aclPayload)
            if pending.payload.count >= pending.expectedLength {
                pendingL2CAPByConnectionHandle.removeValue(forKey: connectionHandle)
                reassembledL2CAPCount += 1
                scanL2CAPPayload(
                    record: record,
                    connectionHandle: connectionHandle,
                    cid: pending.cid,
                    payload: Array(pending.payload.prefix(pending.expectedLength))
                )
            } else {
                pendingL2CAPByConnectionHandle[connectionHandle] = pending
            }
            return
        }

        guard aclPayload.count >= 4 else { return }
        let l2capLength = Int(readUInt16LE(aclPayload, 0))
        let cid = readUInt16LE(aclPayload, 2)
        let l2capPayload = Array(aclPayload.dropFirst(4))
        if l2capPayload.count >= l2capLength {
            scanL2CAPPayload(
                record: record,
                connectionHandle: connectionHandle,
                cid: cid,
                payload: Array(l2capPayload.prefix(l2capLength))
            )
        } else {
            pendingL2CAPByConnectionHandle[connectionHandle] = PendingL2CAPPacket(
                expectedLength: l2capLength,
                cid: cid,
                payload: l2capPayload
            )
        }
    }

    private func scanL2CAPPayload(record: HCIRecord, connectionHandle: UInt16, cid: UInt16, payload: [UInt8]) {
        guard cid == 0x0004, !payload.isEmpty else { return }
        attCount += 1
        scanATT(
            record: record,
            connectionHandle: connectionHandle,
            att: payload
        )
    }

    private func scanATT(record: HCIRecord, connectionHandle: UInt16, att: [UInt8]) {
        let opcode = att[0]
        switch opcode {
        case 0x0A:
            guard att.count >= 3 else { return }
            let handle = readUInt16LE(att, 1)
            pendingReadByConnectionHandle[connectionHandle] = handle
            if options.allATT {
                append(record, "ATT Read Request handle=0x\(hexWord(handle)) dir=\(record.direction)")
            }

        case 0x0B:
            let value = Array(att.dropFirst())
            if let descriptorHandle = pendingReadByConnectionHandle.removeValue(forKey: connectionHandle),
               value.count == 2,
               isLikelyReportReference(value) {
                reportReferenceCount += 1
                append(
                    record,
                    "REPORT_REFERENCE descriptor=0x\(hexWord(descriptorHandle)) reportID=0x\(hexByte(value[0])) type=\(reportTypeName(value[1])) raw=\(hex(value, limit: 16))"
                )
            } else if options.allATT {
                append(record, "ATT Read Response len=\(value.count) value=\(hex(value, limit: 32))")
            }

        case 0x12, 0x52:
            guard att.count >= 3 else { return }
            let handle = readUInt16LE(att, 1)
            let value = Array(att.dropFirst(3))
            writeCount += 1
            if value.contains(0xAF) {
                inputEnableWriteCount += 1
                append(
                    record,
                    "WRITE_0xAF opcode=0x\(hexByte(opcode)) handle=0x\(hexWord(handle)) len=\(value.count) value=\(hex(value, limit: 32)) dir=\(record.direction)"
                )
            } else if options.allATT {
                append(
                    record,
                    "ATT Write opcode=0x\(hexByte(opcode)) handle=0x\(hexWord(handle)) len=\(value.count) value=\(hex(value, limit: 32)) dir=\(record.direction)"
                )
            }

        case 0x1B, 0x1D:
            guard att.count >= 3 else { return }
            let handle = readUInt16LE(att, 1)
            let value = Array(att.dropFirst(3))
            if opcode == 0x1B {
                notificationCount += 1
            } else {
                indicationCount += 1
            }
            scanNotificationValue(record: record, opcode: opcode, handle: handle, value: value)

        default:
            if options.allATT {
                append(record, "ATT opcode=0x\(hexByte(opcode)) len=\(att.count) bytes=\(hex(att, limit: 48)) dir=\(record.direction)")
            }
        }
    }

    private func scanNotificationValue(record: HCIRecord, opcode: UInt8, handle: UInt16, value: [UInt8]) {
        let kind = opcode == 0x1B ? "NOTIFY" : "INDICATE"
        if value.first == 0xFA {
            faPrefixedCount += 1
            append(
                record,
                "\(kind)_FA_PREFIX handle=0x\(hexWord(handle)) len=\(value.count) value=\(hex(value, limit: 80)) dir=\(record.direction)"
            )
        }

        if let mic = parseMicPayload(value) {
            micCandidateCount += 1
            append(
                record,
                "MIC_CANDIDATE handle=0x\(hexWord(handle)) payloadLen=\(value.count) seq=\(mic.sequence) opusLen=\(mic.opusLength) value=\(hex(value, limit: 96)) dir=\(record.direction)"
            )
            return
        }

        if value.count > 0 && value.count >= 90 && value.count <= 110 {
            append(
                record,
                "\(kind)_NEAR_MIC_SIZE handle=0x\(hexWord(handle)) len=\(value.count) value=\(hex(value, limit: 96)) dir=\(record.direction)"
            )
        } else if options.allATT {
            append(
                record,
                "\(kind) handle=0x\(hexWord(handle)) len=\(value.count) value=\(hex(value, limit: 48)) dir=\(record.direction)"
            )
        }
    }

    private func append(_ record: HCIRecord, _ text: String) {
        guard events.count < options.maxEvents else { return }
        events.append(EventLine(sequence: record.sequence, text: "\(record.timestampDescription) \(text)"))
    }
}

private func parseBTSnoop(_ data: [UInt8]) throws -> [HCIRecord] {
    guard data.count >= 16 else { throw ScanError.invalid("btsnoop file too short") }
    let magic = Array("btsnoop\0".utf8)
    guard Array(data[0 ..< 8]) == magic else { throw ScanError.invalid("not btsnoop") }
    let version = readUInt32BE(data, 8)
    let dataLinkType = readUInt32BE(data, 12)
    guard version == 1 else { throw ScanError.invalid("unsupported btsnoop version \(version)") }
    guard dataLinkType == 1002 else {
        throw ScanError.invalid("unsupported btsnoop link type \(dataLinkType); expected HCI UART/H4 1002")
    }

    var offset = 16
    var sequence = 1
    var records: [HCIRecord] = []
    while offset + 24 <= data.count {
        let originalLength = Int(readUInt32BE(data, offset))
        let includedLength = Int(readUInt32BE(data, offset + 4))
        let flags = readUInt32BE(data, offset + 8)
        let timestamp = readInt64BE(data, offset + 16)
        offset += 24
        guard includedLength >= 0, offset + includedLength <= data.count else { break }
        let payload = Array(data[offset ..< offset + includedLength])
        offset += includedLength

        let direction = (flags & 0x01) == 0 ? "tx" : "rx"
        let timestampDescription = btsnoopTimestampDescription(timestamp)
        if originalLength == includedLength {
            records.append(HCIRecord(sequence: sequence, direction: direction, timestampDescription: timestampDescription, bytes: payload))
        }
        sequence += 1
    }
    return records
}

private func parsePacketLogger(_ data: [UInt8]) -> PKLGParseResult {
    let little = parsePacketLogger(data, endian: .little)
    let big = parsePacketLogger(data, endian: .big)
    if little.usefulRecordCount > big.usefulRecordCount {
        return little
    }
    if big.usefulRecordCount > little.usefulRecordCount {
        return big
    }
    return data.count > 1 && data[1] == 0x01 ? little : big
}

private func parsePacketLogger(_ data: [UInt8], endian: Endian) -> PKLGParseResult {
    var offset = 0
    var sequence = 1
    var parsedRecordCount = 0
    var usefulRecordCount = 0
    var records: [HCIRecord] = []

    while offset + 13 <= data.count {
        let length = Int(readUInt32(data, offset, endian: endian))
        let timestamp = readUInt64(data, offset + 4, endian: endian)
        let packetType = data[offset + 12]
        guard length >= 9 else { break }
        let payloadLength = length - 9
        let payloadStart = offset + 13
        let nextOffset = payloadStart + payloadLength
        guard payloadLength >= 0, nextOffset <= data.count else { break }
        let payload = Array(data[payloadStart ..< nextOffset])
        offset = nextOffset
        parsedRecordCount += 1

        guard let uartType = packetLoggerUARTType(packetType) else {
            sequence += 1
            continue
        }

        let direction = packetType == 0x02 ? "tx" : packetType == 0x03 ? "rx" : "control"
        let bytes = [uartType] + payload
        if !bytes.isEmpty {
            usefulRecordCount += 1
            records.append(
                HCIRecord(
                    sequence: sequence,
                    direction: direction,
                    timestampDescription: packetLoggerTimestampDescription(timestamp),
                    bytes: bytes
                )
            )
        }
        sequence += 1
    }

    return PKLGParseResult(endian: endian, records: records, parsedRecordCount: parsedRecordCount, usefulRecordCount: usefulRecordCount)
}

private func packetLoggerUARTType(_ packetType: UInt8) -> UInt8? {
    switch packetType {
    case 0x00: return 0x01 // command
    case 0x01: return 0x04 // event
    case 0x02: return 0x02 // ACL tx
    case 0x03: return 0x02 // ACL rx
    default: return nil
    }
}

private func isLikelyReportReference(_ value: [UInt8]) -> Bool {
    guard value.count == 2 else { return false }
    return (value[1] == 1 || value[1] == 2 || value[1] == 3)
}

private func reportTypeName(_ byte: UInt8) -> String {
    switch byte {
    case 1: return "input"
    case 2: return "output"
    case 3: return "feature"
    default: return "type\(byte)"
    }
}

private func parseMicPayload(_ value: [UInt8]) -> (sequence: UInt16, opusLength: Int)? {
    let payload: [UInt8]
    if value.count == 100 && value[0] == 0xFA {
        payload = Array(value.dropFirst())
    } else {
        payload = value
    }

    guard payload.count == 99, payload.count >= 6 else { return nil }
    let sequence = readUInt16LE(payload, 2)
    let opusLength = Int(payload[4])
    guard opusLength > 0, opusLength <= 94, 5 + opusLength <= payload.count else { return nil }
    return (sequence, opusLength)
}

private func packetLoggerTimestampDescription(_ timestamp: UInt64) -> String {
    let seconds = timestamp >> 32
    let microseconds = timestamp & 0xFFFF_FFFF
    guard seconds > 0, microseconds < 1_000_000 else { return "time=raw:\(timestamp)" }
    let date = Date(timeIntervalSince1970: TimeInterval(seconds) + TimeInterval(microseconds) / 1_000_000)
    return "time=\(iso8601(date))"
}

private func btsnoopTimestampDescription(_ timestamp: Int64) -> String {
    let epoch2000 = Int64(0x00E0_3AB4_4A67_6000)
    let microsecondsSince2000 = timestamp - epoch2000
    let date = Date(timeIntervalSinceReferenceDate: TimeInterval(microsecondsSince2000) / 1_000_000)
    return "time=\(iso8601(date))"
}

private func iso8601(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}

private func hex(_ bytes: [UInt8], limit: Int) -> String {
    let shown = bytes.prefix(limit).map { String(format: "%02X", $0) }.joined(separator: " ")
    return bytes.count > limit ? shown + " ..." : shown
}

private func hexByte(_ byte: UInt8) -> String {
    String(format: "%02X", byte)
}

private func hexWord(_ word: UInt16) -> String {
    String(format: "%04X", word)
}

private func readUInt16LE(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
    UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
}

private func readUInt32BE(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
    (UInt32(bytes[offset]) << 24)
        | (UInt32(bytes[offset + 1]) << 16)
        | (UInt32(bytes[offset + 2]) << 8)
        | UInt32(bytes[offset + 3])
}

private func readInt64BE(_ bytes: [UInt8], _ offset: Int) -> Int64 {
    Int64(bitPattern: readUInt64(bytes, offset, endian: .big))
}

private func readUInt32(_ bytes: [UInt8], _ offset: Int, endian: Endian) -> UInt32 {
    switch endian {
    case .little:
        return UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    case .big:
        return readUInt32BE(bytes, offset)
    }
}

private func readUInt64(_ bytes: [UInt8], _ offset: Int, endian: Endian) -> UInt64 {
    var value: UInt64 = 0
    switch endian {
    case .little:
        for index in (0 ..< 8).reversed() {
            value = (value << 8) | UInt64(bytes[offset + index])
        }
    case .big:
        for index in 0 ..< 8 {
            value = (value << 8) | UInt64(bytes[offset + index])
        }
    }
    return value
}

private enum ScanError: Error, CustomStringConvertible {
    case invalid(String)
    var description: String { if case let .invalid(message) = self { return message }; return "" }
}

private func usage() -> Never {
    FileHandle.standardError.write("""
    Usage: swift Scripts/apple-tv-remote-pklg-scan.swift <capture.pklg|btsnoop_hci.log> [--max-events N] [--all-att]
    Scans PacketLogger/btsnoop BLE ATT traffic for 0xAF writes, HID Report
    Reference reads, and 99-byte Apple TV / Siri Remote mic payloads.
    """.data(using: .utf8)!)
    exit(2)
}

var args = Array(CommandLine.arguments.dropFirst())
guard !args.isEmpty else { usage() }
let capturePath = args.removeFirst()
var options = ScanOptions()

while !args.isEmpty {
    let arg = args.removeFirst()
    switch arg {
    case "--max-events":
        guard let value = args.first, let parsed = Int(value), parsed > 0 else { usage() }
        options.maxEvents = parsed
        args.removeFirst()
    case "--all-att":
        options.allATT = true
    default:
        usage()
    }
}

do {
    let data = [UInt8](try Data(contentsOf: URL(fileURLWithPath: capturePath)))
    let records: [HCIRecord]
    let sourceDescription: String
    if data.count >= 8 && Array(data[0 ..< 8]) == Array("btsnoop\0".utf8) {
        records = try parseBTSnoop(data)
        sourceDescription = "btsnoop"
    } else {
        let parsed = parsePacketLogger(data)
        records = parsed.records
        sourceDescription = "PacketLogger endian=\(parsed.endian == .little ? "little" : "big") parsedRecords=\(parsed.parsedRecordCount) usefulRecords=\(parsed.usefulRecordCount)"
    }

    let scanner = ATTScanner(options: options)
    scanner.scan(records: records)

    print("source: \(sourceDescription)")
    print("hciRecords=\(records.count) acl=\(scanner.aclCount) l2capReassembled=\(scanner.reassembledL2CAPCount) att=\(scanner.attCount) notifications=\(scanner.notificationCount) indications=\(scanner.indicationCount) writes=\(scanner.writeCount)")
    print("matches: write0xAF=\(scanner.inputEnableWriteCount) reportRefs=\(scanner.reportReferenceCount) micCandidates=\(scanner.micCandidateCount) faPrefixedNotifications=\(scanner.faPrefixedCount)")
    scanner.printEvents()
} catch {
    FileHandle.standardError.write("error: \(error)\n".data(using: .utf8)!)
    exit(1)
}
