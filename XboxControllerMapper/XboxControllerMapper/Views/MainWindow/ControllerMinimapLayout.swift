import SwiftUI

// MARK: - Controller Minimap Layout
//
// Normalized control positions for each controller preview, measured from
// the same product photos the body silhouettes were traced from. All
// coordinates are fractions of the preview frame (x of width, y of height);
// sizes are fractions of the frame WIDTH so controls keep their aspect.
// `ControllerBodyView` (decor) and `ControllerAnalogOverlay` (interactive
// elements) both read from these tables so they stay in registration.

/// Which product the preview is mimicking. Distinct from
/// `ControllerPreviewLayout` (which includes `.active`); this is the
/// resolved visual style.
enum ControllerMinimapStyle {
    case xbox
    case xboxElite
    case dualSense
    case dualSenseEdge
    case dualShock
    case nintendo
    case steam

    var bodyAspectRatio: CGFloat {
        switch self {
        case .xbox: return ControllerBodyShape.aspectRatio
        case .xboxElite: return XboxEliteBodyShape.aspectRatio
        case .dualSense, .dualSenseEdge: return DualSenseBodyShape.aspectRatio
        case .dualShock: return DualShockBodyShape.aspectRatio
        case .nintendo: return NintendoProBodyShape.aspectRatio
        case .steam: return SteamControllerBodyShape.aspectRatio
        }
    }

    /// Preview frame, width-locked with the traced aspect ratio.
    static let previewWidth: CGFloat = 340

    var previewSize: CGSize {
        CGSize(
            width: Self.previewWidth,
            height: (Self.previewWidth / bodyAspectRatio).rounded()
        )
    }
}

extension View {
    /// Position a control at a layout-normalized point within a minimap frame.
    func minimapPosition(_ point: CGPoint, in size: CGSize) -> some View {
        position(x: point.x * size.width, y: point.y * size.height)
    }
}

// MARK: - Xbox Series X|S

enum XboxMinimapLayout {
    static let guide = CGPoint(x: 0.50, y: 0.125)
    static let guideSize: CGFloat = 0.082

    static let view = CGPoint(x: 0.415, y: 0.27)
    static let menu = CGPoint(x: 0.585, y: 0.27)
    static let viewMenuSize: CGFloat = 0.045
    static let share = CGPoint(x: 0.50, y: 0.315)
    static let shareSize: CGFloat = 0.038

    static let leftStick = CGPoint(x: 0.235, y: 0.27)
    static let rightStick = CGPoint(x: 0.615, y: 0.50)
    static let stickWellSize: CGFloat = 0.16

    static let faceCluster = CGPoint(x: 0.745, y: 0.27)
    static let faceButtonOffset: CGFloat = 0.057
    static let faceButtonSize: CGFloat = 0.062

    static let dpad = CGPoint(x: 0.385, y: 0.50)
    static let dpadSize: CGFloat = 0.15

    static let leftBumper = CGPoint(x: 0.275, y: 0.055)
    static let rightBumper = CGPoint(x: 0.725, y: 0.055)
    static let leftTrigger = CGPoint(x: 0.235, y: 0.012)
    static let rightTrigger = CGPoint(x: 0.765, y: 0.012)

    static let battery = CGPoint(x: 0.50, y: 0.88)
}

// MARK: - Xbox Elite Series 2

enum XboxEliteMinimapLayout {
    static let guide = CGPoint(x: 0.50, y: 0.115)
    static let guideSize: CGFloat = 0.080

    static let view = CGPoint(x: 0.415, y: 0.225)
    static let menu = CGPoint(x: 0.585, y: 0.225)
    static let viewMenuSize: CGFloat = 0.045
    /// Profile-switch pill below the guide button.
    static let profileSlot = CGPoint(x: 0.50, y: 0.27)

    static let leftStick = CGPoint(x: 0.235, y: 0.245)
    static let rightStick = CGPoint(x: 0.625, y: 0.475)
    static let stickWellSize: CGFloat = 0.165

    static let faceCluster = CGPoint(x: 0.765, y: 0.235)
    static let faceButtonOffset: CGFloat = 0.057
    static let faceButtonSize: CGFloat = 0.060

    static let dpad = CGPoint(x: 0.375, y: 0.475)
    static let dpadSize: CGFloat = 0.155

    static let leftBumper = CGPoint(x: 0.275, y: 0.05)
    static let rightBumper = CGPoint(x: 0.725, y: 0.05)
    static let leftTrigger = CGPoint(x: 0.235, y: 0.01)
    static let rightTrigger = CGPoint(x: 0.765, y: 0.01)

    static let battery = CGPoint(x: 0.50, y: 0.88)
}

// MARK: - DualSense / DualSense Edge

enum DualSenseMinimapLayout {
    static let touchpad = CGPoint(x: 0.50, y: 0.20)
    static let touchpadSize = CGSize(width: 0.28, height: 0.19)

    static let create = CGPoint(x: 0.305, y: 0.085)
    static let options = CGPoint(x: 0.695, y: 0.085)
    static let createOptionsSize: CGFloat = 0.030

    static let dpad = CGPoint(x: 0.195, y: 0.265)
    static let dpadSize: CGFloat = 0.145

    static let faceCluster = CGPoint(x: 0.805, y: 0.265)
    static let faceButtonOffset: CGFloat = 0.048
    static let faceButtonSize: CGFloat = 0.046

    static let leftStick = CGPoint(x: 0.385, y: 0.475)
    static let rightStick = CGPoint(x: 0.615, y: 0.475)
    static let stickWellSize: CGFloat = 0.145

    static let micGrille = CGPoint(x: 0.50, y: 0.385)
    static let psButton = CGPoint(x: 0.50, y: 0.50)
    static let psButtonSize: CGFloat = 0.052
    static let micMute = CGPoint(x: 0.50, y: 0.585)

    /// Edge-only: Fn pills below the sticks.
    static let leftFunction = CGPoint(x: 0.40, y: 0.60)
    static let rightFunction = CGPoint(x: 0.60, y: 0.60)

    static let leftBumper = CGPoint(x: 0.20, y: 0.045)
    static let rightBumper = CGPoint(x: 0.80, y: 0.045)
    static let leftTrigger = CGPoint(x: 0.165, y: 0.01)
    static let rightTrigger = CGPoint(x: 0.835, y: 0.01)

    static let battery = CGPoint(x: 0.50, y: 0.90)
}

// MARK: - DualShock 4

enum DualShockMinimapLayout {
    static let touchpad = CGPoint(x: 0.50, y: 0.185)
    static let touchpadSize = CGSize(width: 0.30, height: 0.20)

    static let share = CGPoint(x: 0.305, y: 0.10)
    static let options = CGPoint(x: 0.695, y: 0.10)
    static let shareOptionsSize: CGFloat = 0.028

    static let dpad = CGPoint(x: 0.165, y: 0.225)
    static let dpadSize: CGFloat = 0.135

    static let faceCluster = CGPoint(x: 0.835, y: 0.225)
    static let faceButtonOffset: CGFloat = 0.050
    static let faceButtonSize: CGFloat = 0.050

    static let leftStick = CGPoint(x: 0.36, y: 0.43)
    static let rightStick = CGPoint(x: 0.64, y: 0.43)
    static let stickWellSize: CGFloat = 0.15

    static let speakerGrille = CGPoint(x: 0.50, y: 0.345)
    static let psButton = CGPoint(x: 0.50, y: 0.50)
    static let psButtonSize: CGFloat = 0.052

    static let leftBumper = CGPoint(x: 0.135, y: 0.045)
    static let rightBumper = CGPoint(x: 0.865, y: 0.045)
    static let leftTrigger = CGPoint(x: 0.115, y: 0.008)
    static let rightTrigger = CGPoint(x: 0.885, y: 0.008)

    static let battery = CGPoint(x: 0.50, y: 0.88)
}

// MARK: - Nintendo Switch Pro

enum NintendoProMinimapLayout {
    static let minus = CGPoint(x: 0.36, y: 0.15)
    static let plus = CGPoint(x: 0.64, y: 0.15)
    static let minusPlusSize: CGFloat = 0.040

    static let capture = CGPoint(x: 0.415, y: 0.295)
    static let home = CGPoint(x: 0.585, y: 0.295)
    static let captureHomeSize: CGFloat = 0.038

    static let leftStick = CGPoint(x: 0.235, y: 0.26)
    static let rightStick = CGPoint(x: 0.63, y: 0.44)
    static let stickWellSize: CGFloat = 0.145

    static let faceCluster = CGPoint(x: 0.77, y: 0.255)
    static let faceButtonOffset: CGFloat = 0.055
    static let faceButtonSize: CGFloat = 0.058

    static let dpad = CGPoint(x: 0.345, y: 0.455)
    static let dpadSize: CGFloat = 0.155

    static let leftBumper = CGPoint(x: 0.25, y: 0.045)
    static let rightBumper = CGPoint(x: 0.75, y: 0.045)
    static let leftTrigger = CGPoint(x: 0.21, y: 0.008)
    static let rightTrigger = CGPoint(x: 0.79, y: 0.008)

    static let battery = CGPoint(x: 0.50, y: 0.88)
}

// MARK: - Steam Controller

enum SteamMinimapLayout {
    static let dpad = CGPoint(x: 0.20, y: 0.145)
    static let dpadSize: CGFloat = 0.115

    static let view = CGPoint(x: 0.345, y: 0.095)
    static let menu = CGPoint(x: 0.655, y: 0.095)
    static let viewMenuSize: CGFloat = 0.040

    static let guide = CGPoint(x: 0.50, y: 0.135)
    static let guideSize: CGFloat = 0.062

    static let faceCluster = CGPoint(x: 0.80, y: 0.145)
    static let faceButtonOffset: CGFloat = 0.044
    static let faceButtonSize: CGFloat = 0.044

    static let leftStick = CGPoint(x: 0.345, y: 0.27)
    static let rightStick = CGPoint(x: 0.655, y: 0.27)
    static let stickWellSize: CGFloat = 0.14

    static let leftTouchpad = CGPoint(x: 0.345, y: 0.555)
    static let rightTouchpad = CGPoint(x: 0.655, y: 0.555)
    static let touchpadSize: CGFloat = 0.21

    static let share = CGPoint(x: 0.50, y: 0.555)
    static let shareSize: CGFloat = 0.036

    static let leftBumper = CGPoint(x: 0.115, y: 0.035)
    static let rightBumper = CGPoint(x: 0.885, y: 0.035)
    static let leftTrigger = CGPoint(x: 0.075, y: 0.012)
    static let rightTrigger = CGPoint(x: 0.925, y: 0.012)

    static let battery = CGPoint(x: 0.50, y: 0.90)
}
