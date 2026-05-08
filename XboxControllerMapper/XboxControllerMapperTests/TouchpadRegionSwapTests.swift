import XCTest
import CoreGraphics
@testable import ControllerKeys

@MainActor
final class TouchpadRegionSwapTests: XCTestCase {
    private var profileManager: ProfileManager!
    private var testConfigDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        testConfigDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("controllerkeys-tests-\(UUID().uuidString)", isDirectory: true)
        profileManager = ProfileManager(configDirectoryOverride: testConfigDirectory)
    }

    override func tearDown() async throws {
        profileManager = nil
        testConfigDirectory = nil
        try await super.tearDown()
    }

    // MARK: - Classification (TouchpadRegion.from(position:))
    //
    // Convention from `TouchpadRegion.from`: positions come from
    // `GCControllerDirectionPad` in [-1, 1] with (0, 0) at the pad center.
    // Threshold is >= 0 → right, >= 0 → top. That makes the (0, 0) center
    // fall in `.topRight` (inclusive on both axes). Tests pin this so any
    // future refactor of the classifier breaks visibly rather than silently.

    func testRegionFromPositionInteriorPoints() {
        XCTAssertEqual(TouchpadRegion.from(position: CGPoint(x: -0.5, y: 0.5)), .topLeft)
        XCTAssertEqual(TouchpadRegion.from(position: CGPoint(x: 0.5, y: 0.5)), .topRight)
        XCTAssertEqual(TouchpadRegion.from(position: CGPoint(x: -0.5, y: -0.5)), .bottomLeft)
        XCTAssertEqual(TouchpadRegion.from(position: CGPoint(x: 0.5, y: -0.5)), .bottomRight)
    }

    func testRegionFromPositionCenterFallsIntoTopRight() {
        // (0, 0) is the pad center in HID coordinates. Inclusive on both
        // axes → top-right.
        XCTAssertEqual(TouchpadRegion.from(position: .zero), .topRight)
    }

    func testRegionFromPositionEdgesClassifyCorrectly() {
        // Sanity-check the four corners.
        XCTAssertEqual(TouchpadRegion.from(position: CGPoint(x: -1, y: 1)), .topLeft)
        XCTAssertEqual(TouchpadRegion.from(position: CGPoint(x: 1, y: 1)), .topRight)
        XCTAssertEqual(TouchpadRegion.from(position: CGPoint(x: -1, y: -1)), .bottomLeft)
        XCTAssertEqual(TouchpadRegion.from(position: CGPoint(x: 1, y: -1)), .bottomRight)
    }

    // MARK: - swapTouchpadRegions

    /// Both regions populated with one mapping each — fields move together.
    func testSwapBothRegionsPopulated() {
        let topLeftId = UUID()
        let topRightId = UUID()
        let topLeft = TouchpadRegionMapping(
            id: topLeftId,
            region: .topLeft,
            triggerMode: .click,
            keyCode: 10,
            modifiers: ModifierFlags(command: true),
            hint: "TL"
        )
        let topRight = TouchpadRegionMapping(
            id: topRightId,
            region: .topRight,
            triggerMode: .both,
            keyCode: 20,
            modifiers: ModifierFlags(shift: true),
            hint: "TR"
        )
        seedProfile(with: [topLeft, topRight])

        profileManager.swapTouchpadRegions(region1: .topLeft, region2: .topRight)

        let mappings = profileManager.activeProfile?.touchpadRegionMappings ?? []
        let movedToTopLeft = mappings.first { $0.id == topRightId }
        let movedToTopRight = mappings.first { $0.id == topLeftId }

        XCTAssertEqual(movedToTopLeft?.region, .topLeft, "TR mapping should now be tagged topLeft")
        XCTAssertEqual(movedToTopRight?.region, .topRight, "TL mapping should now be tagged topRight")

        // Unrelated fields preserved exactly.
        XCTAssertEqual(movedToTopLeft?.keyCode, 20)
        XCTAssertEqual(movedToTopLeft?.triggerMode, .both)
        XCTAssertTrue(movedToTopLeft?.modifiers.shift ?? false)
        XCTAssertEqual(movedToTopLeft?.hint, "TR")

        XCTAssertEqual(movedToTopRight?.keyCode, 10)
        XCTAssertEqual(movedToTopRight?.triggerMode, .click)
        XCTAssertTrue(movedToTopRight?.modifiers.command ?? false)
        XCTAssertEqual(movedToTopRight?.hint, "TL")
    }

    /// Source region populated, destination empty — mapping moves, source becomes empty.
    func testSwapOneEmptyRegion() {
        let mapping = TouchpadRegionMapping(region: .bottomLeft, triggerMode: .click, keyCode: 7)
        seedProfile(with: [mapping])

        profileManager.swapTouchpadRegions(region1: .bottomLeft, region2: .bottomRight)

        let mappings = profileManager.activeProfile?.touchpadRegionMappings ?? []
        XCTAssertEqual(mappings.count, 1, "Mapping count should be unchanged")
        XCTAssertEqual(mappings.first?.region, .bottomRight, "Sole mapping should now live in destination")
        XCTAssertFalse(mappings.contains { $0.region == .bottomLeft }, "Source should have no mappings")
    }

    /// Multiple mappings per region (touch + click) all migrate together.
    func testSwapMovesAllMappingsForRegionAsAUnit() {
        let touchId = UUID()
        let clickId = UUID()
        let touch = TouchpadRegionMapping(id: touchId, region: .topLeft, triggerMode: .touch, keyCode: 1)
        let click = TouchpadRegionMapping(id: clickId, region: .topLeft, triggerMode: .click, keyCode: 2)
        seedProfile(with: [touch, click])

        profileManager.swapTouchpadRegions(region1: .topLeft, region2: .bottomRight)

        let mappings = profileManager.activeProfile?.touchpadRegionMappings ?? []
        XCTAssertEqual(mappings.count, 2)
        XCTAssertTrue(mappings.allSatisfy { $0.region == .bottomRight }, "Both mappings should have moved")
        XCTAssertEqual(Set(mappings.map(\.id)), Set([touchId, clickId]), "IDs preserved across the swap")
    }

    /// Same region on both sides is a no-op — guard short-circuits before any rewrite.
    func testSwapSameRegionIsNoOp() {
        let id = UUID()
        let mapping = TouchpadRegionMapping(id: id, region: .topLeft, triggerMode: .click, keyCode: 5, hint: "Same")
        seedProfile(with: [mapping])

        profileManager.swapTouchpadRegions(region1: .topLeft, region2: .topLeft)

        let mappings = profileManager.activeProfile?.touchpadRegionMappings ?? []
        XCTAssertEqual(mappings.count, 1)
        XCTAssertEqual(mappings.first?.id, id)
        XCTAssertEqual(mappings.first?.region, .topLeft)
        XCTAssertEqual(mappings.first?.hint, "Same")
    }

    /// Swapping two regions leaves unrelated regions untouched.
    func testSwapPreservesUnrelatedRegions() {
        let tl = TouchpadRegionMapping(region: .topLeft, triggerMode: .click, keyCode: 1)
        let tr = TouchpadRegionMapping(region: .topRight, triggerMode: .click, keyCode: 2)
        let bl = TouchpadRegionMapping(region: .bottomLeft, triggerMode: .click, keyCode: 3)
        let br = TouchpadRegionMapping(region: .bottomRight, triggerMode: .click, keyCode: 4)
        seedProfile(with: [tl, tr, bl, br])

        profileManager.swapTouchpadRegions(region1: .topLeft, region2: .topRight)

        let mappings = profileManager.activeProfile?.touchpadRegionMappings ?? []
        XCTAssertEqual(mappings.count, 4)

        // Top-left and top-right swapped.
        XCTAssertEqual(mappings.first { $0.id == tl.id }?.region, .topRight)
        XCTAssertEqual(mappings.first { $0.id == tr.id }?.region, .topLeft)

        // Bottom-left and bottom-right unchanged.
        XCTAssertEqual(mappings.first { $0.id == bl.id }?.region, .bottomLeft)
        XCTAssertEqual(mappings.first { $0.id == br.id }?.region, .bottomRight)
    }

    /// Both regions empty — the operation should be a no-op without crashing.
    func testSwapBothRegionsEmpty() {
        seedProfile(with: [])

        profileManager.swapTouchpadRegions(region1: .topLeft, region2: .bottomRight)

        XCTAssertEqual(profileManager.activeProfile?.touchpadRegionMappings.count, 0)
    }

    // MARK: - shouldFireRegionClick policy
    //
    // Pure-function unit tests for the click-firing decision. These pin the
    // policy that ControllerService+Touchpad's pressedChangedHandler relies on,
    // without having to drive a real GameController button event through.

    func testShouldFireRegionClick_FiresOnNormalSingleFingerClick() {
        let result = ControllerService.shouldFireRegionClick(
            willBeTwoFingerClick: false,
            clickPosition: CGPoint(x: -0.5, y: 0.5),
            isCurrentlyTouching: true,
            requireActiveTouch: true
        )
        XCTAssertTrue(result, "Finger down at a real position should fire the region click")
    }

    func testShouldFireRegionClick_SuppressesTwoFingerClick() {
        let result = ControllerService.shouldFireRegionClick(
            willBeTwoFingerClick: true,
            clickPosition: CGPoint(x: -0.5, y: 0.5),
            isCurrentlyTouching: true,
            requireActiveTouch: true
        )
        XCTAssertFalse(result, "Two-finger clicks route through the two-finger handler, not regions")
    }

    func testShouldFireRegionClick_SuppressesZeroPosition() {
        // (0, 0) is the "never touched" sentinel; falling through to the base
        // touchpad click is preferable to misclassifying as bottom-left.
        let result = ControllerService.shouldFireRegionClick(
            willBeTwoFingerClick: false,
            clickPosition: .zero,
            isCurrentlyTouching: false,
            requireActiveTouch: false
        )
        XCTAssertFalse(result, "(0, 0) should never fire region clicks regardless of policy")
    }

    func testShouldFireRegionClick_RequireActiveTouchSuppressesStalePosition() {
        // Reproduces the customer's reported bug: finger landed near top-left,
        // lifted, then user pressed the physical click button. Without the
        // active-touch requirement, the stale (-0.8, 0.8) would re-fire the
        // top-left action ("Select All").
        let result = ControllerService.shouldFireRegionClick(
            willBeTwoFingerClick: false,
            clickPosition: CGPoint(x: -0.8, y: 0.8),
            isCurrentlyTouching: false,
            requireActiveTouch: true
        )
        XCTAssertFalse(result, "Click after finger-lift should not fire when active-touch is required")
    }

    func testShouldFireRegionClick_RequireActiveTouchOff_AllowsStalePosition() {
        // Legacy behavior — preserved for users who explicitly opt out.
        let result = ControllerService.shouldFireRegionClick(
            willBeTwoFingerClick: false,
            clickPosition: CGPoint(x: -0.8, y: 0.8),
            isCurrentlyTouching: false,
            requireActiveTouch: false
        )
        XCTAssertTrue(result, "With the setting off, stale-position clicks still fire (legacy behavior)")
    }

    // MARK: - Region action position selection

    func testPreferredTouchpadRegionPosition_UsesLatestLivePosition() {
        // The first touch sample can be noisier than the settled position the
        // UI displays. Region actions should follow the same latest position,
        // otherwise tap/click actions can feel biased while the visual overlay
        // looks correct.
        let position = ControllerService.preferredTouchpadRegionPosition(
            currentPosition: CGPoint(x: 0.5, y: 0.5),
            touchStartPosition: CGPoint(x: -0.5, y: -0.5)
        )

        XCTAssertEqual(position, CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(TouchpadRegion.from(position: position), .topRight)
    }

    func testPreferredTouchpadRegionPosition_FallsBackToTouchStartWhenCurrentIsZero() {
        let position = ControllerService.preferredTouchpadRegionPosition(
            currentPosition: .zero,
            touchStartPosition: CGPoint(x: -0.5, y: 0.5)
        )

        XCTAssertEqual(position, CGPoint(x: -0.5, y: 0.5))
        XCTAssertEqual(TouchpadRegion.from(position: position), .topLeft)
    }

    func testPreferredTouchpadRegionPosition_RepairsZeroedXAxisOnLeftTapLift() {
        // Tap lift can report x == 0 while y still carries the real vertical
        // side. Without repairing x from touch-start, left-side taps classify
        // as right-side actions because the center boundary is inclusive.
        let topLeft = ControllerService.preferredTouchpadRegionPosition(
            currentPosition: CGPoint(x: 0, y: 0.5),
            touchStartPosition: CGPoint(x: -0.5, y: 0.5)
        )
        let bottomLeft = ControllerService.preferredTouchpadRegionPosition(
            currentPosition: CGPoint(x: 0, y: -0.5),
            touchStartPosition: CGPoint(x: -0.5, y: -0.5)
        )

        XCTAssertEqual(TouchpadRegion.from(position: topLeft), .topLeft)
        XCTAssertEqual(TouchpadRegion.from(position: bottomLeft), .bottomLeft)
    }

    func testPreferredTouchpadRegionPosition_RepairsZeroedYAxisOnBottomTapLift() {
        let bottomRight = ControllerService.preferredTouchpadRegionPosition(
            currentPosition: CGPoint(x: 0.5, y: 0),
            touchStartPosition: CGPoint(x: 0.5, y: -0.5)
        )

        XCTAssertEqual(TouchpadRegion.from(position: bottomRight), .bottomRight)
    }

    // MARK: - JoystickSettings codable roundtrip for the new flag

    func testRequireActiveTouchForRegionClick_DefaultsToTrueWhenAbsentFromJSON() throws {
        // Older configs predate this field. They must still decode cleanly with
        // the safer default (require active touch = on).
        let legacyJSON = "{}".data(using: .utf8)!
        let settings = try JSONDecoder().decode(JoystickSettings.self, from: legacyJSON)
        XCTAssertTrue(settings.requireActiveTouchForRegionClick, "Missing field should default to true")
    }

    func testRequireActiveTouchForRegionClick_RoundtripsWhenSetToFalse() throws {
        var settings = JoystickSettings.default
        settings.requireActiveTouchForRegionClick = false
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(JoystickSettings.self, from: data)
        XCTAssertFalse(decoded.requireActiveTouchForRegionClick, "Explicit false must roundtrip")
    }

    // MARK: - Helpers

    /// Seeds the bootstrap default profile's touchpad region mappings. We mutate the
    /// existing active profile rather than substituting a fresh `Profile` via
    /// `setActiveProfile`, because `saveConfiguration` orphans any active profile
    /// whose id isn't already in the `profiles` array.
    private func seedProfile(with regionMappings: [TouchpadRegionMapping]) {
        profileManager.updateTouchpadRegionMappings(regionMappings)
    }
}
