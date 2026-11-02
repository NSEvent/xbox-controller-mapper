import XCTest
@testable import ControllerKeys

final class LemonSqueezyLicenseVerifierTests: XCTestCase {
	private let product = LemonSqueezyLicenseVerifier.Product(storeID: 101, productID: 202, variantID: 303)
	private let key = "00000000-1111-2222-3333-444444444444"
	private let endpoint = URL(string: "https://api.lemonsqueezy.com/v1/licenses/validate")!

	private func payload(status: String = "active", expiry: Any = NSNull(),
						 store: Int = 101, product: Int = 202, variant: Int = 303) -> [String: Any] {
		["valid": true, "error": NSNull(),
		 "license_key": ["key": key, "status": status, "expires_at": expiry],
		 "meta": ["store_id": store, "product_id": product, "variant_id": variant]]
	}

	private func verify(_ json: [String: Any], status: Int = 200,
						url: URL? = nil) async -> Result<Void, LemonSqueezyLicenseVerifier.Failure> {
		let data = try! JSONSerialization.data(withJSONObject: json)
		let response = HTTPURLResponse(url: url ?? endpoint, statusCode: status, httpVersion: nil, headerFields: nil)!
		let verifier = LemonSqueezyLicenseVerifier(product: product, transport: { _ in (data, response) },
												  now: { Date(timeIntervalSince1970: 1_800_000_000) })
		return await verifier.verify(key: key)
	}

	private func assertFailure(_ result: Result<Void, LemonSqueezyLicenseVerifier.Failure>,
							   _ expected: LemonSqueezyLicenseVerifier.Failure,
							   file: StaticString = #filePath, line: UInt = #line) {
		switch result {
		case .success: XCTFail("Unexpected license acceptance", file: file, line: line)
		case .failure(let actual): XCTAssertEqual(actual, expected, file: file, line: line)
		}
	}

	func testAcceptsMatchingLifetimeLicenseWithOrWithoutExistingActivations() async throws {
		for status in ["active", "inactive"] {
			let result = await verify(payload(status: status))
			try result.get()
		}
	}

	func testRejectsOtherSellerProductAndVariantIncludingTestProduct() async {
		assertFailure(await verify(payload(store: 999)), .wrongProduct)
		assertFailure(await verify(payload(product: 999)), .wrongProduct)
		assertFailure(await verify(payload(variant: 999)), .wrongProduct)
	}

	func testRejectsRevokedExpiredAndUnknownStatusesEvenIfValidIsTrue() async {
		for status in ["disabled", "expired", "unknown", ""] {
			assertFailure(await verify(payload(status: status)), .revoked)
		}
	}

	func testChecksExpiryInBothDocumentedTimestampPrecisions() async throws {
		for date in ["2020-01-01T00:00:00Z", "2020-01-01T00:00:00.000Z"] {
			assertFailure(await verify(payload(expiry: date)), .revoked)
		}
		for date in ["2099-01-01T00:00:00Z", "2099-01-01T00:00:00.000Z"] {
			try await verify(payload(expiry: date)).get()
		}
		assertFailure(await verify(payload(expiry: "invalid")), .malformedResponse)
	}

	func testRejectsUnboundOrContradictorySuccess() async {
		assertFailure(await verify(["valid": true]), .malformedResponse)
		var json = payload()
		json["error"] = "not valid"
		assertFailure(await verify(json), .malformedResponse)
		json = payload()
		json["license_key"] = ["key": "another-key", "status": "active"]
		assertFailure(await verify(json), .invalidKey)
		json = payload()
		json["valid"] = false
		assertFailure(await verify(json), .invalidKey)
		json = payload()
		json["meta"] = ["store_id": true, "product_id": 202, "variant_id": 303]
		assertFailure(await verify(json), .malformedResponse)
	}

	func testHTTPFailuresAndUnexpectedResponseURLsCannotActivate() async {
		for status in [400, 404, 422, 302] {
			assertFailure(await verify(payload(), status: status), .invalidKey)
		}
		for status in [429, 500, 503] {
			assertFailure(await verify(payload(), status: status), .server)
		}
		assertFailure(await verify(payload(), url: URL(string: "https://example.com")), .malformedResponse)
	}

	func testEmptyKeyAndUnconfiguredProductNeverContactProvider() async {
		let transport: LemonSqueezyLicenseVerifier.Transport = { _ in
			XCTFail("Must not contact a provider without a configured product and nonempty key")
			throw URLError(.cancelled)
		}
		let verifier = LemonSqueezyLicenseVerifier(product: product, transport: transport)
		assertFailure(await verifier.verify(key: " \n"), .emptyKey)
		let unconfigured = LemonSqueezyLicenseVerifier(
			product: .init(storeID: 0, productID: 202, variantID: 303), transport: transport)
		assertFailure(await unconfigured.verify(key: key), .notConfigured)
	}

	func testRequestOnlyContainsEncodedKeyWithoutCustomerDataOrAPISecrets() async {
		let verifier = LemonSqueezyLicenseVerifier(product: product, transport: { request in
			XCTAssertEqual(request.url?.absoluteString, "https://api.lemonsqueezy.com/v1/licenses/validate")
			XCTAssertEqual(request.httpMethod, "POST")
			XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
			XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
			XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
			XCTAssertEqual(String(data: request.httpBody!, encoding: .utf8), "license_key=a%2Bb%26c%3Dd")
			XCTAssertEqual(request.timeoutInterval, 20)
			throw URLError(.timedOut)
		})
		assertFailure(await verifier.verify(key: " a+b&c=d\n"), .network)
	}

	func testRejectsMalformedAndOversizedPayloads() async {
		let response = HTTPURLResponse(url: endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!
		for data in [Data("not json".utf8), Data(repeating: 32, count: 65_537)] {
			let verifier = LemonSqueezyLicenseVerifier(product: product, transport: { _ in (data, response) })
			assertFailure(await verifier.verify(key: key), .malformedResponse)
		}
	}
}
