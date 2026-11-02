import Foundation

/// Validates the unlimited-Mac, one-time license without creating device instances.
/// Store/product/variant binding is mandatory: a valid key for another seller (or
/// our test-mode product) must never unlock ControllerKeys.
struct LemonSqueezyLicenseVerifier {
	struct Product: Equatable {
		let storeID: Int
		let productID: Int
		let variantID: Int

		var isValid: Bool { storeID > 0 && productID > 0 && variantID > 0 }
	}

	enum Failure: Error, Equatable {
		case notConfigured, emptyKey, invalidKey, revoked, wrongProduct
		case malformedResponse, network, server
	}

	typealias Transport = (URLRequest) async throws -> (Data, URLResponse)

	private let product: Product
	private let transport: Transport
	private let now: () -> Date
	private static let endpoint = URL(string: "https://api.lemonsqueezy.com/v1/licenses/validate")!

	init(product: Product, transport: @escaping Transport = Self.send, now: @escaping () -> Date = Date.init) {
		self.product = product
		self.transport = transport
		self.now = now
	}

	func verify(key rawKey: String) async -> Result<Void, Failure> {
		guard product.isValid else { return .failure(.notConfigured) }
		let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !key.isEmpty else { return .failure(.emptyKey) }
		var request = URLRequest(url: Self.endpoint)
		request.httpMethod = "POST"
		request.timeoutInterval = 20
		request.setValue("application/json", forHTTPHeaderField: "Accept")
		request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
		let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
		guard let escaped = key.addingPercentEncoding(withAllowedCharacters: unreserved) else {
			return .failure(.invalidKey)
		}
		request.httpBody = Data("license_key=\(escaped)".utf8)

		do {
			let (data, response) = try await transport(request)
			guard let http = response as? HTTPURLResponse,
				  http.url == Self.endpoint else { return .failure(.malformedResponse) }
			guard http.statusCode == 200 else {
				return .failure(http.statusCode >= 500 || http.statusCode == 429 ? .server : .invalidKey)
			}
			guard data.count <= 65_536,
				  let payload = try? JSONDecoder().decode(Response.self, from: data) else {
				return .failure(.malformedResponse)
			}
			guard payload.valid else { return .failure(.invalidKey) }
			guard payload.error == nil, let license = payload.licenseKey, let meta = payload.meta else {
				return .failure(.malformedResponse)
			}
			guard meta.storeID == product.storeID, meta.productID == product.productID,
				  meta.variantID == product.variantID else { return .failure(.wrongProduct) }
			guard license.key.caseInsensitiveCompare(key) == .orderedSame else { return .failure(.invalidKey) }
			guard license.status == "active" || license.status == "inactive" else { return .failure(.revoked) }
			if let expiry = license.expiresAt {
				let formatter = ISO8601DateFormatter()
				formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
				var date = formatter.date(from: expiry)
				if date == nil {
					formatter.formatOptions = [.withInternetDateTime]
					date = formatter.date(from: expiry)
				}
				guard let date else { return .failure(.malformedResponse) }
				guard date > now() else { return .failure(.revoked) }
			}
			return .success(())
		} catch {
			return .failure(.network)
		}
	}

	private struct Response: Decodable {
		let valid: Bool
		let error: String?
		let licenseKey: License?
		let meta: Metadata?
		enum CodingKeys: String, CodingKey {
			case valid, error, meta
			case licenseKey = "license_key"
		}
	}

	private struct License: Decodable {
		let key: String
		let status: String
		let expiresAt: String?
		enum CodingKeys: String, CodingKey {
			case key, status
			case expiresAt = "expires_at"
		}
	}

	private struct Metadata: Decodable {
		let storeID: Int
		let productID: Int
		let variantID: Int
		enum CodingKeys: String, CodingKey {
			case storeID = "store_id"
			case productID = "product_id"
			case variantID = "variant_id"
		}
	}

	/// An API redirect must never forward a customer's license to another host.
	static func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.httpShouldSetCookies = false
		configuration.urlCache = nil
		configuration.timeoutIntervalForResource = 30
		let session = URLSession(configuration: configuration, delegate: NoLicenseRedirects(), delegateQueue: nil)
		defer { session.finishTasksAndInvalidate() }
		return try await session.data(for: request)
	}
}

private final class NoLicenseRedirects: NSObject, URLSessionTaskDelegate {
	func urlSession(_ session: URLSession, task: URLSessionTask,
					willPerformHTTPRedirection response: HTTPURLResponse,
					newRequest request: URLRequest,
					completionHandler: @escaping (URLRequest?) -> Void) {
		completionHandler(nil)
	}
}
