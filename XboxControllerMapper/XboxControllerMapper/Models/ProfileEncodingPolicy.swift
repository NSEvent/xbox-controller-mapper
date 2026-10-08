import Foundation

extension CodingUserInfoKey {
	/// Community exports must not persist secrets or touch Keychain during review.
	static let omitPrivateCredentials = CodingUserInfoKey(rawValue: "controllerkeys.omitPrivateCredentials")!
}
