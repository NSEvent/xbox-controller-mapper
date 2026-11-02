import Foundation

enum LicenseProvider: String, CaseIterable, Identifiable {
	case gumroad = "Gumroad"
	case lemonSqueezy = "Lemon Squeezy"
	var id: String { rawValue }
}

enum LicenseDistribution {
	// Enable only after the LIVE product has been created and verified. Test-mode
	// IDs belong in test fixtures, never in a distributed app. These IDs are public
	// product identifiers, not API credentials. See docs/internal/lemon-squeezy.md.
	static let lemonSqueezyProduct: LemonSqueezyLicenseVerifier.Product? = nil
	static let lemonSqueezyCheckoutURL: URL? = nil

	static var supportsLemonSqueezy: Bool {
		lemonSqueezyProduct?.isValid == true
	}
}
