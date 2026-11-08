import Foundation
import CoreGraphics
import GameController
import IOKit.hid

/// Serial queue for pointer mode transitions (engage's ~0.5s paced IR init and
/// disengage's teardown must never interleave), with a generation counter so
/// a superseded engage aborts between writes instead of finishing late and
/// leaving the remote streaming while disengaged.
nonisolated private let wiimotePointerModeQueue = DispatchQueue(label: "com.controllerkeys.wiimote-pointer-mode", qos: .userInitiated)

nonisolated private final class WiimoteModeGeneration: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }

    func isCurrent(_ generation: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value == generation
    }
}

nonisolated private let wiimoteModeGeneration = WiimoteModeGeneration()

/// Matches 0x22 acknowledgements (delivered on the HID thread) to the
/// output report the pointer-mode queue is waiting on, so camera bring-up
/// can confirm each write instead of hoping it landed.
nonisolated final class WiimoteAckWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private let signal = DispatchSemaphore(value: 0)
    private var device: IOHIDDevice?
    private var reportID: UInt8?
    private var errorCode: UInt8?

    func arm(device: IOHIDDevice, reportID: UInt8) {
        // Drain a stale signal from an ack that matched as a wait timed out.
        while signal.wait(timeout: .now()) == .success {}
        lock.withLock {
            self.device = device
            self.reportID = reportID
            errorCode = nil
        }
    }

    func deliver(device: IOHIDDevice, reportID: UInt8, errorCode: UInt8) {
        let matched = lock.withLock { () -> Bool in
            guard self.reportID == reportID, self.device == device else { return false }
            self.reportID = nil
            self.device = nil
            self.errorCode = errorCode
            return true
        }
        if matched { signal.signal() }
    }

    /// The acknowledged result code, or nil if no ack arrived in time.
    func wait(timeout: TimeInterval) -> UInt8? {
        if signal.wait(timeout: .now() + timeout) == .timedOut {
            lock.withLock {
                reportID = nil
                device = nil
            }
            return nil
        }
        return lock.withLock { errorCode }
    }
}

nonisolated private let wiimoteAckWaiter = WiimoteAckWaiter()

/// IR pointer state for the current pointer session, shared between
/// HID-thread reports.
nonisolated final class WiimotePointerState: @unchecked Sendable {
    /// With IR aiming on, tilt may steer only if the sensor bar hasn't been
    /// seen by this long after engaging (camera bring-up takes ~0.5s). Once
    /// IR has been seen, losing it holds the cursor — tilt never takes over.
    static let tiltSettleInterval: TimeInterval = 1.0

    private let lock = NSLock()
    private var tracker = WiimoteIRTracker()
    private var sessionStart: TimeInterval = 0
    private var cachedScreenBounds: CGRect?

    /// Cursor delta for one report's IR blobs (nil = don't move). Screen
    /// bounds are cached per session so the ~100 Hz path doesn't query
    /// CoreGraphics per report.
    func irDelta(
        points: [WiimoteIRPoint],
        baseAlpha: CGFloat,
        gain: CGFloat,
        at time: TimeInterval = ProcessInfo.processInfo.systemUptime,
        bounds: CGRect? = nil,
        currentCursor: (() -> CGPoint)? = nil
    ) -> CGPoint? {
        lock.lock()
        defer { lock.unlock() }
        let screen = bounds ?? cachedScreenBounds ?? CGDisplayBounds(CGMainDisplayID())
        cachedScreenBounds = screen
        let blobs = points.map {
            WiimoteIRTracker.Blob(point: CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)), size: $0.size)
        }
        return tracker.update(
            blobs: blobs,
            at: time,
            baseAlpha: baseAlpha,
            gain: gain,
            bounds: screen,
            currentCursor: currentCursor ?? {
                CGEvent(source: nil)?.location ?? CGPoint(x: screen.midX, y: screen.midY)
            }
        )
    }

    /// One NDJSON line per engaged report for the diagnostic trace: raw
    /// blobs, the tracker's smoothed aim and cursor target, and which input
    /// steered (ir / tilt / hold).
    func traceLine(time: TimeInterval, points: [WiimoteIRPoint]?, mode: String) -> String {
        lock.lock()
        let aim = tracker.lastAim
        let target = tracker.lastTarget
        let screen = cachedScreenBounds
        lock.unlock()
        func pair(_ p: CGPoint?) -> String {
            p.map { String(format: "[%.1f,%.1f]", $0.x, $0.y) } ?? "null"
        }
        let blobs = (points ?? []).map { "[\($0.x),\($0.y),\($0.size)]" }.joined(separator: ",")
        let screenText = screen.map { String(format: "[%.0f,%.0f,%.0f,%.0f]", $0.minX, $0.minY, $0.width, $0.height) } ?? "null"
        return String(format: "{\"t\":%.3f,", time)
            + "\"mode\":\"\(mode)\",\"blobs\":[\(blobs)],\"aim\":\(pair(aim)),\"target\":\(pair(target)),\"screen\":\(screenText)}\n"
    }

    func tiltAllowed(irEnabled: Bool, now: TimeInterval) -> Bool {
        guard irEnabled else { return true }
        lock.lock()
        defer { lock.unlock() }
        return !tracker.hasSeenIR && now - sessionStart >= Self.tiltSettleInterval
    }

    func reset(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        lock.lock()
        tracker = WiimoteIRTracker()
        sessionStart = time
        cachedScreenBounds = nil
        lock.unlock()
    }
}

nonisolated private let wiimotePointerState = WiimotePointerState()

/// Opt-in IR pointer trace (`wiimoteIRTraceLogging` default) appended to
/// /tmp/controllerkeys-wii-ir-trace.ndjson off the HID thread — raw blobs
/// plus the resulting aim/target, for diagnosing pointing from real data.
nonisolated private final class WiimoteIRTraceWriter: @unchecked Sendable {
    static let path = "/tmp/controllerkeys-wii-ir-trace.ndjson"
    private let queue = DispatchQueue(label: "com.controllerkeys.wiimote-ir-trace", qos: .utility)
    private var handle: FileHandle?

    func append(_ line: String) {
        queue.async {
            if self.handle == nil {
                if !FileManager.default.fileExists(atPath: Self.path) {
                    FileManager.default.createFile(atPath: Self.path, contents: nil)
                }
                self.handle = FileHandle(forWritingAtPath: Self.path)
                self.handle?.seekToEndOfFile()
            }
            self.handle?.write(Data(line.utf8))
        }
    }
}

nonisolated private let wiimoteIRTraceWriter = WiimoteIRTraceWriter()

@MainActor
extension ControllerService {
    // MARK: Pointer (tilt/IR mouse via the mapped Pointer (Hold) action)

    /// Pointer tuning, user-adjustable in the Wii Remote settings tab.
    /// UserDefaults is thread-safe and internally cached — fine at 100 Hz.
    nonisolated private static func wiimoteTuning(_ key: String, default defaultValue: Double) -> Double {
        let value = UserDefaults.standard.double(forKey: key)
        return value == 0 ? defaultValue : value
    }

    nonisolated static let wiimoteIRTraceKey = "wiimoteIRTraceLogging"

    /// Default-true boolean toggle (UserDefaults returns false for unset keys).
    nonisolated private static func wiimoteFlag(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil
            ? true
            : UserDefaults.standard.bool(forKey: key)
    }

    /// Quadratic response: gentle tilts give fine control, hard tilts sprint.
    nonisolated private static func wiimoteTiltVelocity(_ g: Float, maxPerReport: Float, deadzone: Float) -> CGFloat {
        let magnitude = abs(g)
        guard magnitude > deadzone else { return 0 }
        let normalized = min(1.0, (magnitude - deadzone) / (1.0 - deadzone))
        let speed = normalized * normalized * maxPerReport
        return CGFloat(g < 0 ? -speed : speed)
    }

    /// IR aiming (see WiimoteIRTracker), delivered as moves through the
    /// MAPPING ENGINE's simulator so held mapped clicks turn them into drags.
    nonisolated private func moveWiimotePointerByIR(_ points: [WiimoteIRPoint], at time: TimeInterval) {
        guard let delta = wiimotePointerState.irDelta(
            points: points,
            baseAlpha: CGFloat(Self.wiimoteTuning(Config.wiimoteIRSmoothingKey, default: 0.25)),
            gain: CGFloat(Self.wiimoteTuning(Config.wiimoteIRSpeedKey, default: 1.0)),
            at: time
        ) else { return }
        if abs(delta.x) > 0.01 || abs(delta.y) > 0.01 {
            wiimotePointerSimulator?.moveMouse(dx: delta.x, dy: delta.y)
        }
    }

    /// Engine-facing engage/disengage for the mapped "Pointer (Hold)" action.
    /// Idempotent; any button bound to the action can drive it.
    func setWiimotePointerEngaged(_ engaged: Bool) {
        let changed = storage.lock.withLock { () -> Bool in
            guard storage.wiimotePointerEngaged != engaged else { return false }
            storage.wiimotePointerEngaged = engaged
            return true
        }
        guard changed else { return }
        setWiimoteMotionReporting(engaged)
    }

    /// Switch the remote between on-change core buttons (0x30) and continuous
    /// buttons+accel+IR (0x33). Streaming runs only while the pointer is
    /// engaged. Engaging also runs the IR camera init sequence and starts a
    /// fresh pointer session (the next IR fix re-anchors aiming). Targets the
    /// pointer's session device (the active one), not merely the first
    /// registration.
    func setWiimoteMotionReporting(_ enabled: Bool) {
        wiimotePointerState.reset()
        guard let device = wiimoteHIDActiveDevice ?? wiimoteHIDRegistrations.first?.device else {
            _ = wiimoteModeGeneration.next()
            return
        }
        enqueueWiimotePointerMode(engaged: enabled, device: device)
        NSLog("[ControllerKeys] Wii Remote pointer %@", enabled ? "engaged" : "disengaged")
    }

    /// Enqueue a mode transition on the serial pointer-mode queue. The
    /// generation token lets a superseding transition abort an in-flight
    /// engage between its paced writes, so rapid press-release can never
    /// leave the remote streaming while disengaged (or vice versa).
    func enqueueWiimotePointerMode(engaged: Bool, device: IOHIDDevice) {
        let generation = wiimoteModeGeneration.next()
        wiimotePointerModeQueue.async {
            guard wiimoteModeGeneration.isCurrent(generation) else { return }
            if engaged {
                Self.initializeWiimoteIRCamera(device, generation: generation)
            } else {
                // Buttons-only reporting, then power the IR camera back down
                // (battery) — paced like bring-up, since back-to-back writes
                // get dropped and can leave the camera half powered.
                var session = WiimoteWriteSession(device: device, generation: generation)
                _ = session.send([0x12, 0x00, 0x30], awaitAck: false)
                    && session.send([0x13, 0x02])
                    && session.send([0x1A, 0x02])
            }
        }
    }

    /// WiiBrew IR camera bring-up, as the Wii itself does it (0x06 = enable
    /// + request ack; 0x01 then 0x08 to 0xB00030), with inio's high-
    /// sensitivity blocks so a sensor bar viewed off-axis (pitched up or
    /// down) stays bright enough to track, in extended-format mode 3.
    ///
    /// WiiBrew: bring-up lands in a random state (camera on but silent, or
    /// half sensitivity) unless every write is ≥50ms apart — the old 20ms
    /// pacing intermittently produced a dim, flickering camera. Each write is
    /// also confirmed by its 0x22 ack and retried on an error result. Aborts
    /// between steps if a newer mode transition superseded this one.
    nonisolated private static func initializeWiimoteIRCamera(_ device: IOHIDDevice, generation: Int) {
        var session = WiimoteWriteSession(device: device, generation: generation)
        guard session.send([0x13, 0x06]),                                 // IR pixel clock
              session.send([0x1A, 0x06]),                                 // IR logic
              session.send(registerWrite(0xB0_0030, [0x01])),
              session.send(registerWrite(0xB0_0000, [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x90, 0x00, 0x41])),
              session.send(registerWrite(0xB0_001A, [0x40, 0x00])),
              session.send(registerWrite(0xB0_0033, [0x03])),              // extended mode
              session.send(registerWrite(0xB0_0030, [0x08])),
              wiimoteModeGeneration.isCurrent(generation) else { return }
        sendWiimoteReport(device, [0x12, 0x04, 0x33])                     // continuous buttons+accel+IR
        NSLog("[ControllerKeys] Wii Remote IR camera ready (%d write retries%@)",
              session.retries, session.acksAvailable ? "" : ", acks unavailable")
    }

    /// Paced, ack-confirmed output-report writes for one mode transition.
    nonisolated private struct WiimoteWriteSession {
        static let stepGap: useconds_t = 55_000
        static let ackTimeout: TimeInterval = 0.12
        static let maxAttempts = 3

        let device: IOHIDDevice
        let generation: Int
        /// Cleared after a register-write ack times out — acks aren't
        /// arriving, so later steps fall back to pacing alone rather than
        /// stalling on every write.
        var acksAvailable = true
        var retries = 0

        /// Send `bytes`, wait for its ack (retrying on an error result), then
        /// pause before the next write. False once superseded.
        mutating func send(_ bytes: [UInt8], awaitAck: Bool = true) -> Bool {
            for attempt in 1...Self.maxAttempts {
                guard wiimoteModeGeneration.isCurrent(generation) else { return false }
                let waiting = awaitAck && acksAvailable
                if waiting { wiimoteAckWaiter.arm(device: device, reportID: bytes[0]) }
                ControllerService.sendWiimoteReport(device, bytes)
                let result = waiting ? wiimoteAckWaiter.wait(timeout: Self.ackTimeout) : 0
                usleep(Self.stepGap)
                guard let result else {
                    // Register writes (0x16) are always acked, so a missing
                    // one means acks aren't reaching us at all; 0x13/0x1A
                    // acks are only requested, so one going missing doesn't.
                    if bytes[0] == 0x16 { acksAvailable = false }
                    NSLog("[ControllerKeys] Wii Remote 0x%02X not acknowledged; continuing on pacing", bytes[0])
                    return true
                }
                if result == 0 { return true }
                NSLog("[ControllerKeys] Wii Remote 0x%02X rejected (error 0x%02X, attempt %d)", bytes[0], result, attempt)
                retries += 1
            }
            return true
        }
    }

    /// Report 0x16 register write: 0x04 = register space, 3-byte big-endian
    /// address, size byte, 16 data bytes (padded). Always acknowledged.
    nonisolated private static func registerWrite(_ address: UInt32, _ data: [UInt8]) -> [UInt8] {
        var bytes: [UInt8] = [
            0x16, 0x04,
            UInt8((address >> 16) & 0xFF), UInt8((address >> 8) & 0xFF), UInt8(address & 0xFF),
            UInt8(data.count),
        ]
        bytes += data
        bytes += [UInt8](repeating: 0, count: 16 - data.count)
        return bytes
    }

    /// Thread-agnostic output-report send (ID repeated as the buffer's first
    /// byte — Bluetooth HID quirk).
    nonisolated static func sendWiimoteReport(_ device: IOHIDDevice, _ bytes: [UInt8]) {
        guard let reportID = bytes.first else { return }
        let rc = bytes.withUnsafeBufferPointer { buf in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(reportID), buf.baseAddress!, buf.count)
        }
        if rc != kIOReturnSuccess {
            NSLog("[ControllerKeys] Wii Remote output report 0x%02X failed: 0x%08X", reportID, UInt32(bitPattern: rc))
        }
    }

    /// Parse a Wii Remote input report, diff the button mask, and emit
    /// edge-triggered presses.
    nonisolated func handleWiimoteHIDReport(device: IOHIDDevice, reportID: UInt32, report: UnsafeMutablePointer<UInt8>, length: Int) {
        if Self.hidDumpEnabled {
            Self.logChangedReport(reportID: reportID, report: report, length: length)
        }
        guard let parsed = WiimoteHIDParser().parse(
            reportID: reportID,
            report: UnsafePointer(report),
            length: length
        ) else { return }

        if let ackReportID = parsed.wiimoteAckReportID {
            wiimoteAckWaiter.deliver(device: device, reportID: ackReportID, errorCode: parsed.wiimoteAckError ?? 0)
            return
        }

        // Status reports (0x20) HALT all further data reporting until the
        // host re-sends the reporting mode (WiiBrew) — re-assert it for the
        // interface that delivered the report. Queued behind any in-flight
        // camera bring-up so it can't land between its register writes, and
        // reads the engagement state when it runs.
        if reportID == 0x20 {
            wiimotePointerModeQueue.async { [weak self] in
                guard let self else { return }
                let engaged = self.storage.lock.withLock { self.storage.wiimotePointerEngaged }
                Self.sendWiimoteReport(device, engaged ? [0x12, 0x04, 0x33] : [0x12, 0x00, 0x30])
            }
        }

        if let level = parsed.wiimoteBatteryLevel {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.wiimoteHIDActiveDevice != nil else { return }
                self.batteryLevel = level
                self.batteryState = .discharging
            }
        }

        guard let buttons = parsed.wiimoteButtons else { return }

        // One lock section serves the pointer-engagement read AND the button
        // diff, so both come from the same instant.
        let (pointerEngaged, changed): (Bool, WiimoteButtons) = storage.lock.withLock {
            let previous = WiimoteButtons(rawValue: storage.lastWiimoteButtons)
            let diff = WiimoteButtons(rawValue: previous.rawValue ^ buttons.rawValue)
            if !diff.isEmpty {
                storage.lastWiimoteButtons = buttons.rawValue
                storage.lastInputTime = CFAbsoluteTimeGetCurrent()
            }
            return (storage.wiimotePointerEngaged, diff)
        }

        // Pointer: while the mapped pointer action is engaged, IR aiming
        // drives the cursor when the camera sees the sensor bar. With IR on,
        // losing the bar holds the cursor still — tilt steers only if the bar
        // hasn't been seen at all this session. Signs assume the pointing
        // grip — face-up, IR end toward the screen.
        if pointerEngaged {
            let irEnabled = Self.wiimoteFlag(Config.wiimoteIREnabledKey)
            let tiltEnabled = Self.wiimoteFlag(Config.wiimoteTiltEnabledKey)
            let now = ProcessInfo.processInfo.systemUptime

            var mode = "hold"
            if irEnabled, let ir = parsed.wiimoteIRPoints, !ir.isEmpty {
                mode = "ir"
                moveWiimotePointerByIR(ir, at: now)
            } else if tiltEnabled,
                      wiimotePointerState.tiltAllowed(irEnabled: irEnabled, now: now),
                      let ax = parsed.wiimoteAccelX, let ay = parsed.wiimoteAccelY {
                let deadzone = Float(Self.wiimoteTuning(Config.wiimoteTiltDeadzoneKey, default: 0.12))
                let dx = Self.wiimoteTiltVelocity(
                    ax,
                    maxPerReport: Float(Self.wiimoteTuning(Config.wiimoteTiltRollSpeedKey, default: 30)),
                    deadzone: deadzone
                )
                let dy = Self.wiimoteTiltVelocity(
                    ay,
                    maxPerReport: Float(Self.wiimoteTuning(Config.wiimoteTiltPitchSpeedKey, default: 44)),
                    deadzone: deadzone
                )
                mode = "tilt"
                if dx != 0 || dy != 0 {
                    wiimotePointerSimulator?.moveMouse(dx: dx, dy: dy)
                }
            }
            if UserDefaults.standard.bool(forKey: Self.wiimoteIRTraceKey) {
                wiimoteIRTraceWriter.append(wiimotePointerState.traceLine(time: now, points: parsed.wiimoteIRPoints, mode: mode))
            }
        }

        guard !changed.isEmpty else { return }

        for entry in Self.wiimoteButtonMap where changed.contains(entry.wiimote) {
            let button = entry.button
            let pressed = buttons.contains(entry.wiimote)
			handleWiimoteInput(button: button, pressed: pressed)
        }
    }
}
