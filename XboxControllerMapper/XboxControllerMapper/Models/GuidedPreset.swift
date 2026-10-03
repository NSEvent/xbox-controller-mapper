import Foundation

enum GuidedPreset: String, CaseIterable, Identifiable {
	case anki, photoCulling, finalCut, oneHand
	var id: String { rawValue }
	var title: String {
		switch self {
		case .anki: return "Review Anki cards"
		case .photoCulling: return "Cull photos in Photo Mechanic"
		case .finalCut: return "Review a Final Cut timeline"
		case .oneHand: return "Control your Mac with one hand"
		}
	}
	var icon: String {
		switch self {
		case .anki: return "rectangle.on.rectangle"
		case .photoCulling: return "photo"
		case .finalCut: return "film"
		case .oneHand: return "hand.point.up"
		}
	}
	var preferredBundleIds: [String] {
		switch self {
		case .anki: return ["net.ankiweb.launcher", "net.ankiweb.anki"]
		case .photoCulling: return [] // Choose the installed edition explicitly.
		case .finalCut: return ["com.apple.FinalCut"]
		case .oneHand: return []
		}
	}
	var testInstruction: String {
		switch self {
		case .anki: return "Open a review card in Anki. Press A once: the answer should appear."
		case .photoCulling: return "Open a contact sheet or preview. Press Right Bumper: selection should move to the next photo."
		case .finalCut: return "Open a timeline in Final Cut Pro. Press A: playback should start or pause."
		case .oneHand: return "Open a disposable Finder window. Use the left stick to move the pointer; press A on a folder to select it."
		}
	}
	var setupInstruction: String {
		switch self {
		case .anki: return "Uses Anki's standard review keys. Bring the review pane forward before testing."
		case .photoCulling: return "Uses arrow navigation and Control+number star ratings. Review your customized Photo Mechanic shortcuts first."
		case .finalCut: return "Uses the standard Final Cut command set. Customized keyboard layouts may need edits."
		case .oneHand: return "Left stick moves the pointer; face buttons click, go back, focus next, and open the on-screen keyboard. Adjust reach and sensitivity to suit your hand."
		}
	}

	/// Small, local, deterministic starting profiles; no downloads or automation.
	func makeProfile(name: String, targetBundleId: String?, linkApp: Bool) -> Profile {
		func key(_ code: UInt16, _ hint: String, modifiers: ModifierFlags = ModifierFlags()) -> KeyMapping {
			KeyMapping(keyCode: code, modifiers: modifiers, hint: hint)
		}
		var bindings: [ControllerButton: KeyMapping]
		var settings = JoystickSettings.default
		switch self {
		case .anki:
			bindings = [.a: key(49, "Show Answer / Good"), .b: key(18, "Again"), .x: key(19, "Hard"),
						.y: key(21, "Easy"), .rightBumper: key(20, "Good"), .leftBumper: key(14, "Edit Card"),
						.dpadLeft: key(6, "Undo", modifiers: ModifierFlags(command: true))]
			settings.leftStick.mode = .none; settings.rightStick.mode = .none
		case .photoCulling:
			bindings = [.a: key(23, "Five Stars", modifiers: ModifierFlags(control: true)),
						.b: key(29, "Clear Rating", modifiers: ModifierFlags(control: true)),
						.x: key(18, "One Star", modifiers: ModifierFlags(control: true)),
						.y: key(20, "Three Stars", modifiers: ModifierFlags(control: true)),
						.leftBumper: key(123, "Previous Photo"), .rightBumper: key(124, "Next Photo")]
			settings.leftStick.mode = .none; settings.rightStick.mode = .none
		case .finalCut:
			bindings = [.a: key(49, "Play / Pause"), .b: key(40, "Stop Playback"),
						.x: key(34, "Mark In"), .y: key(31, "Mark Out"),
						.leftBumper: key(123, "Previous Frame"), .rightBumper: key(124, "Next Frame")]
			settings.leftStick.mode = .none; settings.rightStick.mode = .none
		case .oneHand:
			bindings = [.a: key(0xF000, "Left Click"), .b: key(53, "Escape / Back"),
						.x: key(48, "Next Focus"), .y: key(0xF010, "On-Screen Keyboard"),
						.leftBumper: key(36, "Confirm"), .rightBumper: key(0xF001, "Right Click")]
			settings.leftStick.mouseSensitivity = 0.3
		}
		return Profile(name: name, icon: icon, buttonMappings: bindings, joystickSettings: settings,
					   linkedApps: linkApp ? targetBundleId.map { [$0] } ?? [] : [])
	}
}
