#!/usr/bin/env swift
//
// XboxEliteHelper — Standalone HID monitor for Xbox Elite Series 2 controllers
//
// This tool runs as a separate process WITHOUT the GameController framework.
// When GameController.framework is active (via gamecontrollerd), macOS blocks
// IOKit HID access to the Elite Series 2 over BLE. By running in a separate
// process that doesn't link the framework, we can read raw HID events directly.
//
// Output: JSON lines to stdout for button state changes
//   {"type":"guide","pressed":true}
//   {"type":"guide","pressed":false}
//   {"type":"paddle","index":1,"pressed":true}   (P1 = upper left)
//   {"type":"paddle","index":2,"pressed":true}   (P2 = lower left)
//   {"type":"paddle","index":3,"pressed":true}   (P3 = upper right)
//   {"type":"paddle","index":4,"pressed":true}   (P4 = lower right)
//
// Xbox Elite 2 BLE HID Report ID 1 layout:
//   Byte 10: Buttons 1-8  (A, B, X, Y, LB, RB, View, Menu)
//   Byte 11: Buttons 9-15 + Consumer 0xB2
//     bit 4 = Button 13 (Guide)
//
// Consumer Page 0x81 (4-bit bitmask for paddles):
//   bit 0 = P3 (upper right)
//   bit 1 = P4 (lower right)
//   bit 2 = P1 (upper left)
//   bit 3 = P2 (lower left)

import Foundation
import IOKit.hid

// MARK: - State

var guidePressed = false
var paddleState: [Int: Bool] = [1: false, 2: false, 3: false, 4: false]

// Disable stdout buffering for immediate JSON line delivery
setbuf(stdout, nil)

func emit(_ json: String) {
    print(json)
}

// MARK: - HID Setup

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

// Match Microsoft controllers
let matching = [kIOHIDVendorIDKey: 0x045E] as CFDictionary
IOHIDManagerSetDeviceMatching(manager, matching)

// Elite Series 2 PIDs
let elitePIDs: Set<Int> = [0x0B00, 0x0B02, 0x0B05, 0x0B22]

let inputCallback: IOHIDValueCallback = { _, _, _, value in
    let element = IOHIDValueGetElement(value)
    let usagePage = IOHIDElementGetUsagePage(element)
    let usage = IOHIDElementGetUsage(element)
    let intValue = IOHIDValueGetIntegerValue(value)

    // Guide button: Button Page, usage 13
    if usagePage == UInt32(kHIDPage_Button) && usage == 13 {
        let pressed = intValue != 0
        if pressed != guidePressed {
            guidePressed = pressed
            emit("{\"type\":\"guide\",\"pressed\":\(pressed)}")
        }
    }

    // Paddles: Consumer Page, usage 0x81 (4-bit bitmask)
    if usagePage == UInt32(kHIDPage_Consumer) && usage == 0x81 {
        let mask = intValue
        let mapping: [(bit: Int, paddle: Int)] = [
            (2, 1),  // bit 2 = P1 (upper left)
            (3, 2),  // bit 3 = P2 (lower left)
            (0, 3),  // bit 0 = P3 (upper right)
            (1, 4),  // bit 1 = P4 (lower right)
        ]
        for (bit, paddle) in mapping {
            let pressed = (mask & (1 << bit)) != 0
            if pressed != paddleState[paddle]! {
                paddleState[paddle] = pressed
                emit("{\"type\":\"paddle\",\"index\":\(paddle),\"pressed\":\(pressed)}")
            }
        }
    }
}

let deviceCallback: IOHIDDeviceCallback = { _, _, _, device in
    let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
    if elitePIDs.contains(pid) {
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
            emit("{\"type\":\"connected\",\"pid\":\(pid)}")
        }
    }
}

// Signal ready
emit("{\"type\":\"ready\"}")

// Run forever
CFRunLoopRun()
