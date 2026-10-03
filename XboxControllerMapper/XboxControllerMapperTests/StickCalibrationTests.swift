import CoreGraphics
import XCTest
@testable import ControllerKeys

final class StickCalibrationTests: XCTestCase {
	func testRestSuggestionRequiresSamplesAndRejectsMovement() {
		var measurement = StickCalibrationMeasurement()
		measurement.recordRest(CGPoint(x: 0.1, y: 0))
		XCTAssertNil(measurement.suggestedInner)
		for _ in 0..<60 { measurement.recordRest(CGPoint(x: 0.1, y: 0)) }
		XCTAssertEqual(measurement.suggestedInner ?? 0, 0.13, accuracy: 0.001)
		measurement.recordRest(CGPoint(x: 0.6, y: 0))
		XCTAssertNil(measurement.suggestedInner)
	}
	func testRangeRequiresAllDirectionsAndUsesWeakestReach() {
		var measurement = StickCalibrationMeasurement()
		measurement.recordRange(CGPoint(x: 1, y: 0))
		XCTAssertNil(measurement.suggestedOuter)
		for index in 0..<8 {
			let angle = (Double(index) + 0.5) * .pi / 4 - .pi
			let radius = index == 0 ? 0.8 : 1
			measurement.recordRange(CGPoint(x: cos(angle) * radius, y: sin(angle) * radius))
		}
		XCTAssertEqual(measurement.suggestedOuter ?? 0, 0.78, accuracy: 0.001)
	}
	func testOuterRangeNormalizationPreservesDefaultAndCapsCalibratedTravel() {
		let diagonal = CGPoint(x: 1, y: 1)
		XCTAssertEqual(StickCalibrationMeasurement.normalized(diagonal, outerRange: 1), diagonal)
		XCTAssertEqual(StickCalibrationMeasurement.normalized(CGPoint(x: 0.8, y: 0), outerRange: 0.8).x, 1, accuracy: 0.001)
		XCTAssertEqual(StickCalibrationMeasurement.normalized(CGPoint(x: 0.4, y: 0), outerRange: 0.8).x, 0.5, accuracy: 0.001)
	}
	func testOldProfilesDefaultToUnchangedTravel() throws {
		let tuning = try JSONDecoder().decode(StickTuning.self, from: Data(#"{"mode":"mouse"}"#.utf8))
		XCTAssertEqual(tuning.outerRange, 1)
		var calibrated = tuning
		calibrated.outerRange = 0.82
		XCTAssertEqual(try JSONDecoder().decode(StickTuning.self, from: JSONEncoder().encode(calibrated)), calibrated)
	}
}
