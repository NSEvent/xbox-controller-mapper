import Foundation
import CoreGraphics

/// Virtual ControllerKeys actions that reproduce Codex Micro firmware input.
/// These values live outside the macOS keyboard range and are intercepted by
/// `InputSimulator` before any CGEvent is posted.
enum CodexMicroControl: UInt16, CaseIterable, Sendable {
	case agent1 = 0xF100
	case agent2 = 0xF101
	case agent3 = 0xF102
	case agent4 = 0xF103
	case agent5 = 0xF104
	case agent6 = 0xF105

	case fast = 0xF106
	case approve = 0xF107
	case decline = 0xF108
	case fork = 0xF109
	case pushToTalk = 0xF10A
	case action11 = 0xF10B
	case submit = 0xF10C

	case dialClockwise = 0xF110
	case dialCounterclockwise = 0xF111
	case dialClick = 0xF112

	case stickUp = 0xF120
	case stickRight = 0xF121
	case stickDown = 0xF122
	case stickLeft = 0xF123

	var keyCode: CGKeyCode {
		CGKeyCode(rawValue)
	}

	init?(keyCode: CGKeyCode) {
		self.init(rawValue: UInt16(keyCode))
	}

	var displayName: String {
		switch self {
		case .agent1: return "Codex Micro: Agent 1"
		case .agent2: return "Codex Micro: Agent 2"
		case .agent3: return "Codex Micro: Agent 3"
		case .agent4: return "Codex Micro: Agent 4"
		case .agent5: return "Codex Micro: Agent 5"
		case .agent6: return "Codex Micro: Agent 6"
		case .fast: return "Codex Micro: Fast"
		case .approve: return "Codex Micro: Approve"
		case .decline: return "Codex Micro: Decline"
		case .fork: return "Codex Micro: Fork"
		case .pushToTalk: return "Codex Micro: Push to Talk"
		case .action11: return "Codex Micro: Action 11"
		case .submit: return "Codex Micro: Submit"
		case .dialClockwise: return "Codex Micro: Dial Clockwise"
		case .dialCounterclockwise: return "Codex Micro: Dial Counterclockwise"
		case .dialClick: return "Codex Micro: Dial Click"
		case .stickUp: return "Codex Micro: Stick Up"
		case .stickRight: return "Codex Micro: Stick Right"
		case .stickDown: return "Codex Micro: Stick Down"
		case .stickLeft: return "Codex Micro: Stick Left"
		}
	}

	/// Exact radial angle values consumed by ChatGPT: right starts at zero and
	/// angles increase clockwise in quarter turns.
	var joystickAngle: Double? {
		switch self {
		case .stickRight: return 0
		case .stickDown: return 0.25
		case .stickLeft: return 0.5
		case .stickUp: return 0.75
		default: return nil
		}
	}

	var agentIndex: Int? {
		switch self {
		case .agent1: return 0
		case .agent2: return 1
		case .agent3: return 2
		case .agent4: return 3
		case .agent5: return 4
		case .agent6: return 5
		default: return nil
		}
	}

	var hidKey: String? {
		if let agentIndex {
			return String(format: "AG%02d", agentIndex)
		}

		switch self {
		case .fast: return "ACT06"
		case .approve: return "ACT07"
		case .decline: return "ACT08"
		case .fork: return "ACT09"
		case .pushToTalk: return "ACT10"
		case .action11: return "ACT11"
		case .submit: return "ACT12"
		case .dialClockwise: return "ENC_CW"
		case .dialCounterclockwise: return "ENC_CC"
		case .dialClick: return "ENC_CLK"
		case .agent1, .agent2, .agent3, .agent4, .agent5, .agent6,
			 .stickUp, .stickRight, .stickDown, .stickLeft:
			return nil
		}
	}

	var isDialRotation: Bool {
		self == .dialClockwise || self == .dialCounterclockwise
	}
}
