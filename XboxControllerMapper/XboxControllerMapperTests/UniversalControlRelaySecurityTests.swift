import XCTest
import Foundation
import Network
import CoreGraphics
@testable import ControllerKeys

final class UniversalControlRelaySecurityTests: XCTestCase {
    private let secret = Data((0..<32).map { UInt8($0) })

    func testAuthenticatedFrameRoundTrips() {
        var sender = UniversalControlRelayAuthenticator(
            secretData: secret,
            peerID: "sender",
            counterSeed: 10
        )
        var receiver = UniversalControlRelayAuthenticator(
            secretData: secret,
            peerID: "receiver",
            counterSeed: 50
        )

        let sealed = sender.seal("m 12 -4")

        XCTAssertEqual(receiver.open(sealed ?? ""), "m 12 -4")
    }

    func testPlaintextFrameIsRejected() {
        var receiver = UniversalControlRelayAuthenticator(
            secretData: secret,
            peerID: "receiver",
            counterSeed: 0
        )

        XCTAssertNil(receiver.open("m 12 -4"))
    }

    func testWrongSecretIsRejected() {
        var sender = UniversalControlRelayAuthenticator(
            secretData: secret,
            peerID: "sender",
            counterSeed: 1
        )
        var receiver = UniversalControlRelayAuthenticator(
            secretData: Data((32..<64).map { UInt8($0) }),
            peerID: "receiver",
            counterSeed: 1
        )

        let sealed = sender.seal("kp 0 0")

        XCTAssertNil(receiver.open(sealed ?? ""))
    }

    func testReplayIsRejected() {
        var sender = UniversalControlRelayAuthenticator(
            secretData: secret,
            peerID: "sender",
            counterSeed: 100
        )
        var receiver = UniversalControlRelayAuthenticator(
            secretData: secret,
            peerID: "receiver",
            counterSeed: 0
        )

        let sealed = sender.seal("sc 0 1 -1 -1 1 0")

        XCTAssertNotNil(receiver.open(sealed ?? ""))
        XCTAssertNil(receiver.open(sealed ?? ""))
    }

    func testOutOfOrderAuthenticatedFramesAreAccepted() {
        var sender = UniversalControlRelayAuthenticator(
            secretData: secret,
            peerID: "sender",
            counterSeed: 200
        )
        var receiver = UniversalControlRelayAuthenticator(
            secretData: secret,
            peerID: "receiver",
            counterSeed: 0
        )

        let older = sender.seal("pong abc") ?? ""
        let newer = sender.seal("uiState 0 0 0 0 0") ?? ""

        XCTAssertEqual(receiver.open(newer), "uiState 0 0 0 0 0")
        XCTAssertEqual(receiver.open(older), "pong abc")
        XCTAssertNil(receiver.open(older))
    }

    func testTamperedPayloadIsRejected() {
        var sender = UniversalControlRelayAuthenticator(
            secretData: secret,
            peerID: "sender",
            counterSeed: 7
        )
        var receiver = UniversalControlRelayAuthenticator(
            secretData: secret,
            peerID: "receiver",
            counterSeed: 0
        )

        let sealed = sender.seal("m 1 1") ?? ""
        let tampered = sealed.replacingOccurrences(of: "bSAxIDE=", with: "bSA5IDk=")

        XCTAssertNil(receiver.open(tampered))
    }

    func testNetworkPolicyAllowsPrivateLanAndTailnet() {
        XCTAssertTrue(UniversalControlRelayNetworkPolicy.isAllowed(host: "10.0.0.12"))
        XCTAssertTrue(UniversalControlRelayNetworkPolicy.isAllowed(host: "172.16.2.3"))
        XCTAssertTrue(UniversalControlRelayNetworkPolicy.isAllowed(host: "192.168.1.20"))
        XCTAssertTrue(UniversalControlRelayNetworkPolicy.isAllowed(host: "169.254.10.11"))
        XCTAssertTrue(UniversalControlRelayNetworkPolicy.isAllowed(host: "100.64.0.1"))
        XCTAssertTrue(UniversalControlRelayNetworkPolicy.isAllowed(host: "100.127.255.254"))
    }

    func testNetworkPolicyAllowsRawNWEndpointAddresses() {
        let local = NWEndpoint.hostPort(
            host: .ipv4(IPv4Address("127.0.0.1")!),
            port: 38383
        )
        let tailnet = NWEndpoint.hostPort(
            host: .ipv4(IPv4Address("100.92.71.35")!),
            port: 38383
        )
        let publicAddress = NWEndpoint.hostPort(
            host: .ipv4(IPv4Address("8.8.8.8")!),
            port: 38383
        )

        XCTAssertTrue(UniversalControlRelayNetworkPolicy.isAllowed(endpoint: local))
        XCTAssertTrue(UniversalControlRelayNetworkPolicy.isAllowed(endpoint: tailnet))
        XCTAssertFalse(UniversalControlRelayNetworkPolicy.isAllowed(endpoint: publicAddress))
    }

    func testNetworkPolicyDefersOpaqueInboundEndpointNamesToAuthentication() {
        let opaqueIPv4 = NWEndpoint.hostPort(host: .name("IPv4#abcd1234", nil), port: 38383)
        let opaqueIPv6 = NWEndpoint.hostPort(host: .name("IPv6#abcd1234", nil), port: 38383)

        XCTAssertTrue(UniversalControlRelayNetworkPolicy.isAllowed(endpoint: opaqueIPv4))
        XCTAssertTrue(UniversalControlRelayNetworkPolicy.isAllowed(endpoint: opaqueIPv6))
    }

    func testNetworkPolicyRejectsPublicIPv4AndOutsideTailnetRange() {
        XCTAssertFalse(UniversalControlRelayNetworkPolicy.isAllowed(host: "8.8.8.8"))
        XCTAssertFalse(UniversalControlRelayNetworkPolicy.isAllowed(host: "1.1.1.1"))
        XCTAssertFalse(UniversalControlRelayNetworkPolicy.isAllowed(host: "100.63.255.255"))
        XCTAssertFalse(UniversalControlRelayNetworkPolicy.isAllowed(host: "100.128.0.0"))
    }

    func testNetworkPolicyAllowsLocalIPv6Ranges() {
        XCTAssertTrue(UniversalControlRelayNetworkPolicy.isAllowed(host: "::1"))
        XCTAssertTrue(UniversalControlRelayNetworkPolicy.isAllowed(host: "fe80::1"))
        XCTAssertTrue(UniversalControlRelayNetworkPolicy.isAllowed(host: "fc00::1"))
        XCTAssertTrue(UniversalControlRelayNetworkPolicy.isAllowed(host: "fd7a:115c:a1e0::1"))
    }

    func testNetworkPolicyRejectsPublicIPv6() {
        XCTAssertFalse(UniversalControlRelayNetworkPolicy.isAllowed(host: "2606:4700:4700::1111"))
    }

    func testSystemCommandsAreNeverRelayed() {
        let command = SystemCommand.shellCommand(command: "touch /tmp/controllerkeys-should-not-run", inTerminal: false)

        XCTAssertFalse(UniversalControlMouseRelay.shared.sendSystemCommand(command))
    }

    func testCodePairingDerivesSameSixDigitCodeAndKey() {
        let initiator = UniversalControlRelayPairingSession(localPeerID: "macbook", nonce: "aaa")
        let receiver = UniversalControlRelayPairingSession(localPeerID: "studio", nonce: "bbb")

        let receiverResult = receiver.derive(
            remotePeerID: initiator.localPeerID,
            remotePublicKeyBase64: initiator.localPublicKeyBase64,
            remoteNonce: initiator.localNonce,
            localIsFirst: false
        )
        let initiatorResult = initiator.derive(
            remotePeerID: receiver.localPeerID,
            remotePublicKeyBase64: receiver.localPublicKeyBase64,
            remoteNonce: receiver.localNonce
        )

        XCTAssertNotNil(receiverResult)
        XCTAssertEqual(initiatorResult?.keyData, receiverResult?.keyData)
        XCTAssertEqual(initiatorResult?.code, receiverResult?.code)
        XCTAssertEqual(initiatorResult?.code.count, 6)
        XCTAssertTrue(initiatorResult?.code.allSatisfy(\.isNumber) == true)
    }

    func testCodePairingRejectsInvalidPublicKey() {
        let initiator = UniversalControlRelayPairingSession(localPeerID: "macbook", nonce: "aaa")

        XCTAssertNil(initiator.derive(
            remotePeerID: "studio",
            remotePublicKeyBase64: "not-base64",
            remoteNonce: "bbb"
        ))
    }

	func testDefaultHandoffEdgesAreHorizontalOnly() {
		XCTAssertEqual(
			UniversalControlHandoffEdgeDefaults.localEdges(configuredRawValue: nil),
			[.left, .right]
		)
		XCTAssertEqual(
			UniversalControlHandoffEdgeDefaults.localEdges(configuredRawValue: "bogus"),
			[.left, .right]
		)
		XCTAssertEqual(
			UniversalControlHandoffEdgeDefaults.localEdges(configuredRawValue: "left"),
			[.left]
		)
	}

	func testRemoteMouseMovementClampsOutwardDeltaAtEdge() {
		let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

		let movement = UniversalControlRemoteMouseMovementPolicy.boundedMovement(
			current: CGPoint(x: 99, y: 50),
			requestedDX: 8,
			requestedDY: 3,
			bounds: bounds
		)

		XCTAssertEqual(movement.point, CGPoint(x: 99, y: 53))
		XCTAssertEqual(movement.dx, 0)
		XCTAssertEqual(movement.dy, 3)
		XCTAssertTrue(movement.shouldPostEvent)
	}

	func testRemoteMouseMovementDropsPureOutwardEdgeMove() {
		let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

		let movement = UniversalControlRemoteMouseMovementPolicy.boundedMovement(
			current: CGPoint(x: 0, y: 50),
			requestedDX: -8,
			requestedDY: 0,
			bounds: bounds
		)

		XCTAssertEqual(movement.point, CGPoint(x: 0, y: 50))
		XCTAssertEqual(movement.dx, 0)
		XCTAssertEqual(movement.dy, 0)
		XCTAssertFalse(movement.shouldPostEvent)
	}

	func testRemoteMouseMovementDoesNotPostWhenCursorAlreadyLeftRemoteBounds() {
		let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

		let movement = UniversalControlRemoteMouseMovementPolicy.boundedMovement(
			current: CGPoint(x: 140, y: 42),
			requestedDX: -8,
			requestedDY: 0,
			bounds: bounds
		)

		XCTAssertEqual(movement.point, CGPoint(x: 99, y: 42))
		XCTAssertEqual(movement.dx, 0)
		XCTAssertEqual(movement.dy, 0)
		XCTAssertFalse(movement.shouldPostEvent)
		XCTAssertEqual(
			UniversalControlRemoteMouseMovementPolicy.statusPoint(
				current: CGPoint(x: 140, y: 42),
				bounds: bounds
			),
			CGPoint(x: 99, y: 42)
		)
	}

	func testRemoteSessionOnlyTimesOutBeforeFirstCursorStatus() {
		XCTAssertTrue(
			UniversalControlRelaySessionPolicy.shouldCancelForMissingInitialCursorStatus(
				sessionActive: true,
				hasReceivedCursorStatus: false,
				elapsedSinceStart: UniversalControlRelaySessionPolicy.confirmationTimeout + 0.1
			)
		)

		XCTAssertFalse(
			UniversalControlRelaySessionPolicy.shouldCancelForMissingInitialCursorStatus(
				sessionActive: true,
				hasReceivedCursorStatus: true,
				elapsedSinceStart: 60
			),
			"Confirmed remote sessions must survive idle periods with stale cursor status."
		)
	}

	func testRemoteSessionSurvivesLongControllerIdleAfterCursorStatus() {
		XCTAssertFalse(
			UniversalControlRelaySessionPolicy.shouldCancelForMissingInitialCursorStatus(
				sessionActive: true,
				hasReceivedCursorStatus: true,
				elapsedSinceStart: UniversalControlRelaySessionPolicy.confirmationTimeout + 600
			)
		)

		XCTAssertFalse(
			UniversalControlRelaySessionPolicy.shouldCancelForMissingInitialCursorStatus(
				sessionActive: false,
				hasReceivedCursorStatus: false,
				elapsedSinceStart: UniversalControlRelaySessionPolicy.confirmationTimeout + 600
			)
		)
	}

	func testRemoteCursorVisibilityRepairRunsAgainAfterReconnectIdleGap() {
		let first = RemoteCursorVisibilityRestorePolicy.decision(
			now: 100,
			lastRestoreAt: nil
		)
		XCTAssertEqual(
			first,
			RemoteCursorVisibilityRestorePolicy.Decision(
				shouldRestore: true,
				shouldRepairPotentialStaleHide: true
			)
		)

		let throttled = RemoteCursorVisibilityRestorePolicy.decision(
			now: 100 + RemoteCursorVisibilityRestorePolicy.restoreThrottleInterval / 2,
			lastRestoreAt: 100
		)
		XCTAssertEqual(
			throttled,
			RemoteCursorVisibilityRestorePolicy.Decision(
				shouldRestore: false,
				shouldRepairPotentialStaleHide: false
			)
		)

		let sameRemoteBurst = RemoteCursorVisibilityRestorePolicy.decision(
			now: 100 + RemoteCursorVisibilityRestorePolicy.restoreThrottleInterval + 0.1,
			lastRestoreAt: 100
		)
		XCTAssertEqual(
			sameRemoteBurst,
			RemoteCursorVisibilityRestorePolicy.Decision(
				shouldRestore: true,
				shouldRepairPotentialStaleHide: false
			)
		)

		let afterReconnectIdle = RemoteCursorVisibilityRestorePolicy.decision(
			now: 100 + RemoteCursorVisibilityRestorePolicy.reconnectIdleRepairInterval + 0.1,
			lastRestoreAt: 100
		)
		XCTAssertEqual(
			afterReconnectIdle,
			RemoteCursorVisibilityRestorePolicy.Decision(
				shouldRestore: true,
				shouldRepairPotentialStaleHide: true
			)
		)
	}
}
