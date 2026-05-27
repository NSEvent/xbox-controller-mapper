import XCTest
@testable import ControllerKeys

final class ControllerIdentityResolverTests: XCTestCase {
    func testResolvedIdentityKeepsStableIdForOnePhysicalController() {
        let identity = makeIdentity(stableId: "serial:alpha")

        let resolved = ControllerIdentityResolver.resolvedIdentity(
            candidates: [identity],
            fallbackName: "DualSense"
        )

        XCTAssertEqual(resolved.stableId, "serial:alpha")
        XCTAssertEqual(resolved.fallbackId, identity.fallbackId)
    }

    func testResolvedIdentityDeduplicatesDuplicateInterfacesWithSameStableId() {
        let identity = makeIdentity(stableId: "serial:alpha")
        let duplicateInterface = makeIdentity(
            stableId: "serial:alpha",
            productName: "Wireless Controller"
        )

        let resolved = ControllerIdentityResolver.resolvedIdentity(
            candidates: [identity, duplicateInterface],
            fallbackName: "DualSense"
        )

        XCTAssertEqual(resolved.stableId, "serial:alpha")
    }

    func testResolvedIdentityDropsStableIdForAmbiguousSameModelControllers() {
        let first = makeIdentity(stableId: "serial:alpha")
        let second = makeIdentity(stableId: "serial:beta")

        let resolved = ControllerIdentityResolver.resolvedIdentity(
            candidates: [first, second],
            fallbackName: "DualSense"
        )

        XCTAssertNil(resolved.stableId)
        XCTAssertNil(resolved.serialNumber)
        XCTAssertEqual(resolved.fallbackId, first.fallbackId)
    }

    func testFallbackOnlyDuplicateCandidatesAreNotTreatedAsOnePhysicalController() {
        let first = makeIdentity(stableId: nil)
        let second = makeIdentity(stableId: nil)

        XCTAssertFalse(ControllerIdentityResolver.hasSinglePhysicalIdentity([first, second]))
        XCTAssertTrue(ControllerIdentityResolver.hasSinglePhysicalIdentity([first]))
    }

    func testDevicesForSinglePhysicalIdentityKeepsDuplicateInterfacesForSameStableController() {
        let firstInterface = makeIdentity(stableId: "serial:alpha")
        let secondInterface = makeIdentity(stableId: "serial:alpha")

        let devices = ControllerIdentityResolver.devicesForSinglePhysicalIdentity(
            devices: ["input", "output"],
            identities: [firstInterface, secondInterface]
        )

        XCTAssertEqual(devices, ["input", "output"])
    }

    func testDevicesForSinglePhysicalIdentityDropsAmbiguousSameModelControllers() {
        let firstController = makeIdentity(stableId: "serial:alpha")
        let secondController = makeIdentity(stableId: "serial:beta")

        let devices = ControllerIdentityResolver.devicesForSinglePhysicalIdentity(
            devices: ["alpha", "beta"],
            identities: [firstController, secondController]
        )

        XCTAssertTrue(devices.isEmpty)
    }

    func testDevicesForSinglePhysicalIdentityDropsFallbackOnlyDuplicateControllers() {
        let firstController = makeIdentity(stableId: nil)
        let secondController = makeIdentity(stableId: nil)

        let devices = ControllerIdentityResolver.devicesForSinglePhysicalIdentity(
            devices: ["first", "second"],
            identities: [firstController, secondController]
        )

        XCTAssertTrue(devices.isEmpty)
    }

    func testCandidatesMatchingProductIdsKeepsOnlyActiveControllerModel() {
        let dualShock = makeIdentity(
            stableId: "serial:ds4",
            fallbackId: "hid:054c:09cc:dualshock-4:bluetooth",
            productId: 0x09cc,
            productName: "DUALSHOCK 4 Wireless Controller"
        )
        let dualSense = makeIdentity(
            stableId: "serial:ds5",
            fallbackId: "hid:054c:0ce6:dualsense:bluetooth",
            productId: 0x0ce6,
            productName: "DualSense Wireless Controller"
        )

        let candidates = ControllerIdentityResolver.candidatesMatchingProductIds(
            devices: ["ds4", "ds5"],
            identities: [dualShock, dualSense],
            productIds: [0x0ce6, 0x0df2]
        )

        XCTAssertEqual(candidates.devices, ["ds5"])
        XCTAssertEqual(candidates.identities, [dualSense])
    }

    func testCandidatesMatchingProductIdsDropsMismatchedDeviceIdentityPairs() {
        let identity = makeIdentity(stableId: "serial:alpha")

        let candidates = ControllerIdentityResolver.candidatesMatchingProductIds(
            devices: ["only-device", "extra-device"],
            identities: [identity],
            productIds: [0x0ce6]
        )

        XCTAssertTrue(candidates.devices.isEmpty)
        XCTAssertTrue(candidates.identities.isEmpty)
    }

    func testResolvedIdentityUsesGenericFallbackForDifferentAmbiguousModels() {
        let dualSense = makeIdentity(
            stableId: "serial:alpha",
            fallbackId: "hid:054c:0ce6:dualsense:bluetooth"
        )
        let dualShock = makeIdentity(
            stableId: "serial:beta",
            fallbackId: "hid:054c:09cc:dualshock-4:bluetooth",
            productId: 0x09cc,
            productName: "DUALSHOCK 4"
        )

        let resolved = ControllerIdentityResolver.resolvedIdentity(
            candidates: [dualSense, dualShock],
            fallbackName: "Wireless Controller"
        )

        XCTAssertNil(resolved.stableId)
        XCTAssertEqual(resolved.fallbackId, "hid:unknown:unknown:wireless-controller:unknown")
    }

    private func makeIdentity(
        stableId: String?,
        fallbackId: String = "hid:054c:0ce6:dualsense:bluetooth",
        productId: Int = 0x0ce6,
        productName: String = "DualSense"
    ) -> ControllerIdentity {
        ControllerIdentity(
            stableId: stableId,
            fallbackId: fallbackId,
            vendorId: 0x054c,
            productId: productId,
            productName: productName,
            transport: "Bluetooth",
            serialNumber: stableId?.replacingOccurrences(of: "serial:", with: ""),
            deviceAddress: nil
        )
    }
}
