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
/// Which of the small 8BitDo pads a minimap renders. Carried as one optional
/// alongside the older boolean style flags (`isPlayStation` etc.).
enum EightBitDoMinimapModel: String, CaseIterable {
    case zero2
    case micro
    case lite2
    case liteSE

    var minimapStyle: ControllerMinimapStyle {
        switch self {
        case .zero2: return .eightBitDoZero2
        case .micro: return .eightBitDoMicro
        case .lite2: return .eightBitDoLite2
        case .liteSE: return .eightBitDoLiteSE
        }
    }
}

enum ControllerMinimapStyle {
    case xbox
    case xboxElite
    case dualSense
    case dualSenseEdge
    case dualShock
    case nintendo
    case steam
    case eightBitDoZero2
    case eightBitDoMicro
    case eightBitDoLite2
    case eightBitDoLiteSE

    var bodyAspectRatio: CGFloat {
        switch self {
        case .xbox: return ControllerBodyShape.aspectRatio
        case .xboxElite: return XboxEliteBodyShape.aspectRatio
        case .dualSense, .dualSenseEdge: return DualSenseBodyShape.aspectRatio
        case .dualShock: return DualShockBodyShape.aspectRatio
        case .nintendo: return NintendoProBodyShape.aspectRatio
        case .steam: return SteamControllerBodyShape.aspectRatio
        case .eightBitDoZero2: return EightBitDoZero2BodyShape.aspectRatio
        case .eightBitDoMicro: return EightBitDoMicroBodyShape.aspectRatio
        case .eightBitDoLite2: return EightBitDoLite2BodyShape.aspectRatio
        case .eightBitDoLiteSE: return EightBitDoLiteSEBodyShape.aspectRatio
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

    // Back paddles peeking into the valley between the grips (the body's
    // bottom arch sits at y ≈ 0.726).
    static let paddleUpperLeft = CGPoint(x: 0.435, y: 0.775)
    static let paddleUpperRight = CGPoint(x: 0.565, y: 0.775)
    static let paddleLowerLeft = CGPoint(x: 0.47, y: 0.885)
    static let paddleLowerRight = CGPoint(x: 0.53, y: 0.885)

    static let battery = CGPoint(x: 0.50, y: 0.97)
}

// MARK: - DualSense / DualSense Edge

enum DualSenseMinimapLayout {
    // The DualSense touchpad is large and subtly trapezoidal (top edge a
    // touch longer than the bottom). Width here is the TOP edge.
    static let touchpad = CGPoint(x: 0.50, y: 0.205)
    static let touchpadSize = CGSize(width: 0.33, height: 0.26)
    /// How far each bottom corner tucks inward (fraction of width).
    static let touchpadBottomTaper: CGFloat = 0.014

    static let create = CGPoint(x: 0.295, y: 0.12)
    static let options = CGPoint(x: 0.705, y: 0.12)
    static let createOptionsSize: CGFloat = 0.020

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

    /// Edge-only: back paddles peeking under the bottom V notch
    /// (the body's bottom arch sits at y ≈ 0.655).
    static let leftPaddle = CGPoint(x: 0.43, y: 0.735)
    static let rightPaddle = CGPoint(x: 0.57, y: 0.735)

    static let leftBumper = CGPoint(x: 0.20, y: 0.045)
    static let rightBumper = CGPoint(x: 0.80, y: 0.045)
    static let leftTrigger = CGPoint(x: 0.165, y: 0.01)
    static let rightTrigger = CGPoint(x: 0.835, y: 0.01)

    static let battery = CGPoint(x: 0.50, y: 0.90)
}

// MARK: - DualShock 4

enum DualShockMinimapLayout {
    static let touchpad = CGPoint(x: 0.50, y: 0.15)
    static let touchpadSize = CGSize(width: 0.32, height: 0.26)

    static let share = CGPoint(x: 0.28, y: 0.055)
    static let options = CGPoint(x: 0.72, y: 0.055)
    static let shareOptionsSize: CGFloat = 0.028

    static let dpad = CGPoint(x: 0.205, y: 0.21)
    static let dpadSize: CGFloat = 0.125

    static let faceCluster = CGPoint(x: 0.795, y: 0.21)
    static let faceButtonOffset: CGFloat = 0.060
    static let faceButtonSize: CGFloat = 0.052

    static let leftStick = CGPoint(x: 0.355, y: 0.39)
    static let rightStick = CGPoint(x: 0.645, y: 0.39)
    static let stickWellSize: CGFloat = 0.155

    static let speakerGrille = CGPoint(x: 0.50, y: 0.315)
    static let psButton = CGPoint(x: 0.50, y: 0.405)
    static let psButtonSize: CGFloat = 0.048

    static let leftBumper = CGPoint(x: 0.155, y: 0.052)
    static let rightBumper = CGPoint(x: 0.845, y: 0.052)
    static let leftTrigger = CGPoint(x: 0.155, y: 0.008)
    static let rightTrigger = CGPoint(x: 0.845, y: 0.008)

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
    static let dpad = CGPoint(x: 0.20, y: 0.155)
    static let dpadSize: CGFloat = 0.115

    static let view = CGPoint(x: 0.345, y: 0.10)
    static let menu = CGPoint(x: 0.655, y: 0.10)
    static let viewMenuSize: CGFloat = 0.040

    static let guide = CGPoint(x: 0.50, y: 0.14)
    static let guideSize: CGFloat = 0.062

    static let faceCluster = CGPoint(x: 0.80, y: 0.155)
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

    // Bumpers hug the flat top edge just inboard of the rounded corner
    // (body edge is at y ≈ 0.02 for x ≥ 0.18); triggers peek over the
    // corner itself, outboard of and above the d-pad / face clusters.
    static let leftBumper = CGPoint(x: 0.19, y: 0.020)
    static let rightBumper = CGPoint(x: 0.81, y: 0.020)
    static let leftTrigger = CGPoint(x: 0.12, y: 0.014)
    static let rightTrigger = CGPoint(x: 0.88, y: 0.014)

    // Rear grip buttons peeking under the bottom arches beside the
    // center cusp.
    static let gripUpperLeft = CGPoint(x: 0.32, y: 0.845)
    static let gripUpperRight = CGPoint(x: 0.68, y: 0.845)
    static let gripLowerLeft = CGPoint(x: 0.40, y: 0.925)
    static let gripLowerRight = CGPoint(x: 0.60, y: 0.925)

    static let battery = CGPoint(x: 0.50, y: 0.90)
}


// MARK: - 8BitDo Zero 2

/// Keychain-sized pad: d-pad + face diamond + select/start only.
/// No sticks, no triggers, no guide button.
enum EightBitDoZero2MinimapLayout {
    static let dpad = CGPoint(x: 0.195, y: 0.46)
    static let dpadSize: CGFloat = 0.20

    static let faceCluster = CGPoint(x: 0.685, y: 0.40)
    static let faceButtonOffset: CGFloat = 0.095
    static let faceButtonSize: CGFloat = 0.085

    static let select = CGPoint(x: 0.375, y: 0.70)
    static let start = CGPoint(x: 0.46, y: 0.70)
    static let selectStartSize: CGFloat = 0.066

    static let leftBumper = CGPoint(x: 0.26, y: 0.03)
    static let rightBumper = CGPoint(x: 0.74, y: 0.03)

    static let battery = CGPoint(x: 0.50, y: 0.87)
}

// MARK: - 8BitDo Micro

/// Zero 2 successor: adds digital L2/R2 on the top edge, a home (guide)
/// button, and a profile (star) button. Still no sticks.
enum EightBitDoMicroMinimapLayout {
    static let dpad = CGPoint(x: 0.175, y: 0.47)
    static let dpadSize: CGFloat = 0.24

    static let minus = CGPoint(x: 0.355, y: 0.235)
    static let plus = CGPoint(x: 0.545, y: 0.235)
    static let minusPlusSize: CGFloat = 0.05

    static let star = CGPoint(x: 0.43, y: 0.72)
    static let home = CGPoint(x: 0.545, y: 0.72)
    static let starHomeSize: CGFloat = 0.062

    static let faceCluster = CGPoint(x: 0.755, y: 0.42)
    static let faceButtonOffset: CGFloat = 0.092
    static let faceButtonSize: CGFloat = 0.083

    // Top edge, outer to inner: L, L2 ... R2, R
    static let leftBumper = CGPoint(x: 0.16, y: 0.02)
    static let rightBumper = CGPoint(x: 0.84, y: 0.02)
    static let leftTrigger = CGPoint(x: 0.33, y: 0.005)
    static let rightTrigger = CGPoint(x: 0.67, y: 0.005)

    static let battery = CGPoint(x: 0.50, y: 0.88)
}

// MARK: - 8BitDo Lite 2

/// Switch-Lite-style compact pad: low-profile sticks (left upper, right
/// lower-center), d-pad lower-left, full shoulder set, home + profile.
enum EightBitDoLite2MinimapLayout {
    static let leftStick = CGPoint(x: 0.155, y: 0.39)
    static let rightStick = CGPoint(x: 0.63, y: 0.66)
    static let stickWellSize: CGFloat = 0.155

    static let dpad = CGPoint(x: 0.315, y: 0.66)
    static let dpadSize: CGFloat = 0.155

    static let minus = CGPoint(x: 0.345, y: 0.20)
    static let plus = CGPoint(x: 0.575, y: 0.20)
    static let minusPlusSize: CGFloat = 0.042

    /// Decorative S/D mode switch between minus and plus.
    static let modeSwitch = CGPoint(x: 0.46, y: 0.155)

    static let faceCluster = CGPoint(x: 0.745, y: 0.325)
    static let faceButtonOffset: CGFloat = 0.063
    static let faceButtonSize: CGFloat = 0.052

    static let star = CGPoint(x: 0.105, y: 0.79)
    static let home = CGPoint(x: 0.815, y: 0.595)
    static let starHomeSize: CGFloat = 0.045

    static let leftBumper = CGPoint(x: 0.19, y: 0.025)
    static let rightBumper = CGPoint(x: 0.81, y: 0.025)
    static let leftTrigger = CGPoint(x: 0.13, y: 0.005)
    static let rightTrigger = CGPoint(x: 0.87, y: 0.005)

    static let battery = CGPoint(x: 0.50, y: 0.90)
}

// MARK: - 8BitDo Lite SE

/// Accessibility model: every control sits on the face for flat use.
/// Shoulders and stick clicks are face buttons; d-pad is four separate
/// round buttons; both sticks sit bottom-center.
enum EightBitDoLiteSEMinimapLayout {
    static let l2 = CGPoint(x: 0.205, y: 0.155)
    static let minus = CGPoint(x: 0.345, y: 0.155)
    static let plus = CGPoint(x: 0.655, y: 0.15)
    static let r2 = CGPoint(x: 0.79, y: 0.15)
    static let l1 = CGPoint(x: 0.27, y: 0.30)
    static let r1 = CGPoint(x: 0.73, y: 0.30)
    static let faceRowSize: CGFloat = 0.055

    static let dpadUp = CGPoint(x: 0.155, y: 0.30)
    static let dpadLeft = CGPoint(x: 0.085, y: 0.45)
    static let dpadRight = CGPoint(x: 0.225, y: 0.45)
    static let dpadDown = CGPoint(x: 0.155, y: 0.60)

    static let l3 = CGPoint(x: 0.435, y: 0.42)
    static let r3 = CGPoint(x: 0.565, y: 0.42)
    static let stickClickSize: CGFloat = 0.05

    static let faceCluster = CGPoint(x: 0.865, y: 0.45)
    static let faceButtonOffset: CGFloat = 0.07
    static let faceButtonSize: CGFloat = 0.055

    static let leftStick = CGPoint(x: 0.345, y: 0.72)
    static let rightStick = CGPoint(x: 0.655, y: 0.72)
    static let stickWellSize: CGFloat = 0.14

    static let star = CGPoint(x: 0.075, y: 0.83)
    static let home = CGPoint(x: 0.925, y: 0.83)
    static let starHomeSize: CGFloat = 0.04

    static let battery = CGPoint(x: 0.50, y: 0.92)
}
