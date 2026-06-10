import XCTest
import Combine
import CoreGraphics
import Carbon.HIToolbox
import SwiftUI
import AppKit
@testable import ControllerKeys

// MARK: - ActionFeedbackView Tests

final class ActionFeedbackViewTests: XCTestCase {

    /// Tests that ActionFeedbackView sizes correctly for short text
    @MainActor
    func testActionFeedbackViewShortText() {
        let view = ActionFeedbackView(action: "A", type: .singlePress)
        let hostingView = NSHostingView(rootView: view)
        let size = hostingView.fittingSize

        XCTAssertGreaterThan(size.width, 0, "View should have positive width")
        XCTAssertGreaterThan(size.height, 0, "View should have positive height")
    }

    /// Tests that ActionFeedbackView expands to fit long text without truncation
    @MainActor
    func testActionFeedbackViewLongTextNotTruncated() {
        let shortView = ActionFeedbackView(action: "A", type: .singlePress)
        let shortHosting = NSHostingView(rootView: shortView)
        let shortSize = shortHosting.fittingSize

        let longText = "This is a very long action hint that should not be truncated"
        let longView = ActionFeedbackView(action: longText, type: .singlePress)
        let longHosting = NSHostingView(rootView: longView)
        let longSize = longHosting.fittingSize

        // Long text should result in wider view
        XCTAssertGreaterThan(longSize.width, shortSize.width,
            "Long text view should be wider than short text view")

        // Width should be proportional to text length (roughly)
        // Long text is ~60 chars, short is 1 char, so width should be significantly larger
        XCTAssertGreaterThan(longSize.width, shortSize.width * 2,
            "Long text view should be significantly wider")
    }

    /// Tests that ActionFeedbackView includes badge width for special types
    @MainActor
    func testActionFeedbackViewWithBadge() {
        let noBadgeView = ActionFeedbackView(action: "Test", type: .singlePress)
        let noBadgeHosting = NSHostingView(rootView: noBadgeView)
        let noBadgeSize = noBadgeHosting.fittingSize

        let badgeView = ActionFeedbackView(action: "Test", type: .doubleTap)
        let badgeHosting = NSHostingView(rootView: badgeView)
        let badgeSize = badgeHosting.fittingSize

        // View with badge should be wider
        XCTAssertGreaterThan(badgeSize.width, noBadgeSize.width,
            "View with badge should be wider than view without badge")
    }

    /// Tests that ActionFeedbackView includes held indicator width
    @MainActor
    func testActionFeedbackViewWithHeldIndicator() {
        let notHeldView = ActionFeedbackView(action: "Test", type: .singlePress, isHeld: false)
        let notHeldHosting = NSHostingView(rootView: notHeldView)
        let notHeldSize = notHeldHosting.fittingSize

        let heldView = ActionFeedbackView(action: "Test", type: .singlePress, isHeld: true)
        let heldHosting = NSHostingView(rootView: heldView)
        let heldSize = heldHosting.fittingSize

        // View with held indicator should be wider
        XCTAssertGreaterThan(heldSize.width, notHeldSize.width,
            "View with held indicator should be wider")
    }

    /// Tests that ActionFeedbackView handles emoji and special characters
    @MainActor
    func testActionFeedbackViewWithEmoji() {
        let emojiText = "🎮 Game Mode 🕹️"
        let view = ActionFeedbackView(action: emojiText, type: .singlePress)
        let hostingView = NSHostingView(rootView: view)
        let size = hostingView.fittingSize

        XCTAssertGreaterThan(size.width, 50, "Emoji text should result in reasonable width")
        XCTAssertGreaterThan(size.height, 0, "View should have positive height")
    }

    /// Tests that view width scales with content, not fixed at 200px
    @MainActor
    func testActionFeedbackViewNotFixedWidth() {
        let veryLongText = String(repeating: "A", count: 50)
        let view = ActionFeedbackView(action: veryLongText, type: .doubleTap, isHeld: true)
        let hostingView = NSHostingView(rootView: view)
        let size = hostingView.fittingSize

        // Should be wider than the old fixed 200px limit
        XCTAssertGreaterThan(size.width, 200,
            "View with long text should exceed old 200px fixed width")
    }

    // MARK: - Multiple Held Modifier Tests

    /// Tests that combined modifier text displays wider than single modifier
    @MainActor
    func testActionFeedbackViewCombinedModifiers() {
        let singleModifier = ActionFeedbackView(action: "⌘", type: .singlePress, isHeld: true)
        let singleHosting = NSHostingView(rootView: singleModifier)
        let singleSize = singleHosting.fittingSize

        let combinedModifiers = ActionFeedbackView(action: "⌘ + ⇧", type: .singlePress, isHeld: true)
        let combinedHosting = NSHostingView(rootView: combinedModifiers)
        let combinedSize = combinedHosting.fittingSize

        // Combined modifiers text should be wider
        XCTAssertGreaterThan(combinedSize.width, singleSize.width,
            "Combined modifier view should be wider than single modifier")
    }

    /// Tests that three combined modifiers display even wider
    @MainActor
    func testActionFeedbackViewThreeModifiers() {
        let twoModifiers = ActionFeedbackView(action: "⌘ + ⇧", type: .singlePress, isHeld: true)
        let twoHosting = NSHostingView(rootView: twoModifiers)
        let twoSize = twoHosting.fittingSize

        let threeModifiers = ActionFeedbackView(action: "⌃ + ⌘ + ⇧", type: .singlePress, isHeld: true)
        let threeHosting = NSHostingView(rootView: threeModifiers)
        let threeSize = threeHosting.fittingSize

        // Three modifiers should be wider than two
        XCTAssertGreaterThan(threeSize.width, twoSize.width,
            "Three modifier view should be wider than two modifier view")
    }
}
