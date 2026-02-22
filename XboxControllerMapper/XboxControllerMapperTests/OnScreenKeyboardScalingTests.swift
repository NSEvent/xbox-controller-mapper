import XCTest
@testable import ControllerKeys

@MainActor
final class OnScreenKeyboardScalingTests: XCTestCase {

    // MARK: - scaleToFit

    func testScaleToFit_keyboardFitsScreen_returnsOne() {
        let keyboard = NSSize(width: 1100, height: 700)
        let screen = NSRect(x: 0, y: 0, width: 2560, height: 1440)

        let scale = OnScreenKeyboardManager.scaleToFit(keyboardSize: keyboard, screenVisibleFrame: screen)

        XCTAssertEqual(scale, 1.0)
    }

    func testScaleToFit_keyboardTooTallFor1080p_scalesDown() {
        // With optional sections (app bar, quick texts, website links) keyboard can be ~1050px tall
        let keyboard = NSSize(width: 1100, height: 1050)
        // 1080p visible frame (minus ~25px menu bar)
        let screen = NSRect(x: 0, y: 0, width: 1920, height: 1055)
        let margin = OnScreenKeyboardManager.screenMargin

        let scale = OnScreenKeyboardManager.scaleToFit(keyboardSize: keyboard, screenVisibleFrame: screen)

        XCTAssertLessThan(scale, 1.0)
        // Scaled height must fit within available area
        let availableHeight = screen.height - margin * 2
        XCTAssertLessThanOrEqual(keyboard.height * scale, availableHeight + 0.001)
    }

    func testScaleToFit_keyboardTooWide_scalesDown() {
        let keyboard = NSSize(width: 1200, height: 400)
        let screen = NSRect(x: 0, y: 0, width: 1024, height: 768)
        let margin = OnScreenKeyboardManager.screenMargin

        let scale = OnScreenKeyboardManager.scaleToFit(keyboardSize: keyboard, screenVisibleFrame: screen)

        XCTAssertLessThan(scale, 1.0)
        let availableWidth = screen.width - margin * 2
        XCTAssertLessThanOrEqual(keyboard.width * scale, availableWidth + 0.001)
    }

    func testScaleToFit_keyboardTooTallAndTooWide_usesSmallestScale() {
        let keyboard = NSSize(width: 1200, height: 800)
        let screen = NSRect(x: 0, y: 0, width: 1024, height: 768)
        let margin = OnScreenKeyboardManager.screenMargin

        let scale = OnScreenKeyboardManager.scaleToFit(keyboardSize: keyboard, screenVisibleFrame: screen)

        // Both dimensions must fit
        let availableWidth = screen.width - margin * 2
        let availableHeight = screen.height - margin * 2
        XCTAssertLessThanOrEqual(keyboard.width * scale, availableWidth + 0.001)
        XCTAssertLessThanOrEqual(keyboard.height * scale, availableHeight + 0.001)
    }

    func testScaleToFit_keyboardJustFitsWithMargins_returnsOne() {
        let margin = OnScreenKeyboardManager.screenMargin
        // Keyboard exactly fills available area
        let keyboard = NSSize(width: 960, height: 728)
        let screen = NSRect(x: 0, y: 0, width: 960 + margin * 2, height: 728 + margin * 2)

        let scale = OnScreenKeyboardManager.scaleToFit(keyboardSize: keyboard, screenVisibleFrame: screen)

        XCTAssertEqual(scale, 1.0)
    }

    func testScaleToFit_keyboardOnePixelOverHeight_scalesDown() {
        let margin = OnScreenKeyboardManager.screenMargin
        let availableHeight = 728.0
        let keyboard = NSSize(width: 500, height: availableHeight + 1)
        let screen = NSRect(x: 0, y: 0, width: 1920, height: availableHeight + margin * 2)

        let scale = OnScreenKeyboardManager.scaleToFit(keyboardSize: keyboard, screenVisibleFrame: screen)

        XCTAssertLessThan(scale, 1.0)
    }

    func testScaleToFit_zeroScreenFrame_returnsOne() {
        let keyboard = NSSize(width: 1100, height: 700)

        let scale = OnScreenKeyboardManager.scaleToFit(keyboardSize: keyboard, screenVisibleFrame: .zero)

        XCTAssertEqual(scale, 1.0, "Should not crash or produce invalid scale for zero screen")
    }

    func testScaleToFit_verySmallScreen_producesValidScale() {
        let keyboard = NSSize(width: 1100, height: 700)
        let screen = NSRect(x: 0, y: 0, width: 640, height: 480)

        let scale = OnScreenKeyboardManager.scaleToFit(keyboardSize: keyboard, screenVisibleFrame: screen)

        XCTAssertGreaterThan(scale, 0)
        XCTAssertLessThan(scale, 1.0)
    }

    func testScaleToFit_4kScreen_returnsOne() {
        let keyboard = NSSize(width: 1100, height: 750)
        // 4K at 2x scaling = 1920x1080 in points, but visible frame similar
        let screen = NSRect(x: 0, y: 0, width: 2560, height: 1415)

        let scale = OnScreenKeyboardManager.scaleToFit(keyboardSize: keyboard, screenVisibleFrame: screen)

        XCTAssertEqual(scale, 1.0)
    }

    func testScaleToFit_preservesAspectRatio() {
        let keyboard = NSSize(width: 1100, height: 700)
        let screen = NSRect(x: 0, y: 0, width: 800, height: 500)

        let scale = OnScreenKeyboardManager.scaleToFit(keyboardSize: keyboard, screenVisibleFrame: screen)

        // Both dimensions use the same scale factor (uniform scaling)
        let scaledWidth = keyboard.width * scale
        let scaledHeight = keyboard.height * scale
        let ratioAfter = scaledWidth / scaledHeight
        let ratioBefore = keyboard.width / keyboard.height
        XCTAssertEqual(ratioAfter, ratioBefore, accuracy: 0.001)
    }

    // MARK: - panelOrigin

    func testPanelOrigin_unscaled_centeredWith100Offset() {
        let panelSize = NSSize(width: 1100, height: 700)
        let screen = NSRect(x: 0, y: 25, width: 2560, height: 1415)

        let origin = OnScreenKeyboardManager.panelOrigin(panelSize: panelSize, screenVisibleFrame: screen, scaled: false)

        XCTAssertEqual(origin.x, screen.midX - panelSize.width / 2)
        XCTAssertEqual(origin.y, screen.minY + 100)
    }

    func testPanelOrigin_scaled_centeredWithMarginOffset() {
        let panelSize = NSSize(width: 900, height: 600)
        let screen = NSRect(x: 0, y: 25, width: 1920, height: 1055)
        let margin = OnScreenKeyboardManager.screenMargin

        let origin = OnScreenKeyboardManager.panelOrigin(panelSize: panelSize, screenVisibleFrame: screen, scaled: true)

        XCTAssertEqual(origin.x, screen.midX - panelSize.width / 2)
        XCTAssertEqual(origin.y, screen.minY + margin)
    }

    func testPanelOrigin_scaled_panelFitsWithinScreen() {
        // Use a keyboard tall enough to trigger scaling on this screen
        let keyboard = NSSize(width: 1100, height: 1050)
        let screen = NSRect(x: 0, y: 25, width: 1920, height: 1055)

        let scale = OnScreenKeyboardManager.scaleToFit(keyboardSize: keyboard, screenVisibleFrame: screen)
        let panelSize = NSSize(width: keyboard.width * scale, height: keyboard.height * scale)
        let origin = OnScreenKeyboardManager.panelOrigin(panelSize: panelSize, screenVisibleFrame: screen, scaled: scale < 1.0)

        // Panel bottom must be within screen
        XCTAssertGreaterThanOrEqual(origin.y, screen.minY)
        // Panel top must be within screen
        let panelTop = origin.y + panelSize.height
        XCTAssertLessThanOrEqual(panelTop, screen.maxY)
    }

    func testPanelOrigin_secondaryScreenWithOffset_respectsScreenOrigin() {
        // Secondary screen positioned to the right with different origin
        let panelSize = NSSize(width: 900, height: 600)
        let screen = NSRect(x: 1920, y: 0, width: 1920, height: 1055)

        let origin = OnScreenKeyboardManager.panelOrigin(panelSize: panelSize, screenVisibleFrame: screen, scaled: false)

        // x should be centered on the secondary screen, not the primary
        XCTAssertGreaterThan(origin.x, screen.minX)
        XCTAssertLessThan(origin.x + panelSize.width, screen.maxX)
    }

    // MARK: - Integration: scale + position together

    func testIntegration_1080pScreen_keyboardFitsCompletely() {
        let keyboard = NSSize(width: 1100, height: 1050)
        let screen = NSRect(x: 0, y: 25, width: 1920, height: 1055)

        let scale = OnScreenKeyboardManager.scaleToFit(keyboardSize: keyboard, screenVisibleFrame: screen)
        let panelSize = NSSize(width: keyboard.width * scale, height: keyboard.height * scale)
        let origin = OnScreenKeyboardManager.panelOrigin(panelSize: panelSize, screenVisibleFrame: screen, scaled: scale < 1.0)

        let panelRect = NSRect(origin: origin, size: panelSize)

        // Entire panel must be within the screen's visible frame
        XCTAssertTrue(screen.contains(panelRect),
                      "Panel \(panelRect) must fit within screen \(screen)")
    }

    func testIntegration_768pScreen_keyboardFitsCompletely() {
        let keyboard = NSSize(width: 1100, height: 750)
        let screen = NSRect(x: 0, y: 0, width: 1366, height: 743)

        let scale = OnScreenKeyboardManager.scaleToFit(keyboardSize: keyboard, screenVisibleFrame: screen)
        let panelSize = NSSize(width: keyboard.width * scale, height: keyboard.height * scale)
        let origin = OnScreenKeyboardManager.panelOrigin(panelSize: panelSize, screenVisibleFrame: screen, scaled: scale < 1.0)

        let panelRect = NSRect(origin: origin, size: panelSize)

        XCTAssertTrue(screen.contains(panelRect),
                      "Panel \(panelRect) must fit within screen \(screen)")
    }

    func testIntegration_retinaScreen_noScaling() {
        let keyboard = NSSize(width: 1100, height: 750)
        // MacBook Pro 14" Retina visible frame in points
        let screen = NSRect(x: 0, y: 25, width: 1512, height: 957)

        let scale = OnScreenKeyboardManager.scaleToFit(keyboardSize: keyboard, screenVisibleFrame: screen)

        XCTAssertEqual(scale, 1.0, "Retina MacBook should not need scaling")
    }
}
