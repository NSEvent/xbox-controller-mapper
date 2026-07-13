import CommonCrypto
import CoreBluetooth
import Foundation
import Security

enum OuraRingProtocol {
	static let serviceUUID = CBUUID(string: "98ED0001-A541-11E4-B6A0-0002A5D5C51B")
	static let writeCharacteristicUUID = CBUUID(string: "98ED0002-A541-11E4-B6A0-0002A5D5C51B")
	static let notifyCharacteristicUUID = CBUUID(string: "98ED0003-A541-11E4-B6A0-0002A5D5C51B")

	static let tapToTagFeature: UInt8 = 0x07
	static let realtimeAccelerometerBitmask: UInt32 = 0x20
	static let realtimeAccelerometerResponseTag: UInt8 = 0x33
	static let accelerometerCountsPerG = 1000.0

	static func nonceCommand() -> Data {
		Data([0x2f, 0x01, 0x2b])
	}

	static func installKeyCommand(_ key: Data) -> Data {
		var data = Data([0x24, UInt8(key.count)])
		data.append(key)
		return data
	}

	static func authProofCommand(nonce: Data, key: Data) -> Data? {
		guard nonce.count == 15, key.count == kCCKeySizeAES128 else { return nil }
		var block = Data()
		block.append(nonce)
		block.append(0x01)
		block.append(Data(repeating: 0x10, count: 16))
		guard let encrypted = aes128ECBEncrypt(block, key: key), encrypted.count >= 16 else { return nil }
		var command = Data([0x2f, 0x11, 0x2d])
		command.append(encrypted.prefix(16))
		return command
	}

	static func readFeatureCommand(_ feature: UInt8) -> Data {
		Data([0x2f, 0x02, 0x20, feature])
	}

	static func enableFeatureCommand(_ feature: UInt8, value: UInt8) -> Data {
		Data([0x2f, 0x03, 0x22, feature, value])
	}

	static func subscribeFeatureCommand(_ feature: UInt8, value: UInt8) -> Data {
		Data([0x2f, 0x03, 0x26, feature, value])
	}

	static func enableNotificationsCommand() -> Data {
		Data([0x1c, 0x01, 0x3f])
	}

	static func startAccelerometerCommand(durationMinutes: UInt16, delay: UInt8 = 0) -> Data {
		var data = Data([0x06, 0x07])
		data.append(littleEndianBytes(realtimeAccelerometerBitmask))
		data.append(littleEndianBytes(durationMinutes))
		data.append(delay)
		return data
	}

	static func stopRealtimeCommand() -> Data {
		Data([0x06, 0x04, 0x00, 0x00, 0x00, 0x00])
	}

	static func newAuthKey() -> Data? {
		var bytes = [UInt8](repeating: 0, count: kCCKeySizeAES128)
		let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
		guard result == errSecSuccess else { return nil }
		return Data(bytes)
	}

	private static func aes128ECBEncrypt(_ data: Data, key: Data) -> Data? {
		guard key.count == kCCKeySizeAES128 else { return nil }

		let outputCapacity = data.count + kCCBlockSizeAES128
		var output = [UInt8](repeating: 0, count: outputCapacity)
		var outputLength = 0

		let status = output.withUnsafeMutableBytes { outputBytes in
			data.withUnsafeBytes { dataBytes in
				key.withUnsafeBytes { keyBytes in
					CCCrypt(
						CCOperation(kCCEncrypt),
						CCAlgorithm(kCCAlgorithmAES),
						CCOptions(kCCOptionECBMode),
						keyBytes.baseAddress,
						key.count,
						nil,
						dataBytes.baseAddress,
						data.count,
						outputBytes.baseAddress,
						outputCapacity,
						&outputLength
					)
				}
			}
		}

		guard status == kCCSuccess else { return nil }
		return Data(output.prefix(outputLength))
	}

	private static func littleEndianBytes(_ value: UInt32) -> Data {
		var littleEndian = value.littleEndian
		return Data(bytes: &littleEndian, count: MemoryLayout<UInt32>.size)
	}

	private static func littleEndianBytes(_ value: UInt16) -> Data {
		var littleEndian = value.littleEndian
		return Data(bytes: &littleEndian, count: MemoryLayout<UInt16>.size)
	}
}

enum OuraAuthStatus: UInt8 {
	case success = 0
	case wrongKey = 1
	case inFactoryReset = 2
	case notOriginalDevice = 3

	var displayName: String {
		switch self {
		case .success: return "authenticated"
		case .wrongKey: return "wrong auth key"
		case .inFactoryReset: return "factory reset"
		case .notOriginalDevice: return "not original onboarded device"
		}
	}
}

struct OuraRingFrame: Equatable {
	let op: UInt8
	let payload: Data
}

enum OuraRingDecodedEvent: Equatable {
	case nonce(Data)
	case authStatus(OuraAuthStatus)
	case keyInstallStatus(success: Bool)
	case tap
	case motion(OuraMotionSample)
	case unknown(String)
}

enum OuraRingScanMatcher {
	static func match(peripheralName: String?, advertisementData: [String: Any]) -> String? {
		if advertisedServiceUUIDs(in: advertisementData).contains(OuraRingProtocol.serviceUUID) {
			return "service"
		}
		if let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String,
		   isOuraName(localName) {
			return "local name"
		}
		if let peripheralName, isOuraName(peripheralName) {
			return "peripheral name"
		}
		return nil
	}

	static func isOuraName(_ name: String) -> Bool {
		let lowered = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		return lowered.contains("oura") || lowered.contains("ōura")
	}

	private static func advertisedServiceUUIDs(in advertisementData: [String: Any]) -> Set<CBUUID> {
		var uuids = Set<CBUUID>()
		for key in [
			CBAdvertisementDataServiceUUIDsKey,
			CBAdvertisementDataOverflowServiceUUIDsKey,
			CBAdvertisementDataSolicitedServiceUUIDsKey
		] {
			if let values = advertisementData[key] as? [CBUUID] {
				uuids.formUnion(values)
			}
		}
		if let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] {
			uuids.formUnion(serviceData.keys)
		}
		return uuids
	}
}

enum OuraRingPacketDecoder {
	static func decode(_ data: Data) -> [OuraRingDecodedEvent] {
		let frames = parseFrames(data)
		var events: [OuraRingDecodedEvent] = []

		for frame in frames {
			events.append(contentsOf: decode(frame))
		}

		if events.isEmpty, let sample = motionSample(from: [UInt8](data)) {
			events.append(.motion(sample))
		}

		if events.isEmpty {
			events.append(.unknown(data.ouraHexString))
		}

		return events
	}

	static func parseFrames(_ data: Data) -> [OuraRingFrame] {
		let bytes = [UInt8](data)
		var frames: [OuraRingFrame] = []
		var offset = 0

		while offset + 2 <= bytes.count {
			let op = bytes[offset]
			let length = Int(bytes[offset + 1])
			let payloadStart = offset + 2

			if op == OuraRingProtocol.realtimeAccelerometerResponseTag {
				frames.append(OuraRingFrame(op: op, payload: Data(bytes[payloadStart..<bytes.count])))
				break
			}

			let payloadEnd = payloadStart + length
			guard payloadEnd <= bytes.count else { break }
			frames.append(OuraRingFrame(op: op, payload: Data(bytes[payloadStart..<payloadEnd])))
			offset = payloadEnd
		}

		return frames
	}

	private static func decode(_ frame: OuraRingFrame) -> [OuraRingDecodedEvent] {
		switch frame.op {
		case 0x25:
			return [.keyInstallStatus(success: frame.payload.first == 0x00)]
		case 0x2f:
			return decodeSecureFrame(frame.payload)
		case OuraRingProtocol.realtimeAccelerometerResponseTag:
			return decodeAccelerometerFrame(frame.payload)
		default:
			if let sample = motionSample(from: [frame.op, UInt8(frame.payload.count)] + [UInt8](frame.payload)) {
				return [.motion(sample)]
			}
			return [.unknown(Data([frame.op, UInt8(frame.payload.count)] + [UInt8](frame.payload)).ouraHexString)]
		}
	}

	private static func decodeSecureFrame(_ payload: Data) -> [OuraRingDecodedEvent] {
		let bytes = [UInt8](payload)
		guard let command = bytes.first else { return [] }
		let body = Array(bytes.dropFirst())

		switch command {
		case 0x2c where body.count == 15:
			return [.nonce(Data(body))]
		case 0x2e where body.count >= 1:
			let status = OuraAuthStatus(rawValue: body[0]).map { OuraRingDecodedEvent.authStatus($0) }
			return [status ?? .unknown(payload.ouraHexString)]
		case 0x28:
			return decodeFeaturePush(body, originalPayload: payload)
		default:
			if let sample = motionSample(from: bytes) {
				return [.motion(sample)]
			}
			return [.unknown(payload.ouraHexString)]
		}
	}

	private static func decodeFeaturePush(_ body: [UInt8], originalPayload: Data) -> [OuraRingDecodedEvent] {
		guard let feature = body.first else { return [.unknown(originalPayload.ouraHexString)] }
		if feature == OuraRingProtocol.tapToTagFeature {
			return [.tap]
		}
		if let sample = motionSample(from: body) {
			return [.motion(sample)]
		}
		return [.unknown(originalPayload.ouraHexString)]
	}

	private static func decodeAccelerometerFrame(_ payload: Data) -> [OuraRingDecodedEvent] {
		let bytes = [UInt8](payload)
		guard bytes.count >= 8 else { return [] }

		var events: [OuraRingDecodedEvent] = []
		if let sample = accelerometerSample(from: bytes, offset: 2) {
			events.append(.motion(sample))
		}
		if bytes.count >= 14, let sample = accelerometerSample(from: bytes, offset: 8) {
			events.append(.motion(sample))
		}
		return events
	}

	private static func accelerometerSample(from bytes: [UInt8], offset: Int) -> OuraMotionSample? {
		guard offset + 5 < bytes.count else { return nil }
		let x = signedInt16(from: bytes, offset: offset)
		let y = signedInt16(from: bytes, offset: offset + 2)
		let z = signedInt16(from: bytes, offset: offset + 4)
		return OuraMotionSample(
			x: Double(x) / OuraRingProtocol.accelerometerCountsPerG,
			y: Double(y) / OuraRingProtocol.accelerometerCountsPerG,
			z: Double(z) / OuraRingProtocol.accelerometerCountsPerG,
			timestamp: CFAbsoluteTimeGetCurrent()
		)
	}

	private static func signedInt16(from bytes: [UInt8], offset: Int) -> Int16 {
		Int16(bitPattern: UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8))
	}

	private static func motionSample(from bytes: [UInt8]) -> OuraMotionSample? {
		guard let recordStart = bytes.firstIndex(of: 0x47), recordStart + 9 < bytes.count else { return nil }
		let x = normalizedMotionAxis(bytes[recordStart + 7])
		let y = normalizedMotionAxis(bytes[recordStart + 8])
		let z = normalizedMotionAxis(bytes[recordStart + 9])
		return OuraMotionSample(x: x, y: y, z: z, timestamp: CFAbsoluteTimeGetCurrent())
	}

	private static func normalizedMotionAxis(_ byte: UInt8) -> Double {
		let value = Double(Int8(bitPattern: byte)) * 8.0
		return max(-1.0, min(1.0, value / 512.0))
	}
}

extension Data {
	var ouraHexString: String {
		map { String(format: "%02x", $0) }.joined(separator: " ")
	}
}
