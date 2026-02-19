import XCTest
@testable import ControllerKeys

final class BindingAnalysisEngineTests: XCTestCase {

    // MARK: - Input Cost Tests

    func testInputCostSinglePressFace() {
        let cost = BindingAnalysisEngine.singleButtonCost(button: .a, type: "Press")
        XCTAssertEqual(cost, 1.0, accuracy: 0.001)
    }

    func testInputCostSinglePressDpad() {
        let cost = BindingAnalysisEngine.singleButtonCost(button: .dpadUp, type: "Press")
        XCTAssertEqual(cost, 1.1, accuracy: 0.001)
    }

    func testInputCostSinglePressThumbstick() {
        let cost = BindingAnalysisEngine.singleButtonCost(button: .leftThumbstick, type: "Press")
        XCTAssertEqual(cost, 1.3, accuracy: 0.001)
    }

    func testInputCostSinglePressSpecial() {
        let cost = BindingAnalysisEngine.singleButtonCost(button: .menu, type: "Press")
        XCTAssertEqual(cost, 1.4, accuracy: 0.001)
    }

    func testInputCostLongPressFace() {
        let cost = BindingAnalysisEngine.singleButtonCost(button: .a, type: "Long Press")
        XCTAssertEqual(cost, 2.0, accuracy: 0.001)
    }

    func testInputCostLongPressDpad() {
        let cost = BindingAnalysisEngine.singleButtonCost(button: .dpadDown, type: "Long Press")
        XCTAssertEqual(cost, 2.1, accuracy: 0.001)
    }

    func testInputCostDoubleTap() {
        let cost = BindingAnalysisEngine.singleButtonCost(button: .a, type: "Double Tap")
        XCTAssertEqual(cost, 1.5, accuracy: 0.001)
    }

    func testInputCostChordCrossHand() {
        // bumper + face = cross-hand
        let cost = BindingAnalysisEngine.chordCost(buttonPart: "leftBumper+a")
        XCTAssertEqual(cost, 1.3, accuracy: 0.001)
    }

    func testInputCostChordSameHand() {
        // face + face = same-hand
        let cost = BindingAnalysisEngine.chordCost(buttonPart: "a+b")
        XCTAssertEqual(cost, 1.8, accuracy: 0.001)
    }

    func testInputCostChordThreeButtons() {
        let cost = BindingAnalysisEngine.chordCost(buttonPart: "leftBumper+a+b")
        XCTAssertEqual(cost, 2.2, accuracy: 0.001)
    }

    // MARK: - Cross-Hand Detection

    func testCrossHandBumperFace() {
        XCTAssertTrue(BindingAnalysisEngine.isCrossHand(.leftBumper, .a))
        XCTAssertTrue(BindingAnalysisEngine.isCrossHand(.rightBumper, .y))
    }

    func testCrossHandTriggerDpad() {
        XCTAssertTrue(BindingAnalysisEngine.isCrossHand(.leftTrigger, .dpadUp))
    }

    func testSameHandFaceFace() {
        XCTAssertFalse(BindingAnalysisEngine.isCrossHand(.a, .b))
    }

    func testSameHandBumperBumper() {
        XCTAssertFalse(BindingAnalysisEngine.isCrossHand(.leftBumper, .rightBumper))
    }

    // MARK: - Analyze

    func testAnalyzeInsufficientData() {
        var counts: [String: Int] = [:]
        // Only 30 total actions — below 50 minimum
        counts["a:Press"] = 20
        counts["b:Press"] = 10

        let profile = Profile.createDefault()
        let result = BindingAnalysisEngine.analyze(actionDetailCounts: counts, profile: profile)

        XCTAssertFalse(result.hasEnoughData)
        XCTAssertTrue(result.entries.isEmpty)
        XCTAssertTrue(result.recommendations.isEmpty)
    }

    func testAnalyzeFiltersLowOccurrence() {
        var counts: [String: Int] = [:]
        counts["a:Press"] = 40
        counts["b:Press"] = 10
        counts["x:Press"] = 2  // Below minimumOccurrences (3)

        let profile = Profile.createDefault()
        let result = BindingAnalysisEngine.analyze(actionDetailCounts: counts, profile: profile)

        XCTAssertTrue(result.hasEnoughData)
        // x:Press should be filtered out
        XCTAssertFalse(result.entries.contains(where: { $0.actionKey == "x:Press" }))
        XCTAssertTrue(result.entries.contains(where: { $0.actionKey == "a:Press" }))
        XCTAssertTrue(result.entries.contains(where: { $0.actionKey == "b:Press" }))
    }

    func testEfficiencyScoreInRange() {
        var counts: [String: Int] = [:]
        counts["a:Press"] = 30
        counts["leftThumbstick:Long Press"] = 15
        counts["dpadUp:Press"] = 10

        let profile = Profile.createDefault()
        let result = BindingAnalysisEngine.analyze(actionDetailCounts: counts, profile: profile)

        XCTAssertTrue(result.hasEnoughData)
        XCTAssertGreaterThanOrEqual(result.efficiencyScore, 0.0)
        XCTAssertLessThanOrEqual(result.efficiencyScore, 1.0)
    }

    func testSwapRecommendationGenerated() {
        // Frequent action on expensive button, infrequent on cheap button
        var counts: [String: Int] = [:]
        counts["menu:Press"] = 40      // special button (cost 1.4) - frequent
        counts["a:Press"] = 5          // face button (cost 1.0) - infrequent
        counts["b:Press"] = 5          // padding to reach minimum

        var profile = Profile.createDefault()
        profile.buttonMappings[.menu] = KeyMapping(keyCode: 0x00, hint: "Cmd-A")
        profile.buttonMappings[.a] = KeyMapping(keyCode: 0x01, hint: "Esc")

        let result = BindingAnalysisEngine.analyze(actionDetailCounts: counts, profile: profile)

        let swaps = result.recommendations.filter {
            if case .swap = $0.type { return true }
            return false
        }
        XCTAssertFalse(swaps.isEmpty, "Should generate at least one swap recommendation")
    }

    func testRecommendationsAreNonConflicting() {
        var counts: [String: Int] = [:]
        counts["menu:Press"] = 30
        counts["view:Press"] = 25
        counts["a:Press"] = 5
        counts["b:Press"] = 3

        var profile = Profile.createDefault()
        profile.buttonMappings[.menu] = KeyMapping(keyCode: 0x00)
        profile.buttonMappings[.view] = KeyMapping(keyCode: 0x01)
        profile.buttonMappings[.a] = KeyMapping(keyCode: 0x02)
        profile.buttonMappings[.b] = KeyMapping(keyCode: 0x03)

        let result = BindingAnalysisEngine.analyze(actionDetailCounts: counts, profile: profile)

        // Verify no two recommendations share a button
        for i in 0..<result.recommendations.count {
            for j in (i + 1)..<result.recommendations.count {
                let a = result.recommendations[i].type.involvedButtons
                let b = result.recommendations[j].type.involvedButtons
                XCTAssertTrue(a.isDisjoint(with: b),
                    "Recommendations \(i) and \(j) share buttons: \(a.intersection(b))")
            }
        }
    }

    func testLookupDescriptionUsesHint() {
        var profile = Profile.createDefault()
        profile.buttonMappings[.a] = KeyMapping(keyCode: 0x00, hint: "Copy Selection")

        let desc = BindingAnalysisEngine.descriptionForActionKey("a:Press", profile: profile)
        XCTAssertEqual(desc, "Copy Selection")
    }

    func testLookupDescriptionFallsBackToDisplayString() {
        var profile = Profile.createDefault()
        profile.buttonMappings[.a] = KeyMapping(keyCode: 0x00) // No hint, keyCode 0x00 = "A"

        let desc = BindingAnalysisEngine.descriptionForActionKey("a:Press", profile: profile)
        XCTAssertEqual(desc, "A")
    }

    func testLookupDescriptionLongPress() {
        var profile = Profile.createDefault()
        profile.buttonMappings[.a] = KeyMapping(
            keyCode: 0x00,
            longHoldMapping: LongHoldMapping(keyCode: 0x01, hint: "Undo")
        )

        let desc = BindingAnalysisEngine.descriptionForActionKey("a:Long Press", profile: profile)
        XCTAssertEqual(desc, "Undo")
    }

    func testButtonFromActionKey() {
        XCTAssertEqual(BindingAnalysisEngine.buttonFromActionKey("a:Press"), .a)
        XCTAssertEqual(BindingAnalysisEngine.buttonFromActionKey("leftBumper:Long Press"), .leftBumper)
        XCTAssertNil(BindingAnalysisEngine.buttonFromActionKey("a+b:Chord"))
        XCTAssertNil(BindingAnalysisEngine.buttonFromActionKey("invalid"))
    }

    // MARK: - Conflict Filtering

    func testFilterConflictingRemovesDuplicateButtons() {
        let rec1 = BindingRecommendation(
            type: .swap(button1: .a, button2: .b),
            priority: 10.0,
            description: "Swap A and B",
            beforeDescription: "", afterDescription: ""
        )
        let rec2 = BindingRecommendation(
            type: .swap(button1: .a, button2: .x),
            priority: 5.0,
            description: "Swap A and X",
            beforeDescription: "", afterDescription: ""
        )

        let filtered = BindingAnalysisEngine.filterConflicting([rec1, rec2])
        XCTAssertEqual(filtered.count, 1)
        // Higher priority wins
        XCTAssertEqual(filtered[0].description, "Swap A and B")
    }

    func testFilterConflictingKeepsNonOverlapping() {
        let rec1 = BindingRecommendation(
            type: .swap(button1: .a, button2: .b),
            priority: 10.0,
            description: "Swap A and B",
            beforeDescription: "", afterDescription: ""
        )
        let rec2 = BindingRecommendation(
            type: .swap(button1: .x, button2: .y),
            priority: 5.0,
            description: "Swap X and Y",
            beforeDescription: "", afterDescription: ""
        )

        let filtered = BindingAnalysisEngine.filterConflicting([rec1, rec2])
        XCTAssertEqual(filtered.count, 2)
    }
}
