import XCTest
@testable import ControllerKeys

final class ButtonIconViewAlignmentTests: XCTestCase {

    /// Proves that different button types produce different intrinsic widths,
    /// which is the root cause of misaligned bars in the stats view.
    func testButtonIconWidthVariesAcrossCategories() {
        let faceIcon = ButtonIconView(button: .a)
        let triggerIcon = ButtonIconView(button: .leftTrigger)

        // Face buttons are 28pt, triggers are 42pt — they differ
        XCTAssertNotEqual(faceIcon.width, triggerIcon.width,
            "Different button categories should have different intrinsic widths")
    }

    /// Verifies that maxIconWidth is at least as wide as every button's icon,
    /// ensuring a fixed-width column using this value will contain all icons.
    func testMaxIconWidthCoversAllButtons() {
        let maxWidth = ButtonIconView.maxIconWidth

        for button in ControllerButton.allCases {
            let icon = ButtonIconView(button: button)
            XCTAssertGreaterThanOrEqual(maxWidth, icon.width,
                "\(button.rawValue) icon width (\(icon.width)) exceeds maxIconWidth (\(maxWidth))")
        }
    }

    /// Ensures maxIconWidth is a reasonable positive value.
    func testMaxIconWidthIsPositive() {
        XCTAssertGreaterThan(ButtonIconView.maxIconWidth, 0)
    }
}
