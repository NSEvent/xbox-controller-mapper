import Foundation
import Darwin

protocol CodexMicroOutputProtocol: Sendable {
	func tap(_ control: CodexMicroControl)
	func press(_ control: CodexMicroControl)
	func release(_ control: CodexMicroControl)
}

/// JSON-RPC and 64-byte HID-report framing used by Work Louder's Codex Micro.
enum CodexMicroWireProtocol {
	static let reportID: UInt8 = 0x06
	static let rpcChannel: UInt8 = 0x02
	static let reportSize = 64
	static let maximumPayloadSize = 61

	static func frames(for message: Data) -> [Data] {
		var frames: [Data] = []
		var offset = 0

		repeat {
			let count = min(maximumPayloadSize, message.count - offset)
			var frame = Data(repeating: 0, count: reportSize)
			frame[0] = reportID
			frame[1] = rpcChannel
			frame[2] = UInt8(count)
			if count > 0 {
				frame.replaceSubrange(3..<(3 + count), with: message[offset..<(offset + count)])
			}
			frames.append(frame)
			offset += count
		} while offset < message.count

		return frames
	}

	static func payload(from frame: Data) -> (channel: UInt8, bytes: Data)? {
		let bytes = [UInt8](frame)
		guard bytes.count >= 2 else { return nil }

		let headerOffset = bytes[0] == reportID ? 1 : 0
		guard bytes.count >= headerOffset + 2 else { return nil }
		let channel = bytes[headerOffset]
		let count = min(Int(bytes[headerOffset + 1]), bytes.count - headerOffset - 2)
		return (channel, Data(bytes[(headerOffset + 2)..<(headerOffset + 2 + count)]))
	}

	/// Host-to-device RPC has no delimiter. Extract balanced JSON objects while
	/// respecting quoted braces and escaped quote characters.
	static func extractJSONObjects(from buffer: inout Data) -> [Data] {
		let bytes = [UInt8](buffer)
		var objects: [Data] = []
		var depth = 0
		var isInString = false
		var isEscaped = false
		var start: Int?

		for (index, byte) in bytes.enumerated() {
			if isInString {
				if isEscaped {
					isEscaped = false
				} else if byte == 0x5C {
					isEscaped = true
				} else if byte == 0x22 {
					isInString = false
				}
				continue
			}

			switch byte {
			case 0x22:
				isInString = true
			case 0x7B:
				if depth == 0 { start = index }
				depth += 1
			case 0x7D where depth > 0:
				depth -= 1
				if depth == 0, let objectStart = start {
					objects.append(Data(bytes[objectStart...index]))
					start = nil
				}
			default:
				break
			}
		}

		if depth > 0, let start {
			buffer = Data(bytes[start...])
		} else {
			buffer.removeAll(keepingCapacity: true)
		}
		return objects
	}

	static func response(to request: Data) -> Data? {
		guard let object = try? JSONSerialization.jsonObject(with: request) as? [String: Any],
			  let id = object["id"] ?? object["i"] else { return nil }

		let method = (object["method"] ?? object["m"]) as? String
		let result: Any
		switch method {
		case "device.status":
			result = [
				"version": "1.0.0",
				"profile_index": 0,
				"layer_index": 0,
				"battery": 100,
				"is_charging": false
			] as [String: Any]
		case "sys.version":
			result = "1.0.0"
		default:
			// Lighting previews/configuration and future host methods must all be
			// acknowledged or the Work Louder RPC send queue stalls.
			result = true
		}

		guard var data = try? JSONSerialization.data(withJSONObject: ["id": id, "result": result]) else {
			return nil
		}
		data.append(0x0A)
		return data
	}

	static func notification(method: String, parameters: [String: Any]) -> Data? {
		guard var data = try? JSONSerialization.data(withJSONObject: ["m": method, "p": parameters]) else {
			return nil
		}
		data.append(0x0A)
		return data
	}
}

/// Local bridge used by the opt-in node-hid shim that launches ChatGPT with a
/// synthetic Codex Micro descriptor. The socket is user-only and never leaves
/// the Mac.
final class CodexMicroBridgeService: CodexMicroOutputProtocol, @unchecked Sendable {
	static let shared = CodexMicroBridgeService()
	static let socketPath = "/tmp/controllerkeys-codex-micro.sock"

	private let queue = DispatchQueue(label: "com.controllerkeys.codex-micro-bridge", qos: .userInteractive)
	private var listenerFD: Int32 = -1
	private var listenerSource: DispatchSourceRead?
	private var clientFD: Int32 = -1
	private var clientSource: DispatchSourceRead?
	private var socketReceiveBuffer = Data()
	private var rpcReceiveBuffer = Data()
	private var didLogMissingClient = false

	private init() {}

	func start() {
		queue.async { [weak self] in
			self?.startOnQueue()
		}
	}

	func stop() {
		queue.sync {
			closeClientOnQueue()
			listenerSource?.cancel()
			listenerSource = nil
			listenerFD = -1
			Darwin.unlink(Self.socketPath)
		}
	}

	func tap(_ control: CodexMicroControl) {
		start()
		queue.async { [weak self] in
			guard let self else { return }
			if control.joystickAngle != nil {
				sendJoystickOnQueue(control, distance: 1)
				sendJoystickNeutralOnQueue()
			} else if control.isDialRotation {
				sendHIDOnQueue(control, action: 2)
			} else {
				sendHIDOnQueue(control, action: 1)
				sendHIDOnQueue(control, action: 0)
			}
		}
	}

	func press(_ control: CodexMicroControl) {
		start()
		queue.async { [weak self] in
			guard let self else { return }
			if control.joystickAngle != nil {
				sendJoystickOnQueue(control, distance: 1)
			} else {
				sendHIDOnQueue(control, action: control.isDialRotation ? 2 : 1)
			}
		}
	}

	func release(_ control: CodexMicroControl) {
		start()
		queue.async { [weak self] in
			guard let self else { return }
			if control.joystickAngle != nil {
				sendJoystickNeutralOnQueue()
			} else if !control.isDialRotation {
				sendHIDOnQueue(control, action: 0)
			}
		}
	}

	private func startOnQueue() {
		guard listenerFD < 0 else { return }
		Darwin.unlink(Self.socketPath)

		let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
		guard fd >= 0 else {
			NSLog("[CodexMicroBridge] socket() failed: %s", strerror(errno))
			return
		}

		var address = sockaddr_un()
		address.sun_family = sa_family_t(AF_UNIX)
		address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
		let pathBytes = Array(Self.socketPath.utf8) + [0]
		guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
			Darwin.close(fd)
			NSLog("[CodexMicroBridge] Socket path is too long")
			return
		}
		withUnsafeMutableBytes(of: &address.sun_path) { destination in
			destination.copyBytes(from: pathBytes)
		}

		let bindResult = withUnsafePointer(to: &address) { pointer in
			pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
				Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
			}
		}
		guard bindResult == 0, Darwin.listen(fd, 2) == 0 else {
			NSLog("[CodexMicroBridge] bind/listen failed: %s", strerror(errno))
			Darwin.close(fd)
			Darwin.unlink(Self.socketPath)
			return
		}

		_ = Darwin.chmod(Self.socketPath, S_IRUSR | S_IWUSR)
		setNonBlocking(fd)
		listenerFD = fd
		let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
		source.setEventHandler { [weak self] in self?.acceptClientsOnQueue() }
		source.setCancelHandler { Darwin.close(fd) }
		listenerSource = source
		source.resume()
		NSLog("[CodexMicroBridge] Listening at %@", Self.socketPath)
	}

	private func acceptClientsOnQueue() {
		while true {
			let fd = Darwin.accept(listenerFD, nil, nil)
			if fd < 0 {
				if errno == EINTR { continue }
				return
			}

			setNonBlocking(fd)
			closeClientOnQueue()
			clientFD = fd
			socketReceiveBuffer.removeAll(keepingCapacity: true)
			rpcReceiveBuffer.removeAll(keepingCapacity: true)
			didLogMissingClient = false

			let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
			source.setEventHandler { [weak self] in self?.readClientOnQueue(fd: fd) }
			source.setCancelHandler { Darwin.close(fd) }
			clientSource = source
			source.resume()
			NSLog("[CodexMicroBridge] ChatGPT shim connected")
		}
	}

	private func readClientOnQueue(fd: Int32) {
		guard fd == clientFD else { return }
		var bytes = [UInt8](repeating: 0, count: 4096)

		while true {
			let count = bytes.withUnsafeMutableBytes {
				Darwin.read(fd, $0.baseAddress, $0.count)
			}
			if count > 0 {
				socketReceiveBuffer.append(contentsOf: bytes.prefix(count))
				processCompleteFramesOnQueue()
			} else if count == 0 {
				closeClientOnQueue()
				return
			} else if errno == EINTR {
				continue
			} else if errno == EAGAIN || errno == EWOULDBLOCK {
				return
			} else {
				NSLog("[CodexMicroBridge] Socket read failed: %s", strerror(errno))
				closeClientOnQueue()
				return
			}
		}
	}

	private func processCompleteFramesOnQueue() {
		while socketReceiveBuffer.count >= CodexMicroWireProtocol.reportSize {
			let frame = Data(socketReceiveBuffer.prefix(CodexMicroWireProtocol.reportSize))
			socketReceiveBuffer.removeFirst(CodexMicroWireProtocol.reportSize)
			guard let payload = CodexMicroWireProtocol.payload(from: frame),
				  payload.channel == CodexMicroWireProtocol.rpcChannel else { continue }
			rpcReceiveBuffer.append(payload.bytes)
			for request in CodexMicroWireProtocol.extractJSONObjects(from: &rpcReceiveBuffer) {
				if let response = CodexMicroWireProtocol.response(to: request) {
					sendMessageOnQueue(response)
				}
			}
		}
	}

	private func closeClientOnQueue() {
		guard clientFD >= 0 else { return }
		clientSource?.cancel()
		clientSource = nil
		clientFD = -1
		socketReceiveBuffer.removeAll(keepingCapacity: true)
		rpcReceiveBuffer.removeAll(keepingCapacity: true)
		NSLog("[CodexMicroBridge] ChatGPT shim disconnected")
	}

	private func sendHIDOnQueue(_ control: CodexMicroControl, action: Int) {
		guard let key = control.hidKey else { return }
		var parameters: [String: Any] = ["k": key, "act": action]
		if let agentIndex = control.agentIndex {
			parameters["ag"] = agentIndex
		}
		if let message = CodexMicroWireProtocol.notification(method: "v.oai.hid", parameters: parameters) {
			sendMessageOnQueue(message)
		}
	}

	private func sendJoystickOnQueue(_ control: CodexMicroControl, distance: Double) {
		guard let angle = control.joystickAngle,
			  let message = CodexMicroWireProtocol.notification(
				method: "v.oai.rad",
				parameters: ["a": angle, "d": distance]
			  ) else { return }
		sendMessageOnQueue(message)
	}

	private func sendJoystickNeutralOnQueue() {
		guard let message = CodexMicroWireProtocol.notification(
			method: "v.oai.rad",
			parameters: ["a": 0, "d": 0]
		) else { return }
		sendMessageOnQueue(message)
	}

	private func sendMessageOnQueue(_ message: Data) {
		guard clientFD >= 0 else {
			if !didLogMissingClient {
				didLogMissingClient = true
				NSLog("[CodexMicroBridge] Input ignored because the ChatGPT shim is not connected")
			}
			return
		}

		for frame in CodexMicroWireProtocol.frames(for: message) {
			let written = frame.withUnsafeBytes {
				Darwin.write(clientFD, $0.baseAddress, $0.count)
			}
			if written != frame.count {
				NSLog("[CodexMicroBridge] Socket write was incomplete")
				return
			}
		}
	}

	private func setNonBlocking(_ fd: Int32) {
		let flags = Darwin.fcntl(fd, F_GETFL)
		if flags >= 0 {
			_ = Darwin.fcntl(fd, F_SETFL, flags | O_NONBLOCK)
		}
		_ = Darwin.fcntl(fd, F_SETFD, FD_CLOEXEC)
	}
}
