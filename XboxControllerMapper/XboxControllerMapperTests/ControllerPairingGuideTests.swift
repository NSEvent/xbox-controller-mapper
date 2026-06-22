import XCTest
@testable import ControllerKeys

/// Guarantees the "every controller has pairing instructions" contract: every
/// concrete `ControllerPreviewLayout` resolves to a usable pairing guide, so the
/// empty-state can always answer "how do I connect *this*?". Adding a new preview
/// layout without a guide fails here.
final class ControllerPairingGuideTests: XCTestCase {

    func testActiveLayoutHasNoGuide() {
        // `.active` resolves to a real device at runtime; the empty state shows a
        // chooser instead of a single guide.
        XCTAssertNil(ControllerPreviewLayout.active.pairingGuide)
    }

    func testEveryConcreteLayoutHasAGuide() {
        for layout in ControllerPreviewLayout.concreteLayouts {
            XCTAssertNotNil(
                layout.pairingGuide,
                "\(layout.displayName) is missing a pairing guide"
            )
        }
    }

    func testGuidesAreWellFormed() {
        for layout in ControllerPreviewLayout.concreteLayouts {
            guard let guide = layout.pairingGuide else {
                XCTFail("\(layout.displayName) is missing a pairing guide")
                continue
            }

            XCTAssertFalse(
                guide.title.trimmingCharacters(in: .whitespaces).isEmpty,
                "\(layout.displayName) guide has an empty title"
            )
            XCTAssertFalse(
                guide.tagline.trimmingCharacters(in: .whitespaces).isEmpty,
                "\(layout.displayName) guide has an empty tagline"
            )

            // Pairing only reads as instructions with at least two steps.
            XCTAssertGreaterThanOrEqual(
                guide.bluetoothSteps.count, 2,
                "\(layout.displayName) guide needs at least two Bluetooth steps"
            )
            for step in guide.bluetoothSteps {
                XCTAssertFalse(
                    step.trimmingCharacters(in: .whitespaces).isEmpty,
                    "\(layout.displayName) guide has an empty step"
                )
            }
        }
    }

    func testIconMatchesPickerIcon() {
        // The guide header should reuse the picker's icon for the controller so
        // the empty state and the dropdown stay visually consistent.
        for layout in ControllerPreviewLayout.concreteLayouts {
            XCTAssertEqual(
                layout.pairingGuide?.systemImage,
                layout.systemImage,
                "\(layout.displayName) guide icon diverged from its picker icon"
            )
        }
    }

    func testGuideURLsAreSecure() {
        for layout in ControllerPreviewLayout.concreteLayouts {
            guard let url = layout.pairingGuide?.guideURL else { continue }
            XCTAssertEqual(
                url.scheme, "https",
                "\(layout.displayName) guide URL should be https"
            )
        }
    }

    func testMarkdownRendersWithoutLeftoverMarkers() {
        // The view renders steps AND the optional notes (wiredNote/tip/
        // nativeSupportNote) via `Text(inlineMarkdown:)`. AttributedString(markdown:)
        // never *throws* on malformed input — it silently degrades to literal
        // text — so asserting "doesn't throw" would be vacuous. Instead, render
        // each string the way the view does and assert the emphasis markers were
        // actually consumed: a surviving '*' means an unbalanced `**…` span that
        // would show literal asterisks in the card.
        for layout in ControllerPreviewLayout.concreteLayouts {
            guard let guide = layout.pairingGuide else { continue }

            let markdownStrings = guide.bluetoothSteps
                + [guide.wiredNote, guide.tip, guide.nativeSupportNote].compactMap { $0 }
            XCTAssertFalse(
                markdownStrings.isEmpty,
                "\(layout.displayName) guide exposes no markdown strings to validate"
            )

            for source in markdownStrings {
                guard let attributed = try? AttributedString(
                    markdown: source,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                ) else {
                    XCTFail("\(layout.displayName) markdown failed to parse: \(source)")
                    continue
                }
                let rendered = String(attributed.characters)
                XCTAssertFalse(
                    rendered.isEmpty,
                    "\(layout.displayName) markdown rendered empty for: \(source)"
                )
                XCTAssertFalse(
                    rendered.contains("*"),
                    "\(layout.displayName) left a literal '*' after rendering (unbalanced emphasis?): \"\(source)\" -> \"\(rendered)\""
                )
            }
        }
    }
}
