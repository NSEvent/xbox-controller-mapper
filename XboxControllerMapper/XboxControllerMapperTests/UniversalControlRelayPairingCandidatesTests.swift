import XCTest
@testable import ControllerKeys

final class UniversalControlRelayPairingCandidatesTests: XCTestCase {
	private let now = Date(timeIntervalSince1970: 1_000)

	func testCodeSelectsSecondMacRatherThanFirstResponder() throws {
		let initiator = UniversalControlRelayPairingSession(localPeerID: "macbook")
		let studio = UniversalControlRelayPairingSession(localPeerID: "studio")
		let m3 = UniversalControlRelayPairingSession(localPeerID: "m3")
		let studioResult = try result(initiator: initiator, receiver: studio)
		let m3Result = try result(initiator: initiator, receiver: m3)
		var candidates = UniversalControlRelayPairingCandidates<String, String>()
		candidates.start(searchID: "search", now: now)
		XCTAssertEqual(candidates.add(id: "studio", searchID: "search", code: studioResult.code,
									 keyData: studioResult.keyData, value: "studio", now: now), true)
		XCTAssertEqual(candidates.add(id: "m3", searchID: "search", code: m3Result.code,
									 keyData: m3Result.keyData, value: "m3", now: now), false)
		// Real receiver-derived codes/keys must agree with the initiating Mac.
		let receiverResult = try XCTUnwrap(m3.derive(remotePeerID: initiator.localPeerID,
			remotePublicKeyBase64: initiator.localPublicKeyBase64, remoteNonce: initiator.localNonce,
			localIsFirst: false))
		XCTAssertEqual(m3Result.keyData, receiverResult.keyData)
		switch candidates.select(code: receiverResult.code, now: now) {
		case .matched(let value): XCTAssertEqual(value, "m3")
		case .ambiguous: XCTAssertEqual(studioResult.code, m3Result.code) // rare real code collision
		default: XCTFail("The later Mac's displayed code must select its handshake")
		}
	}

	func testAliasesOfOneMacCanShareCode() {
		var candidates = makeCandidates()
		_ = candidates.add(id: "ipv6", searchID: "search", code: "123456",
						   keyData: Data([1]), value: "m3", now: now)
		guard case .matched("m3") = candidates.select(code: "123456", now: now) else {
			return XCTFail("Multiple addresses for the same handshake are valid")
		}
	}

	func testDifferentMacsWithSameCodeRequireRetry() {
		var candidates = makeCandidates()
		_ = candidates.add(id: "other", searchID: "search", code: "123456",
						   keyData: Data([2]), value: "other", now: now)
		guard case .ambiguous = candidates.select(code: "123456", now: now) else {
			return XCTFail("Do not select an arbitrary Mac on a code collision")
		}
	}

	func testWrongCodeLeavesValidCandidateAvailable() {
		let candidates = makeCandidates()
		guard case .wrongCode = candidates.select(code: "654321", now: now),
			  case .matched("m3") = candidates.select(code: "123456", now: now) else {
			return XCTFail("A typo must not discard the waiting handshake")
		}
	}

	func testRestartRejectsOldSearchResponses() {
		var candidates = makeCandidates()
		candidates.start(searchID: "new", now: now)
		XCTAssertNil(candidates.add(id: "late", searchID: "search", code: "123456",
									keyData: Data([1]), value: "old", now: now))
		XCTAssertFalse(candidates.hasCandidates)
	}

	func testExpiryAndResetDiscardCandidates() {
		var candidates = makeCandidates()
		let expired = now.addingTimeInterval(60)
		guard case .notWaiting = candidates.select(code: "123456", now: expired) else {
			return XCTFail("Expired codes must not pair")
		}
		XCTAssertNil(candidates.add(id: "late", searchID: "search", code: "123456",
									keyData: Data([1]), value: "m3", now: expired))
		candidates.reset()
		guard case .notWaiting = candidates.select(code: "123456", now: now) else {
			return XCTFail("Reset must discard all codes")
		}
	}

	func testDisconnectedCandidateIsRemoved() {
		var candidates = makeCandidates()
		candidates.remove(id: "m3")
		XCTAssertFalse(candidates.hasCandidates)
		guard case .notWaiting = candidates.select(code: "123456", now: now) else {
			return XCTFail("A closed handshake must not be selected")
		}
	}

	private func makeCandidates() -> UniversalControlRelayPairingCandidates<String, String> {
		var candidates = UniversalControlRelayPairingCandidates<String, String>()
		candidates.start(searchID: "search", now: now)
		_ = candidates.add(id: "m3", searchID: "search", code: "123456",
						   keyData: Data([1]), value: "m3", now: now)
		return candidates
	}

	private func result(initiator: UniversalControlRelayPairingSession,
						receiver: UniversalControlRelayPairingSession) throws -> UniversalControlRelayPairingSession.PairingResult {
		try XCTUnwrap(initiator.derive(remotePeerID: receiver.localPeerID,
			remotePublicKeyBase64: receiver.localPublicKeyBase64, remoteNonce: receiver.localNonce))
	}
}
