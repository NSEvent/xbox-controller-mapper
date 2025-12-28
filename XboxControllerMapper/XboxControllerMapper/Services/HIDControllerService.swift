import Foundation
import IOKit
import IOKit.hid
import Combine
import CoreGraphics

/// HID-based controller service that receives input even when app is backgrounded
@MainActor
class HIDControllerService: ObservableObject {
    @Published var isConnected = false
    @Published var controllerName: String = ""

    /// Currently pressed buttons
    @Published var activeButtons: Set<ControllerButton> = []

    /// Left joystick position (-1 to 1)
    @Published var leftStick: CGPoint = .zero

    /// Right joystick position (-1 to 1)
    @Published var rightStick: CGPoint = .zero

    /// Trigger values (0 to 1)
    @Published var leftTriggerValue: Float = 0
    @Published var rightTriggerValue: Float = 0

    // Button press timestamps for long-hold detection
    var buttonPressTimestamps: [ControllerButton: Date] = [:]

    // Callbacks
    var onButtonPressed: ((ControllerButton) -> Void)?
    var onButtonReleased: ((ControllerButton, TimeInterval) -> Void)?
    var onChordDetected: ((Set<ControllerButton>) -> Void)?

    // Chord detection
    private var chordTimer: Timer?
    private let chordWindow: TimeInterval = 0.05
    private var pendingButtons: Set<ControllerButton> = []

    // HID Manager
    private var hidManager: IOHIDManager?
    private var connectedDevice: IOHIDDevice?

    // HID usage mappings for Xbox controller
    private let buttonUsageMap: [Int: ControllerButton] = [
        1: .a,
        2: .b,
        4: .x,
        5: .y,
        7: .leftBumper,
        8: .rightBumper,
        11: .view,
        12: .menu,
        13: .xbox,
        14: .leftThumbstick,
        15: .rightThumbstick,
        16: .share
    ]

    init() {
        setupHIDManager()
    }

    deinit {
        if let manager = hidManager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    private func setupHIDManager() {
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        guard let manager = hidManager else {
            print("❌ Failed to create HID Manager")
            return
        }

        // Match Xbox controllers (and other game controllers)
        let matchingCriteria: [[String: Any]] = [
            // Xbox Controllers (various vendor/product IDs)
            [
                kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey: kHIDUsage_GD_GamePad
            ],
            [
                kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey: kHIDUsage_GD_Joystick
            ],
            [
                kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey: kHIDUsage_GD_MultiAxisController
            ]
        ]

        IOHIDManagerSetDeviceMatchingMultiple(manager, matchingCriteria as CFArray)

        // Set up callbacks
        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, result, sender, device in
            guard let context = context else { return }
            let service = Unmanaged<HIDControllerService>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                service.deviceConnected(device)
            }
        }, context)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, result, sender, device in
            guard let context = context else { return }
            let service = Unmanaged<HIDControllerService>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                service.deviceDisconnected(device)
            }
        }, context)

        IOHIDManagerRegisterInputValueCallback(manager, { context, result, sender, value in
            guard let context = context else { return }
            let service = Unmanaged<HIDControllerService>.fromOpaque(context).takeUnretainedValue()
            service.handleInputValue(value)
        }, context)

        // Schedule on a background run loop that keeps running
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            print("❌ Failed to open HID Manager: \(result)")
        } else {
            print("✅ HID Manager opened successfully")
        }
    }

    private func deviceConnected(_ device: IOHIDDevice) {
        connectedDevice = device

        // Get device name
        if let nameRef = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) {
            controllerName = nameRef as? String ?? "Game Controller"
        } else {
            controllerName = "Game Controller"
        }

        isConnected = true
        print("✅ HID Controller connected: \(controllerName)")
    }

    private func deviceDisconnected(_ device: IOHIDDevice) {
        if connectedDevice === device {
            connectedDevice = nil
            isConnected = false
            controllerName = ""
            activeButtons.removeAll()
            leftStick = .zero
            rightStick = .zero
            print("🎮 HID Controller disconnected")
        }
    }

    private func handleInputValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)

        // Handle based on usage page
        switch Int(usagePage) {
        case kHIDPage_Button:
            handleButton(usage: Int(usage), pressed: intValue != 0)

        case kHIDPage_GenericDesktop:
            handleGenericDesktop(usage: Int(usage), value: value, element: element)

        default:
            break
        }
    }

    private func handleButton(usage: Int, pressed: Bool) {
        guard let button = buttonUsageMap[usage] else { return }

        DispatchQueue.main.async { [weak self] in
            #if DEBUG
            print("🎮 HID Button: \(button.displayName) \(pressed ? "pressed" : "released")")
            #endif

            if pressed {
                self?.buttonPressed(button)
            } else {
                self?.buttonReleased(button)
            }
        }
    }

    private func handleGenericDesktop(usage: Int, value: IOHIDValue, element: IOHIDElement) {
        let intValue = IOHIDValueGetIntegerValue(value)
        let min = IOHIDElementGetLogicalMin(element)
        let max = IOHIDElementGetLogicalMax(element)

        // Normalize to -1...1 or 0...1 range
        let range = Double(max - min)
        let normalized = range > 0 ? (Double(intValue - min) / range) * 2.0 - 1.0 : 0.0

        DispatchQueue.main.async { [weak self] in
            switch usage {
            case kHIDUsage_GD_X: // Left stick X
                self?.leftStick.x = CGFloat(normalized)
            case kHIDUsage_GD_Y: // Left stick Y
                self?.leftStick.y = CGFloat(-normalized) // Invert Y
            case kHIDUsage_GD_Z: // Right stick X or Left Trigger
                // Xbox controllers use Z for left trigger
                let triggerValue = Float((normalized + 1.0) / 2.0)
                self?.leftTriggerValue = triggerValue
                if triggerValue > 0.1 {
                    self?.handleTriggerAsButton(.leftTrigger, pressed: true)
                } else {
                    self?.handleTriggerAsButton(.leftTrigger, pressed: false)
                }
            case kHIDUsage_GD_Rx: // Right stick X
                self?.rightStick.x = CGFloat(normalized)
            case kHIDUsage_GD_Ry: // Right stick Y
                self?.rightStick.y = CGFloat(-normalized) // Invert Y
            case kHIDUsage_GD_Rz: // Right Trigger
                let triggerValue = Float((normalized + 1.0) / 2.0)
                self?.rightTriggerValue = triggerValue
                if triggerValue > 0.1 {
                    self?.handleTriggerAsButton(.rightTrigger, pressed: true)
                } else {
                    self?.handleTriggerAsButton(.rightTrigger, pressed: false)
                }
            case kHIDUsage_GD_Hatswitch: // D-pad
                self?.handleDPad(value: Int(intValue))
            default:
                break
            }
        }
    }

    private func handleTriggerAsButton(_ button: ControllerButton, pressed: Bool) {
        let wasPressed = activeButtons.contains(button)
        if pressed && !wasPressed {
            buttonPressed(button)
        } else if !pressed && wasPressed {
            buttonReleased(button)
        }
    }

    private func handleDPad(value: Int) {
        // D-pad is typically a hat switch with values 0-7 (8 directions) or -1/15 for center
        // 0=N, 1=NE, 2=E, 3=SE, 4=S, 5=SW, 6=W, 7=NW

        // Release all d-pad buttons first
        let dpadButtons: [ControllerButton] = [.dpadUp, .dpadRight, .dpadDown, .dpadLeft]
        for button in dpadButtons {
            if activeButtons.contains(button) {
                buttonReleased(button)
            }
        }

        // Press appropriate buttons based on hat switch value
        switch value {
        case 0: // N
            buttonPressed(.dpadUp)
        case 1: // NE
            buttonPressed(.dpadUp)
            buttonPressed(.dpadRight)
        case 2: // E
            buttonPressed(.dpadRight)
        case 3: // SE
            buttonPressed(.dpadDown)
            buttonPressed(.dpadRight)
        case 4: // S
            buttonPressed(.dpadDown)
        case 5: // SW
            buttonPressed(.dpadDown)
            buttonPressed(.dpadLeft)
        case 6: // W
            buttonPressed(.dpadLeft)
        case 7: // NW
            buttonPressed(.dpadUp)
            buttonPressed(.dpadLeft)
        default: // Center or invalid
            break
        }
    }

    private func buttonPressed(_ button: ControllerButton) {
        guard !activeButtons.contains(button) else { return }

        activeButtons.insert(button)
        buttonPressTimestamps[button] = Date()

        pendingButtons.insert(button)

        chordTimer?.invalidate()
        let timer = Timer(timeInterval: chordWindow, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.processChordOrSinglePress()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        chordTimer = timer
    }

    private func buttonReleased(_ button: ControllerButton) {
        guard activeButtons.contains(button) else { return }

        activeButtons.remove(button)

        let holdDuration: TimeInterval
        if let pressTime = buttonPressTimestamps[button] {
            holdDuration = Date().timeIntervalSince(pressTime)
        } else {
            holdDuration = 0
        }

        buttonPressTimestamps.removeValue(forKey: button)
        pendingButtons.remove(button)

        onButtonReleased?(button, holdDuration)
    }

    private func processChordOrSinglePress() {
        if pendingButtons.count >= 2 {
            onChordDetected?(pendingButtons)
        } else if let button = pendingButtons.first {
            onButtonPressed?(button)
        }
        pendingButtons.removeAll()
    }
}

