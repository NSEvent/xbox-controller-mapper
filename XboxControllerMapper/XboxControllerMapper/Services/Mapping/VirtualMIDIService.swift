import CoreMIDI
import Foundation

protocol MIDIControlChangeSending: AnyObject, Sendable {
	func sendPress(_ message: MIDIControlChange)
	func sendRelease(_ message: MIDIControlChange)
	func pulse(_ message: MIDIControlChange)
}

/// Publishes a stable MIDI 1.0 virtual source named "ControllerKeys".
final class VirtualMIDIService: MIDIControlChangeSending, @unchecked Sendable {
	static let shared = VirtualMIDIService()

	static let sourceName = "ControllerKeys"
	static let sourceUniqueID: MIDIUniqueID = 0x434B5953 // "CKYS"

	private let queue = DispatchQueue(label: "xyz.kevintang.controllerkeys.midi")
	private var client = MIDIClientRef()
	private var source = MIDIEndpointRef()

	private init() {
		let clientStatus = MIDIClientCreate(
			"\(Self.sourceName) MIDI Client" as CFString,
			nil,
			nil,
			&client
		)
		guard clientStatus == noErr else {
			NSLog("[VirtualMIDI] MIDIClientCreate failed: %d", clientStatus)
			return
		}

		let sourceStatus = MIDISourceCreate(client, Self.sourceName as CFString, &source)
		guard sourceStatus == noErr else {
			NSLog("[VirtualMIDI] MIDISourceCreate failed: %d", sourceStatus)
			MIDIClientDispose(client)
			client = MIDIClientRef()
			return
		}

		let idStatus = MIDIObjectSetIntegerProperty(
			source,
			kMIDIPropertyUniqueID,
			Self.sourceUniqueID
		)
		if idStatus != noErr {
			NSLog("[VirtualMIDI] Could not set stable source unique ID: %d", idStatus)
		}
	}

	deinit {
		if source != MIDIEndpointRef() {
			MIDIEndpointDispose(source)
		}
		if client != MIDIClientRef() {
			MIDIClientDispose(client)
		}
	}

	func sendPress(_ message: MIDIControlChange) {
		enqueue(message, value: message.pressValue)
	}

	func sendRelease(_ message: MIDIControlChange) {
		enqueue(message, value: message.releaseValue)
	}

	func pulse(_ message: MIDIControlChange) {
		queue.async { [weak self] in
			self?.sendPacket(message, value: message.pressValue)
			self?.queue.asyncAfter(deadline: .now() + 0.03) { [weak self] in
				self?.sendPacket(message, value: message.releaseValue)
			}
		}
	}

	private func enqueue(_ message: MIDIControlChange, value: Int) {
		queue.async { [weak self] in
			self?.sendPacket(message, value: value)
		}
	}

	private func sendPacket(_ message: MIDIControlChange, value: Int) {
		guard source != MIDIEndpointRef() else { return }

		let status = UInt8(0xB0 | ((message.channel - 1) & 0x0F))
		var bytes = [
			status,
			UInt8(message.controller & 0x7F),
			UInt8(value & 0x7F)
		]
		var packetList = MIDIPacketList()
		let packet = MIDIPacketListInit(&packetList)
		let addedPacket = bytes.withUnsafeMutableBufferPointer { buffer in
			MIDIPacketListAdd(
				&packetList,
				MemoryLayout<MIDIPacketList>.size,
				packet,
				0,
				buffer.count,
				buffer.baseAddress!
			)
		}
		guard addedPacket != nil else {
			NSLog("[VirtualMIDI] Could not add MIDI CC packet")
			return
		}

		let receiveStatus = MIDIReceived(source, &packetList)
		if receiveStatus != noErr {
			NSLog("[VirtualMIDI] MIDIReceived failed: %d", receiveStatus)
		}
	}
}
