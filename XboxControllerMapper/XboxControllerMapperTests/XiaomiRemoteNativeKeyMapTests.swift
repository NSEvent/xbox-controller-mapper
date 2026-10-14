import XCTest
@testable import ControllerKeys

@MainActor
final class XiaomiRemoteNativeKeyMapTests: XCTestCase {
	private let src = XiaomiRemoteNativeKeyMap.sourceKey
	private let dst = XiaomiRemoteNativeKeyMap.destinationKey
	private let undefined: UInt64 = 0x700000000

	func testAllThirteenNativeKeysAreDisabledWithoutChangingOtherRemaps() {
		let unrelated = [src: UInt64(0x700000029), dst: UInt64(0x70000006D)]
		let installed = XiaomiRemoteNativeKeyMap.blockingMap(previous: [unrelated])
		XCTAssertEqual(installed.count, 14)
		XCTAssertTrue(installed.contains(unrelated))
		for usage in XiaomiRemoteReportDecoder.buttonsByUsage.keys {
			XCTAssertTrue(installed.contains([src: UInt64(usage) | undefined, dst: undefined]))
		}
	}

	func testStoppingRestoresExactPriorMappingIncludingExistingRemoteRemaps() {
		let previous = [[src: UInt64(0x700000052), dst: UInt64(0x700000053)],
			[src: UInt64(0x700000029), dst: UInt64(0x70000006D)]]
		let installed = XiaomiRemoteNativeKeyMap.blockingMap(previous: previous)
		XCTAssertEqual(XiaomiRemoteNativeKeyMap.restoredMap(previous: previous, installed: installed, current: installed), previous)
		XCTAssertEqual(XiaomiRemoteNativeKeyMap.blockingMap(previous: installed), installed)
	}

	func testAnotherRemappersChangesDuringTheLeaseArePreserved() {
		let previous = [[src: UInt64(0x700000052), dst: UInt64(0x700000053)]]
		let installed = XiaomiRemoteNativeKeyMap.blockingMap(previous: previous)
		let replacement = [src: UInt64(0x700000052), dst: UInt64(0x700000054)]
		let extra = [src: UInt64(0x700000030), dst: UInt64(0x700000031)]
		let current = installed.filter { $0[src] != replacement[src] } + [replacement, extra]
		let restored = XiaomiRemoteNativeKeyMap.restoredMap(previous: previous, installed: installed, current: current)
		XCTAssertEqual(restored, [replacement, extra])
	}

	func testExistingUnrelatedDisabledKeysAreNotOwnedByOurLease() {
		let unrelated = [src: UInt64(0x700000004), dst: undefined]
		let previous = [unrelated]
		let installed = XiaomiRemoteNativeKeyMap.blockingMap(previous: previous)
		let extra = [src: UInt64(0x700000030), dst: UInt64(0x700000031)]
		let restored = XiaomiRemoteNativeKeyMap.restoredMap(previous: previous, installed: installed, current: installed + [extra])
		XCTAssertEqual(restored, [unrelated, extra])
	}

	func testCrashRecoveryDoesNotAdoptBlockingMapAsUsersOriginal() {
		let original = [[src: UInt64(0x700000028), dst: UInt64(0x70000002A)]]
		let installed = XiaomiRemoteNativeKeyMap.blockingMap(previous: original)
		let recovered = XiaomiRemoteNativeKeyMap.restoredMap(previous: original, installed: installed, current: installed)
		XCTAssertEqual(recovered, original)
		XCTAssertEqual(XiaomiRemoteNativeKeyMap.blockingMap(previous: recovered), installed)
	}
}
