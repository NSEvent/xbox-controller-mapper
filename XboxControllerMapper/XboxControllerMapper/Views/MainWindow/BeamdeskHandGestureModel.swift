import SceneKit

enum BeamdeskHandSide: String, Equatable {
  case left
  case right

  /// Sign used to mirror Meta's gesture semantics between physical hands.
  var inwardSign: CGFloat { self == .left ? 1 : -1 }

  /// First-person profile sign: left-hand thumb outside-left, right outside-right.
  var profileSign: CGFloat { -inwardSign }

  var displayName: String { self == .left ? "LEFT HAND" : "RIGHT HAND" }
}

enum BeamdeskMicrogesture: String, Equatable {
  case swipeLeft
  case swipeRight
  case swipeForward
  case swipeBack
  case thumbTap

  var displayName: String {
    switch self {
    case .swipeLeft: return "SWIPE LEFT"
    case .swipeRight: return "SWIPE RIGHT"
    case .swipeForward: return "SWIPE FORWARD"
    case .swipeBack: return "SWIPE BACK"
    case .thumbTap: return "THUMB TAP"
    }
  }

  var systemImage: String {
    switch self {
    case .swipeLeft: return "arrow.left"
    case .swipeRight: return "arrow.right"
    case .swipeForward: return "arrow.up"
    case .swipeBack: return "arrow.down"
    case .thumbTap: return "hand.tap.fill"
    }
  }
}

struct BeamdeskThumbArticulation: Equatable {
  let cmcFlex: CGFloat
  let mcpFlex: CGFloat
  let ipFlex: CGFloat
  let lateralSweep: CGFloat

  static let rest = Self(cmcFlex: -0.04, mcpFlex: 0.08, ipFlex: 0.10, lateralSweep: 0)
  static let contact = Self(cmcFlex: 0.22, mcpFlex: 0.44, ipFlex: 0.38, lateralSweep: 0)
  static let tap = Self(cmcFlex: 0.42, mcpFlex: 0.76, ipFlex: 0.68, lateralSweep: 0)
  // Depth slides keep the column upright so it stays readable against the
  // fist directly behind it; the push is carried by the distal hook alone.
  static let slide = Self(cmcFlex: 0.10, mcpFlex: 0.18, ipFlex: 0.54, lateralSweep: 0)
  static let slideLeft = Self(
    cmcFlex: 0.22, mcpFlex: 0.44, ipFlex: 0.38, lateralSweep: 0.72)
  static let slideRight = Self(
    cmcFlex: 0.22, mcpFlex: 0.44, ipFlex: 0.38, lateralSweep: -0.72)
  static let outwardLeft = Self(
    cmcFlex: 0.22, mcpFlex: 0.44, ipFlex: 0.38, lateralSweep: 0.34)
  static let outwardRight = Self(
    cmcFlex: 0.22, mcpFlex: 0.44, ipFlex: 0.38, lateralSweep: -0.34)
}

@MainActor
struct BeamdeskGesturePresentation: Equatable {
  let side: BeamdeskHandSide
  let gesture: BeamdeskMicrogesture

  init?(button: ControllerButton) {
    switch button {
    case .beamdeskLeftSwipeLeft:
      self.init(side: .left, gesture: .swipeLeft)
    case .beamdeskLeftSwipeRight:
      self.init(side: .left, gesture: .swipeRight)
    case .beamdeskLeftSwipeForward:
      self.init(side: .left, gesture: .swipeForward)
    case .beamdeskLeftSwipeBack:
      self.init(side: .left, gesture: .swipeBack)
    case .beamdeskLeftThumbTap:
      self.init(side: .left, gesture: .thumbTap)
    case .beamdeskRightSwipeLeft:
      self.init(side: .right, gesture: .swipeLeft)
    case .beamdeskRightSwipeRight:
      self.init(side: .right, gesture: .swipeRight)
    case .beamdeskRightSwipeForward:
      self.init(side: .right, gesture: .swipeForward)
    case .beamdeskRightSwipeBack:
      self.init(side: .right, gesture: .swipeBack)
    case .beamdeskRightThumbTap:
      self.init(side: .right, gesture: .thumbTap)
    default:
      return nil
    }
  }

  init(side: BeamdeskHandSide, gesture: BeamdeskMicrogesture) {
    self.side = side
    self.gesture = gesture
  }

  static func active(in buttons: Set<ControllerButton>) -> BeamdeskGesturePresentation? {
    ControllerButton.beamdeskHandButtons
      .first(where: buttons.contains)
      .flatMap(BeamdeskGesturePresentation.init(button:))
  }

  /// Screen-space motion used by the animated thumb root and motion trail.
  /// Horizontal gestures stay horizontal in the first-person preview. Depth
  /// gestures carry their direction in z but, under the orthographic camera,
  /// read through their y travel: forward climbs up along the curled index,
  /// back retreats down toward the wrist. The x drift is a slight
  /// along-the-index garnish that mirrors between hands; it stays small so
  /// the thumb glides over the knuckle stack instead of sinking into it.
  var thumbSlideOffset: SCNVector3 {
    let sign = side.inwardSign
    let horizontalTravel: CGFloat = isOutwardHorizontalSwipe ? 0.30 : 0.58
    switch gesture {
    case .swipeLeft:
      return SCNVector3(-horizontalTravel, 0, 0)
    case .swipeRight:
      return SCNVector3(horizontalTravel, 0, 0)
    case .swipeForward:
      return SCNVector3(sign * 0.12, 0.40, -0.50)
    case .swipeBack:
      return SCNVector3(sign * -0.12, -0.36, 0.50)
    case .thumbTap:
      return SCNVector3Zero
    }
  }

  var finalArticulation: BeamdeskThumbArticulation {
    switch gesture {
    case .thumbTap:
      return .tap
    case .swipeLeft:
      return isOutwardHorizontalSwipe ? .outwardLeft : .slideLeft
    case .swipeRight:
      return isOutwardHorizontalSwipe ? .outwardRight : .slideRight
    case .swipeForward, .swipeBack:
      return .slide
    }
  }

  private var isOutwardHorizontalSwipe: Bool {
    (side == .left && gesture == .swipeLeft)
      || (side == .right && gesture == .swipeRight)
  }
}
