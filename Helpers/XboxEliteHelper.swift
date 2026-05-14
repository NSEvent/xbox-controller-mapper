#!/usr/bin/env swift
//
// XboxEliteHelper — Standalone HID monitor for Xbox Elite Series 2 controllers
//
// This tool runs as a separate process WITHOUT the GameController framework.
// When GameController.framework is active (via gamecontrollerd), macOS blocks
// IOKit HID access to the Elite Series 2 over BLE. By running in a separate
// process that doesn't link the framework, we can read raw HID events directly.
//
// Output: JSON lines to stdout for button state changes.
// Pass --guide-only when GameController already exposes paddles.
//   {"type":"guide","pressed":true}
//   {"type":"guide","pressed":false}
//   {"type":"paddle","index":1,"pressed":true}   (P1 = upper left)
//   {"type":"paddle","index":2,"pressed":true}   (P2 = upper right)
//   {"type":"paddle","index":3,"pressed":true}   (P3 = lower left)
//   {"type":"paddle","index":4,"pressed":true}   (P4 = lower right)
//
// Xbox Elite 2 Guide varies by connection/firmware:
//   Consumer Page 0x0223 = Classic Bluetooth Guide
//   Button Page 13 = BLE Guide unless the descriptor has extended buttons
//   Button Page 17 = USB Guide unless the device exposes Consumer AC Home
//
// Consumer Page 0x81 (4-bit bitmask for paddles):
//   bit 0 = P2 (upper right)
//   bit 1 = P4 (lower right)
//   bit 2 = P1 (upper left)
//   bit 3 = P3 (lower left)

import Foundation
import IOKit.hid

// MARK: - State

let shouldEmitPaddles = !CommandLine.arguments.contains("--guide-only")
let guideStalePressRecoveryInterval: TimeInterval = 2.0
var guidePressed = false
var guideLastEventTime: TimeInterval?
var paddleState: [Int: Bool] = [1: false, 2: false, 3: false, 4: false]
var knownDevices = Set<UnsafeMutableRawPointer>()
var devicesWithExtendedButtons = Set<UnsafeMutableRawPointer>()
var devicesWithACHome = Set<UnsafeMutableRawPointer>()

// Disable stdout buffering for immediate JSON line delivery
setbuf(stdout, nil)

func emit(_ json: String) {
    print(json)
}

func emitGuideEvent(pressed: Bool, now: TimeInterval = CFAbsoluteTimeGetCurrent()) {
	if pressed != guidePressed {
		guidePressed = pressed
		guideLastEventTime = now
		emit("{\"type\":\"guide\",\"pressed\":\(pressed)}")
		return
	}

	let eventGap = guideLastEventTime.map { now - $0 }
	guideLastEventTime = now
	if pressed, let eventGap, eventGap >= guideStalePressRecoveryInterval {
		guidePressed = false
		emit("{\"type\":\"guide\",\"pressed\":false}")
		guidePressed = true
		emit("{\"type\":\"guide\",\"pressed\":true}")
	}
}

// MARK: - HID Setup

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

// Match Microsoft controllers
let matching = [kIOHIDVendorIDKey: 0x045E] as CFDictionary
IOHIDManagerSetDeviceMatching(manager, matching)

// Elite Series 2 PIDs
let elitePIDs: Set<Int> = [0x0B00, 0x0B02, 0x0B05, 0x0B22]

func isEliteDevice(_ device: IOHIDDevice) -> Bool {
	let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
	return elitePIDs.contains(pid)
}

func guideTraits(for device: IOHIDDevice) -> (hasExtendedButtons: Bool, hasACHome: Bool) {
	guard let elements = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] else {
		return (false, false)
	}

	var maxButtonUsage: UInt32 = 0
	var hasACHome = false
	for element in elements {
		let usagePage = IOHIDElementGetUsagePage(element)
		if usagePage == UInt32(kHIDPage_Button) {
			let usage = IOHIDElementGetUsage(element)
			if usage > maxButtonUsage { maxButtonUsage = usage }
		} else if usagePage == UInt32(kHIDPage_Consumer) && IOHIDElementGetUsage(element) == 0x0223 {
			hasACHome = true
		}
	}

	return (maxButtonUsage > 15, hasACHome)
}

func cachedGuideTraits(for device: IOHIDDevice) -> (hasExtendedButtons: Bool, hasACHome: Bool) {
	let ptr = Unmanaged.passUnretained(device).toOpaque()
	if !knownDevices.contains(ptr) {
		let traits = guideTraits(for: device)
		knownDevices.insert(ptr)
		if traits.hasExtendedButtons {
			devicesWithExtendedButtons.insert(ptr)
		}
		if traits.hasACHome {
			devicesWithACHome.insert(ptr)
		}
	}

	return (devicesWithExtendedButtons.contains(ptr), devicesWithACHome.contains(ptr))
}

func eliteSessionGuideTraits() -> (hasExtendedButtons: Bool, hasACHome: Bool) {
	(!devicesWithExtendedButtons.isEmpty, !devicesWithACHome.isEmpty)
}

func effectiveGuideTraits(for device: IOHIDDevice) -> (hasExtendedButtons: Bool, hasACHome: Bool) {
	let traits = cachedGuideTraits(for: device)
	let sessionTraits = eliteSessionGuideTraits()
	return (
		traits.hasExtendedButtons || sessionTraits.hasExtendedButtons,
		traits.hasACHome || sessionTraits.hasACHome
	)
}

func isGuideEvent(usagePage: UInt32, usage: UInt32, hasExtendedButtons: Bool, hasACHome: Bool) -> Bool {
	if usagePage == UInt32(kHIDPage_Consumer) && usage == 0x0223 {
		return true
	}

	guard usagePage == UInt32(kHIDPage_Button) else { return false }

	if usage == 13 {
		return !hasExtendedButtons
	}
	if usage == 17 {
		return !hasACHome
	}
	return false
}

let inputCallback: IOHIDValueCallback = { _, _, _, value in
    let element = IOHIDValueGetElement(value)
    let usagePage = IOHIDElementGetUsagePage(element)
    let usage = IOHIDElementGetUsage(element)
    let intValue = IOHIDValueGetIntegerValue(value)
	let device = IOHIDElementGetDevice(element)

	guard isEliteDevice(device) else { return }

	let traits = effectiveGuideTraits(for: device)
	if isGuideEvent(
		usagePage: usagePage,
		usage: usage,
		hasExtendedButtons: traits.hasExtendedButtons,
		hasACHome: traits.hasACHome
	) {
        let pressed = intValue != 0
		emitGuideEvent(pressed: pressed)
    }

    // Paddles: Consumer Page, usage 0x81 (4-bit bitmask)
	if shouldEmitPaddles && usagePage == UInt32(kHIDPage_Consumer) && usage == 0x81 {
        let mask = intValue
        // Matches GCXboxGamepad convention: P1=upper left, P2=upper right, P3=lower left, P4=lower right
        let mapping: [(bit: Int, paddle: Int)] = [
            (2, 1),  // bit 2 = P1 (upper left)
            (0, 2),  // bit 0 = P2 (upper right)
            (3, 3),  // bit 3 = P3 (lower left)
            (1, 4),  // bit 1 = P4 (lower right)
        ]
        for (bit, paddle) in mapping {
            let pressed = (mask & (1 << bit)) != 0
            // Default to false on missing key — keeps the script alive if a
            // future paddle is added to the mapping above without being added
            // to paddleState below.
            if pressed != (paddleState[paddle] ?? false) {
                paddleState[paddle] = pressed
                emit("{\"type\":\"paddle\",\"index\":\(paddle),\"pressed\":\(pressed)}")
            }
        }
    }
}

let deviceCallback: IOHIDDeviceCallback = { _, _, _, device in
    let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
    if elitePIDs.contains(pid) {
		_ = cachedGuideTraits(for: device)
        // Signal to parent that we found an Elite controller
        emit("{\"type\":\"connected\",\"pid\":\(pid)}")
    }
}

IOHIDManagerRegisterInputValueCallback(manager, inputCallback, nil)
IOHIDManagerRegisterDeviceMatchingCallback(manager, deviceCallback, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

// Also register raw report callbacks on existing devices for robustness
if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
    for device in devices {
        let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        if elitePIDs.contains(pid) {
			_ = cachedGuideTraits(for: device)
            emit("{\"type\":\"connected\",\"pid\":\(pid)}")
        }
    }
}

// Signal ready
emit("{\"type\":\"ready\"}")

// Run forever
CFRunLoopRun()
