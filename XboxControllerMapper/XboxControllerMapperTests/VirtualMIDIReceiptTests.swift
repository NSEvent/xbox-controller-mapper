import CoreMIDI
import XCTest
@testable import ControllerKeys

nonisolated private final class MIDIReceiptBuffer: @unchecked Sendable {
	private let lock = NSLock()
	private var packets: [[UInt8]] = []
	var received: [[UInt8]] { lock.withLock { packets } }
	func receive(_ list: UnsafePointer<MIDIPacketList>) {
		let offset = MemoryLayout<MIDIPacketList>.offset(of: \.packet)!
		var packet = UnsafeRawPointer(list).advanced(by: offset).assumingMemoryBound(to: MIDIPacket.self)
		for _ in 0..<list.pointee.numPackets {
			let bytes = withUnsafeBytes(of: packet.pointee.data) { Array($0.prefix(Int(packet.pointee.length))) }
			lock.withLock { packets.append(bytes) }
			packet = UnsafePointer(MIDIPacketNext(packet))
		}
	}
}

@MainActor
final class VirtualMIDIReceiptTests: XCTestCase {
	func testContinuousTriggerPacketsReachIndependentCoreMIDIReceiver() async throws {
		// A uniquely named test source cannot be confused with the installed app or a personal DAW source.
		let source = VirtualMIDIService(sourceName: "ControllerKeys receipt test \(UUID())", uniqueID: Int32.random(in: 1...Int32.max))
		XCTAssertNotEqual(source.sourceEndpoint, 0)
		var client = MIDIClientRef()
		var port = MIDIPortRef()
		XCTAssertEqual(MIDIClientCreate("ControllerKeys test receiver" as CFString, nil, nil, &client), noErr)
		defer { if port != 0 { MIDIPortDispose(port) }; if client != 0 { MIDIClientDispose(client) } }
		let buffer = MIDIReceiptBuffer()
		XCTAssertEqual(MIDIInputPortCreateWithBlock(client, "Receipt" as CFString, &port) { list, _ in buffer.receive(list) }, noErr)
		XCTAssertEqual(MIDIPortConnectSource(port, source.sourceEndpoint, nil), noErr)
		defer { MIDIPortDisconnectSource(port, source.sourceEndpoint) }
		let config = TriggerMIDIConfiguration(message: MIDIControlChange(channel: 4, controller: 11))
		let stream = TriggerMIDIOutput(sender: source)
		stream.update(left: 0, right: 0, leftConfiguration: config, rightConfiguration: nil, now: 0)
		stream.update(left: 0.7, right: 0, leftConfiguration: config, rightConfiguration: nil, now: 0.02)
		stream.update(left: 0.8, right: 0, leftConfiguration: config, rightConfiguration: nil, now: 0.04)
		stream.reset()
		source.flushPendingOutput()
		let arrived = await waitForCondition { buffer.received.flatMap { $0 }.count >= 12 }
		XCTAssertTrue(arrived, "Timed out waiting for real CoreMIDI packets")
		XCTAssertEqual(buffer.received.flatMap { $0 }, [[0xB3, 11, 0], [0xB3, 11, UInt8(config.value(for: 0.7))], [0xB3, 11, UInt8(config.value(for: 0.8))], [0xB3, 11, 0]].flatMap { $0 })
	}
}
