import XCTest
@testable import ControllerKeys

final class ProfileDefaultMappingsTests: XCTestCase {
    func testCreateDefault_includesCenterMouseChord() {
        let profile = Profile.createDefault()

        let chord = profile.chordMappings.first { $0.buttons == Set([.xbox, .menu]) }
        XCTAssertNotNil(chord, "Default profile should include xbox+menu chord")

        guard let systemCommand = chord?.systemCommand else {
            XCTFail("xbox+menu chord should be a system command")
            return
        }

        guard case .shellCommand(let command, let inTerminal) = systemCommand else {
            XCTFail("xbox+menu chord should use shellCommand")
            return
        }

        XCTAssertFalse(inTerminal, "Center mouse command should run silently")
        XCTAssertTrue(command.contains("CGWarpMouseCursorPosition"), "Command should warp cursor to center")
    }
}
