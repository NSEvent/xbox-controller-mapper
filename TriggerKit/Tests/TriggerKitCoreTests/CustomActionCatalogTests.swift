import XCTest
@testable import TriggerKitCore

final class CustomActionCatalogTests: XCTestCase {
	func testDefaultPayloadEncodesOptionDefaults() {
		let descriptor = CustomActionDescriptor(
			namespace: "test.action",
			title: "Test Action",
			options: [
				.toggle(key: "shuffle", label: "Shuffle", default: true),
				.toggle(key: "activate", label: "Activate", default: false)
			]
		)
		XCTAssertEqual(descriptor.defaultPayload, "{\"activate\":false,\"shuffle\":true}")
	}

	func testDefaultPayloadEncodesMixedToggleAndText() {
		let descriptor = CustomActionDescriptor(
			namespace: "test.mixed",
			title: "Mixed",
			options: [
				.toggle(key: "shuffle", label: "Shuffle", default: true),
				.text(key: "playlist", label: "Playlist", default: "LOW END", placeholder: "Playlist name")
			]
		)
		XCTAssertEqual(descriptor.defaultPayload, "{\"playlist\":\"LOW END\",\"shuffle\":true}")
		XCTAssertEqual(CustomActionPayload.string("playlist", in: descriptor.defaultPayload, default: ""), "LOW END")
		XCTAssertTrue(CustomActionPayload.bool("shuffle", in: descriptor.defaultPayload, default: false))
	}

	func testMakeStepCarriesNamespaceTitleAndDefaults() {
		let descriptor = CustomActionDescriptor(
			namespace: "test.action",
			title: "Test Action",
			options: [.toggle(key: "shuffle", label: "Shuffle", default: true)]
		)
		let step = descriptor.makeStep()
		XCTAssertEqual(step.namespace, "test.action")
		XCTAssertEqual(step.displayName, "Test Action")
		XCTAssertTrue(CustomActionPayload.bool("shuffle", in: step.payload, default: false))
	}

	func testStringPayloadRoundTripAndFallback() {
		var payload = "{}"
		XCTAssertEqual(CustomActionPayload.string("playlist", in: payload, default: "All"), "All")
		payload = CustomActionPayload.setting("Bass & Groove", for: "playlist", in: payload)
		XCTAssertEqual(CustomActionPayload.string("playlist", in: payload, default: ""), "Bass & Groove")
		// a bool and a string coexist in the same payload
		payload = CustomActionPayload.setting(true, for: "shuffle", in: payload)
		XCTAssertTrue(CustomActionPayload.bool("shuffle", in: payload, default: false))
		XCTAssertEqual(CustomActionPayload.string("playlist", in: payload, default: ""), "Bass & Groove")
	}

	func testPayloadRoundTripAndFallback() {
		var payload = "{}"
		XCTAssertTrue(CustomActionPayload.bool("shuffle", in: payload, default: true))
		XCTAssertFalse(CustomActionPayload.bool("shuffle", in: payload, default: false))

		payload = CustomActionPayload.setting(false, for: "shuffle", in: payload)
		XCTAssertFalse(CustomActionPayload.bool("shuffle", in: payload, default: true))

		payload = CustomActionPayload.setting(true, for: "shuffle", in: payload)
		XCTAssertTrue(CustomActionPayload.bool("shuffle", in: payload, default: false))
	}

	func testSettingPreservesOtherKeys() {
		var payload = CustomActionPayload.encode(["a": true, "b": false])
		payload = CustomActionPayload.setting(true, for: "b", in: payload)
		XCTAssertTrue(CustomActionPayload.bool("a", in: payload, default: false))
		XCTAssertTrue(CustomActionPayload.bool("b", in: payload, default: false))
	}

	func testMalformedPayloadFallsBackToDefault() {
		let garbage = "not json"
		XCTAssertTrue(CustomActionPayload.bool("shuffle", in: garbage, default: true))
		// setting on garbage starts a fresh object rather than corrupting further
		let repaired = CustomActionPayload.setting(true, for: "shuffle", in: garbage)
		XCTAssertTrue(CustomActionPayload.bool("shuffle", in: repaired, default: false))
	}

	@MainActor
	func testRegistryRegistersAndReplacesByNamespace() {
		let registry = CustomActionRegistry.shared
		let before = registry.descriptors.count
		registry.register(CustomActionDescriptor(namespace: "test.dup", title: "First"))
		registry.register(CustomActionDescriptor(namespace: "test.dup", title: "Second"))
		XCTAssertEqual(registry.descriptor(for: "test.dup")?.title, "Second")
		XCTAssertEqual(registry.descriptors.filter { $0.namespace == "test.dup" }.count, 1)
		XCTAssertGreaterThan(registry.descriptors.count, before - 1)
	}
}
