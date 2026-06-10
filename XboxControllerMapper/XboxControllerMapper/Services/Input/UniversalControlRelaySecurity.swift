import Foundation
import Network
import CryptoKit
import Darwin

struct UniversalControlRelayNetworkPolicy {
    static func isAllowed(endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else {
            // Network.framework can hide inbound remote addresses behind opaque endpoint forms.
            // Let HMAC authentication make the final decision when the address is unavailable.
            return true
        }
        switch host {
        case .name(let name, _):
            if name.hasPrefix("IPv4#") || name.hasPrefix("IPv6#") {
                return true
            }
            return isAllowed(host: name)
        case .ipv4(let address):
            return isAllowedIPv4Bytes(Array(address.rawValue))
        case .ipv6(let address):
            return isAllowedIPv6Bytes(Array(address.rawValue))
        @unknown default:
            return true
        }
    }

    static func isAllowed(host: String) -> Bool {
        let trimmed = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return isAllowedIPv4(trimmed) || isAllowedIPv6(trimmed)
    }

    private static func isAllowedIPv4(_ host: String) -> Bool {
        var address = in_addr()
        guard host.withCString({ inet_pton(AF_INET, $0, &address) }) == 1 else { return false }
        let raw = UInt32(bigEndian: address.s_addr)
        return isAllowedIPv4Bytes([
            UInt8((raw >> 24) & 0xff),
            UInt8((raw >> 16) & 0xff),
            UInt8((raw >> 8) & 0xff),
            UInt8(raw & 0xff),
        ])
    }

    private static func isAllowedIPv4Bytes(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 4 else { return false }
        let first = bytes[0]
        let second = bytes[1]

        if first == 10 { return true }
        if first == 127 { return true }
        if first == 169 && second == 254 { return true }
        if first == 172 && (16...31).contains(second) { return true }
        if first == 192 && second == 168 { return true }
        if first == 100 && (64...127).contains(second) { return true } // Tailscale / CGNAT
        return false
    }

    private static func isAllowedIPv6(_ host: String) -> Bool {
        var address = in6_addr()
        guard host.withCString({ inet_pton(AF_INET6, $0, &address) }) == 1 else { return false }
        return isAllowedIPv6Bytes(withUnsafeBytes(of: &address) { Array($0) })
    }

    private static func isAllowedIPv6Bytes(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 2 else { return false }
        if bytes.count == 16,
           bytes[0..<10].allSatisfy({ $0 == 0 }),
           bytes[10] == 0xff,
           bytes[11] == 0xff {
            return isAllowedIPv4Bytes(Array(bytes[12..<16]))
        }

        guard bytes.count >= 16 else { return false }
        if bytes.allSatisfy({ $0 == 0 }) { return false }
        if bytes.dropLast().allSatisfy({ $0 == 0 }) && bytes.last == 1 { return true }
        if bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80 { return true } // fe80::/10
        if (bytes[0] & 0xfe) == 0xfc { return true } // fc00::/7
        return false
    }
}

struct UniversalControlRelayAuthenticator {
    static let version = "ck1"

    private let secret: SymmetricKey
    private let peerID: String
    private var outgoingCounter: UInt64
    private(set) var highestSeenIncomingCounters: [String: UInt64] = [:]

    init(secretData: Data, peerID: String, counterSeed: UInt64 = UInt64.random(in: 1...(UInt64.max / 2))) {
        self.secret = SymmetricKey(data: secretData)
        self.peerID = peerID
        self.outgoingCounter = counterSeed
    }

    mutating func seal(_ payload: String) -> String? {
        guard let payloadData = payload.data(using: .utf8) else { return nil }
        outgoingCounter &+= 1
        let encodedPayload = payloadData.base64EncodedString()
        let counter = String(outgoingCounter)
        let mac = Self.macHex(
            secret: secret,
            peerID: peerID,
            counter: counter,
            encodedPayload: encodedPayload
        )
        return "\(Self.version) \(peerID) \(counter) \(encodedPayload) \(mac)"
    }

    mutating func open(_ line: String) -> String? {
        let parts = line.split(separator: " ", maxSplits: 4).map(String.init)
        guard parts.count == 5,
              parts[0] == Self.version,
              let counter = UInt64(parts[2]),
              let data = Data(base64Encoded: parts[3]) else {
            return nil
        }

        let sender = parts[1]
        if let highestSeen = highestSeenIncomingCounters[sender], counter <= highestSeen {
            return nil
        }

        let expected = Self.macHex(
            secret: secret,
            peerID: sender,
            counter: parts[2],
            encodedPayload: parts[3]
        )
        guard Self.constantTimeEqual(parts[4], expected),
              let payload = String(data: data, encoding: .utf8),
              !payload.contains("\n"),
              !payload.contains("\r") else {
            return nil
        }

        highestSeenIncomingCounters[sender] = counter
        return payload
    }

    private static func macHex(
        secret: SymmetricKey,
        peerID: String,
        counter: String,
        encodedPayload: String
    ) -> String {
        let message = "\(version)\n\(peerID)\n\(counter)\n\(encodedPayload)"
        let mac = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: secret)
        return Data(mac).map { String(format: "%02x", $0) }.joined()
    }

    private static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }

        var diff: UInt8 = 0
        for index in left.indices {
            diff |= left[index] ^ right[index]
        }
        return diff == 0
    }
}

struct UniversalControlRelayPairingSession {
    static let version = "ckpair1"
    static let codeDigits = 6

    let localPeerID: String
    let localNonce: String
    let localPublicKeyBase64: String

    private let privateKey: Curve25519.KeyAgreement.PrivateKey

    init(localPeerID: String, nonce: String = UUID().uuidString.replacingOccurrences(of: "-", with: "")) {
        self.localPeerID = localPeerID
        self.localNonce = nonce
        self.privateKey = Curve25519.KeyAgreement.PrivateKey()
        self.localPublicKeyBase64 = privateKey.publicKey.rawRepresentation.base64EncodedString()
    }

    func helloLine() -> String {
        "\(Self.version) hello \(localPeerID) \(localPublicKeyBase64) \(localNonce)"
    }

    func responseLine(remotePeerID: String, remotePublicKeyBase64: String, remoteNonce: String) -> String? {
        guard derive(
            remotePeerID: remotePeerID,
            remotePublicKeyBase64: remotePublicKeyBase64,
            remoteNonce: remoteNonce,
            localIsFirst: false
        ) != nil else {
            return nil
        }
        return "\(Self.version) response \(localPeerID) \(localPublicKeyBase64) \(localNonce)"
    }

    func derive(
        remotePeerID: String,
        remotePublicKeyBase64: String,
        remoteNonce: String,
        localIsFirst: Bool = true
    ) -> PairingResult? {
        guard let remoteData = Data(base64Encoded: remotePublicKeyBase64),
              let remotePublicKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: remoteData),
              let sharedSecret = try? privateKey.sharedSecretFromKeyAgreement(with: remotePublicKey) else {
            return nil
        }

        let transcript: String
        if localIsFirst {
            transcript = Self.transcript(
                firstPeerID: localPeerID,
                firstPublicKeyBase64: localPublicKeyBase64,
                firstNonce: localNonce,
                secondPeerID: remotePeerID,
                secondPublicKeyBase64: remotePublicKeyBase64,
                secondNonce: remoteNonce
            )
        } else {
            transcript = Self.transcript(
                firstPeerID: remotePeerID,
                firstPublicKeyBase64: remotePublicKeyBase64,
                firstNonce: remoteNonce,
                secondPeerID: localPeerID,
                secondPublicKeyBase64: localPublicKeyBase64,
                secondNonce: localNonce
            )
        }
        let salt = Data(SHA256.hash(data: Data(transcript.utf8)))
        let key = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: Data("ControllerKeys relay v1".utf8),
            outputByteCount: 32
        )
        let keyData = key.withUnsafeBytes { Data($0) }
        let code = Self.code(for: transcript, keyData: keyData)
        return PairingResult(code: code, keyData: keyData, transcript: transcript)
    }

    static func transcript(
        firstPeerID: String,
        firstPublicKeyBase64: String,
        firstNonce: String,
        secondPeerID: String,
        secondPublicKeyBase64: String,
        secondNonce: String
    ) -> String {
        [
            version,
            firstPeerID,
            firstPublicKeyBase64,
            firstNonce,
            secondPeerID,
            secondPublicKeyBase64,
            secondNonce
        ].joined(separator: "\n")
    }

    private static func code(for transcript: String, keyData: Data) -> String {
        let mac = HMAC<SHA256>.authenticationCode(
            for: Data("code\n\(transcript)".utf8),
            using: SymmetricKey(data: keyData)
        )
        let prefix = Data(mac).prefix(8).reduce(UInt64(0)) { partial, byte in
            (partial << 8) | UInt64(byte)
        }
        return String(format: "%06llu", prefix % 1_000_000)
    }

    struct PairingResult {
        let code: String
        let keyData: Data
        let transcript: String
    }
}
