import Foundation
import Network
import AppKit
import CoreGraphics

final class UniversalControlMouseRelay: @unchecked Sendable {
    static let shared = UniversalControlMouseRelay()

    private struct RemoteCursorStatus {
        let point: CGPoint
        let bounds: CGRect
    }

    private let queue = DispatchQueue(label: "com.controllerkeys.uc-relay", qos: .userInteractive)
    private let port: NWEndpoint.Port = 38383
    private let lock = NSLock()

    private var listener: NWListener?
    private var incomingConnections: [NWConnection] = []
    private var incomingBuffers: [ObjectIdentifier: String] = [:]
    private var receiverInput: InputSimulatorProtocol?
    private var receiverSystemCommandExecutor: SystemCommandExecutor?
    private var client: NWConnection?
    private var clientHost: String?
    private var clientReceiveBuffer = ""
    private var remoteCursorStatus: RemoteCursorStatus?
    private var isRelayTarget = false
    private var isRemoteSessionActive = false
    private var remoteMouseButtonsHeld: Set<CGMouseButton> = []
    private var remoteMouseEventNumber: Int64 = 0
    private var remoteClickCounts: [CGMouseButton: Int64] = [:]
    private var remoteLastClickTime: [CGMouseButton: Date] = [:]
    private var didLogSendFailure = false
    private var didLogFirstSend = false
    private var didLogFirstReceive = false

    var canSendToRemote: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !isRelayTarget
    }

    var hasActiveRemoteSession: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRemoteSessionActive && !isRelayTarget
    }

    var isRoutingToRemote: Bool {
        hasActiveRemoteSession
    }

    func setRemoteSessionActive(_ active: Bool) {
        lock.lock()
        isRemoteSessionActive = active
        if !active {
            remoteCursorStatus = nil
        }
        lock.unlock()
    }

    func shouldReturnFromRemote(dx: Int, dy: Int, entryEdgeDirection: CGPoint) -> Bool {
        lock.lock()
        let status = remoteCursorStatus
        lock.unlock()
        guard let status else { return false }

        let exitDirection = CGPoint(x: -entryEdgeDirection.x, y: -entryEdgeDirection.y)
        if exitDirection.x > 0 {
            return dx > 0 && status.point.x >= status.bounds.maxX - 1
        } else if exitDirection.x < 0 {
            return dx < 0 && status.point.x <= status.bounds.minX
        } else if exitDirection.y > 0 {
            return dy > 0 && status.point.y >= status.bounds.maxY - 1
        } else if exitDirection.y < 0 {
            return dy < 0 && status.point.y <= status.bounds.minY
        }
        return false
    }

    private var defaultRemoteHost: String {
        UserDefaults.standard.string(forKey: "universalControlRelayHost") ?? "kmacstudio"
    }

    private var defaultRemotePort: NWEndpoint.Port {
        let rawValue = UserDefaults.standard.integer(forKey: "universalControlRelayPort")
        guard rawValue > 0, rawValue <= Int(UInt16.max),
              let port = NWEndpoint.Port(rawValue: UInt16(rawValue)) else {
            return self.port
        }
        return port
    }

    func startListening(
        inputSimulator: InputSimulatorProtocol,
        systemCommandExecutor: SystemCommandExecutor? = nil
    ) {
        lock.lock()
        receiverInput = inputSimulator
        receiverSystemCommandExecutor = systemCommandExecutor
        let alreadyListening = listener != nil
        lock.unlock()
        guard !alreadyListening else { return }

        let hostname = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        let relayTarget = hostname.localizedCaseInsensitiveContains("studio")
            || ProcessInfo.processInfo.hostName.localizedCaseInsensitiveContains("studio")

        lock.lock()
        isRelayTarget = relayTarget
        lock.unlock()

        do {
            let listener = try NWListener(using: .tcp, on: port)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleIncoming(connection)
            }
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    NSLog("[UCMouseRelay] Listener failed: %@", String(describing: error))
                }
            }

            lock.lock()
            self.listener = listener
            lock.unlock()

            listener.start(queue: queue)
            NSLog("[UCMouseRelay] Listening on TCP %d; relayTarget=%@", port.rawValue, relayTarget ? "true" : "false")
        } catch {
            NSLog("[UCMouseRelay] Could not listen on TCP %d: %@", port.rawValue, String(describing: error))
        }
    }

    func sendMove(dx: Int, dy: Int) -> Bool {
        guard canSendToRemote else { return false }
        guard dx != 0 || dy != 0 else { return true }
        setRemoteSessionActive(true)

        let message = "m \(dx) \(dy)\n"
        guard let data = message.data(using: .utf8) else { return false }
        let connection = ensureClient()

        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let error else { return }
            self?.logSendFailureOnce(error)
        })
        logFirstSend(dx: dx, dy: dy)
        return true
    }

    func sendKeyPress(_ keyCode: CGKeyCode, modifiers: CGEventFlags) -> Bool {
        sendLine("kp \(keyCode) \(modifiers.rawValue)")
    }

    func sendKeyDown(_ keyCode: CGKeyCode, modifiers: CGEventFlags) -> Bool {
        sendLine("kd \(keyCode) \(modifiers.rawValue)")
    }

    func sendKeyUp(_ keyCode: CGKeyCode) -> Bool {
        sendLine("ku \(keyCode)")
    }

    func sendHoldModifier(_ modifier: CGEventFlags) -> Bool {
        sendLine("hm \(modifier.rawValue)")
    }

    func sendReleaseModifier(_ modifier: CGEventFlags) -> Bool {
        sendLine("rm \(modifier.rawValue)")
    }

    func sendReleaseAllModifiers() -> Bool {
        sendLine("ra")
    }

    func sendSystemCommand(_ command: SystemCommand) -> Bool {
        guard hasActiveRemoteSession else { return false }
        do {
            let data = try JSONEncoder().encode(command)
            let encoded = data.base64EncodedString()
            return sendLine("sys \(encoded)")
        } catch {
            NSLog("[UCMouseRelay] Could not encode system command: %@", String(describing: error))
            return false
        }
    }

    func sendUIEvent(_ name: String, button: ControllerButton, holdMode: Bool = false) -> Bool {
        guard hasActiveRemoteSession else { return false }
        return sendLine("ui \(name) \(button.rawValue) \(holdMode ? 1 : 0)")
    }

    func sendCommandWheelUpdate(stick: CGPoint, alternateHeld: Bool) -> Bool {
        guard hasActiveRemoteSession else { return false }
        return sendLine("wheel \(Double(stick.x)) \(Double(stick.y)) \(alternateHeld ? 1 : 0)")
    }

    func sendScroll(
        dx: CGFloat,
        dy: CGFloat,
        phase: CGScrollPhase?,
        momentumPhase: CGMomentumScrollPhase?,
        isContinuous: Bool,
        flags: CGEventFlags
    ) -> Bool {
        let phaseRaw = phase.map { Int($0.rawValue) } ?? -1
        let momentumRaw = momentumPhase.map { Int($0.rawValue) } ?? -1
        return sendLine("sc \(Double(dx)) \(Double(dy)) \(phaseRaw) \(momentumRaw) \(isContinuous ? 1 : 0) \(flags.rawValue)")
    }

    func sendTypeText(_ text: String, speed: Int, pressEnter: Bool) -> Bool {
        let encoded = Data(text.utf8).base64EncodedString()
        return sendLine("tt \(encoded) \(speed) \(pressEnter ? 1 : 0)")
    }

    func sendFeedback(action: String, type: InputEventType, isHeld: Bool) -> Bool {
        guard hasActiveRemoteSession else { return false }
        let encoded = Data(action.utf8).base64EncodedString()
        let encodedType = Data(type.rawValue.utf8).base64EncodedString()
        return sendLine("fb \(encoded) \(encodedType) \(isHeld ? 1 : 0)")
    }

    func sendDismissFeedback(action: String?) -> Bool {
        guard hasActiveRemoteSession else { return false }
        let encoded = action.map { Data($0.utf8).base64EncodedString() } ?? "-"
        return sendLine("fd \(encoded)")
    }

    private func sendLine(_ line: String) -> Bool {
        guard canSendToRemote else { return false }
        guard let data = "\(line)\n".data(using: .utf8) else { return false }
        let connection = ensureClient()
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let error else { return }
            self?.logSendFailureOnce(error)
        })
        return true
    }

    private func ensureClient() -> NWConnection {
        let host = defaultRemoteHost
        let remotePort = defaultRemotePort
        let clientKey = "\(host):\(remotePort.rawValue)"

        lock.lock()
        if let client, clientHost == clientKey {
            lock.unlock()
            return client
        }
        lock.unlock()

        let connection = NWConnection(host: NWEndpoint.Host(host), port: remotePort, using: .tcp)
        connection.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                NSLog("[UCMouseRelay] Client failed: %@", String(describing: error))
            }
        }
        connection.start(queue: queue)
        receiveNextFromClient(on: connection)

        lock.lock()
        client = connection
        clientHost = clientKey
        didLogSendFailure = false
        didLogFirstSend = false
        lock.unlock()

        NSLog("[UCMouseRelay] Sending to %@:%d", host, remotePort.rawValue)
        return connection
    }

    private func receiveNextFromClient(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection else { return }
            if let error {
                NSLog("[UCMouseRelay] Client receive failed: %@", String(describing: error))
                return
            }
            if let data, !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                appendClientIncoming(text)
            }
            if !isComplete {
                receiveNextFromClient(on: connection)
            }
        }
    }

    private func appendClientIncoming(_ text: String) {
        var lines: [String] = []
        lock.lock()
        clientReceiveBuffer += text
        while let newline = clientReceiveBuffer.firstIndex(of: "\n") {
            lines.append(String(clientReceiveBuffer[..<newline]))
            clientReceiveBuffer.removeSubrange(...newline)
        }
        lock.unlock()

        for line in lines {
            handleClient(line: line)
        }
    }

    private func handleIncoming(_ connection: NWConnection) {
        lock.lock()
        incomingConnections.append(connection)
        incomingBuffers[ObjectIdentifier(connection)] = ""
        lock.unlock()

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let connection else { return }
            if case .failed(let error) = state {
                NSLog("[UCMouseRelay] Receive connection failed: %@", String(describing: error))
                self?.removeIncoming(connection)
            } else if case .cancelled = state {
                self?.removeIncoming(connection)
            }
        }
        connection.start(queue: queue)
        receiveNext(on: connection)
    }

    private func receiveNext(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection else { return }
            if let error {
                NSLog("[UCMouseRelay] Receive failed: %@", String(describing: error))
                removeIncoming(connection)
                return
            }
            if let data, !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                appendIncoming(text, from: connection)
            }
            if isComplete {
                removeIncoming(connection)
            } else {
                receiveNext(on: connection)
            }
        }
    }

    private func appendIncoming(_ text: String, from connection: NWConnection) {
        let key = ObjectIdentifier(connection)

        lock.lock()
        var buffer = (incomingBuffers[key] ?? "") + text
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: "\n") {
            lines.append(String(buffer[..<newline]))
            buffer.removeSubrange(...newline)
        }
        incomingBuffers[key] = buffer
        lock.unlock()

        for line in lines {
            handle(line: line, from: connection)
        }
    }

    private func removeIncoming(_ connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        lock.lock()
        incomingConnections.removeAll { $0 === connection }
        incomingBuffers.removeValue(forKey: key)
        lock.unlock()
    }

    private func handle(line: String, from connection: NWConnection) {
        let parts = line.split(separator: " ")
        guard let command = parts.first else {
            return
        }

        lock.lock()
        let input = receiverInput
        let systemCommandExecutor = receiverSystemCommandExecutor
        let relayTarget = isRelayTarget
        let hasMouseButtonHeld = !remoteMouseButtonsHeld.isEmpty
        lock.unlock()

        switch command {
        case "m":
            guard parts.count == 3,
                  let dx = Int(parts[1]),
                  let dy = Int(parts[2]) else { return }
            if relayTarget && !hasMouseButtonHeld {
                warpRemoteMouse(dx: dx, dy: dy)
            } else if relayTarget {
                postRemoteMouseDrag(dx: dx, dy: dy)
            } else {
                input?.moveMouseNative(dx: dx, dy: dy)
            }
            if relayTarget {
                sendRemoteCursorStatus(on: connection)
            }
            logFirstReceive("move dx=\(dx) dy=\(dy)")
        case "kp":
            guard parts.count == 3,
                  let keyCode = UInt16(parts[1]),
                  let flagsRaw = UInt64(parts[2]) else { return }
            if relayTarget && KeyCodeMapping.isMouseButton(CGKeyCode(keyCode)) {
                postRemoteMouseButton(keyCode: CGKeyCode(keyCode), down: true)
                postRemoteMouseButton(keyCode: CGKeyCode(keyCode), down: false)
            } else {
                input?.pressKey(CGKeyCode(keyCode), modifiers: CGEventFlags(rawValue: flagsRaw))
            }
            logFirstReceive("key press \(keyCode)")
        case "kd":
            guard parts.count == 3,
                  let keyCode = UInt16(parts[1]),
                  let flagsRaw = UInt64(parts[2]) else { return }
            if relayTarget && KeyCodeMapping.isMouseButton(CGKeyCode(keyCode)) {
                postRemoteMouseButton(keyCode: CGKeyCode(keyCode), down: true)
            } else {
                updateRemoteMouseButtonState(keyCode: CGKeyCode(keyCode), isDown: true)
                input?.keyDown(CGKeyCode(keyCode), modifiers: CGEventFlags(rawValue: flagsRaw))
            }
            logFirstReceive("key down \(keyCode)")
        case "ku":
            guard parts.count == 2,
                  let keyCode = UInt16(parts[1]) else { return }
            if relayTarget && KeyCodeMapping.isMouseButton(CGKeyCode(keyCode)) {
                postRemoteMouseButton(keyCode: CGKeyCode(keyCode), down: false)
            } else {
                updateRemoteMouseButtonState(keyCode: CGKeyCode(keyCode), isDown: false)
                input?.keyUp(CGKeyCode(keyCode))
            }
            logFirstReceive("key up \(keyCode)")
        case "hm":
            guard parts.count == 2,
                  let flagsRaw = UInt64(parts[1]) else { return }
            input?.holdModifier(CGEventFlags(rawValue: flagsRaw))
            logFirstReceive("hold modifier")
        case "rm":
            guard parts.count == 2,
                  let flagsRaw = UInt64(parts[1]) else { return }
            input?.releaseModifier(CGEventFlags(rawValue: flagsRaw))
            logFirstReceive("release modifier")
        case "ra":
            input?.releaseAllModifiers()
            logFirstReceive("release all modifiers")
        case "sc":
            guard parts.count == 7,
                  let dx = Double(parts[1]),
                  let dy = Double(parts[2]),
                  let phaseRaw = Int32(parts[3]),
                  let momentumRaw = Int32(parts[4]),
                  let continuousRaw = Int(parts[5]),
                  let flagsRaw = UInt64(parts[6]) else { return }
            input?.scroll(
                dx: CGFloat(dx),
                dy: CGFloat(dy),
                phase: phaseRaw >= 0 ? CGScrollPhase(rawValue: UInt32(phaseRaw)) : nil,
                momentumPhase: momentumRaw >= 0 ? CGMomentumScrollPhase(rawValue: UInt32(momentumRaw)) : nil,
                isContinuous: continuousRaw != 0,
                flags: CGEventFlags(rawValue: flagsRaw)
            )
            logFirstReceive("scroll dx=\(dx) dy=\(dy)")
        case "tt":
            guard parts.count == 4,
                  let data = Data(base64Encoded: String(parts[1])),
                  let text = String(data: data, encoding: .utf8),
                  let speed = Int(parts[2]),
                  let enterRaw = Int(parts[3]) else { return }
            input?.typeText(text, speed: speed, pressEnter: enterRaw != 0)
            logFirstReceive("type text")
        case "sys":
            guard parts.count == 2,
                  let data = Data(base64Encoded: String(parts[1])),
                  let command = try? JSONDecoder().decode(SystemCommand.self, from: data) else { return }
            systemCommandExecutor?.execute(command)
            logFirstReceive("system command")
        case "ui":
            guard parts.count == 4,
                  let button = ControllerButton(rawValue: String(parts[2])),
                  let holdRaw = Int(parts[3]) else { return }
            let action = String(parts[1])
            let holdMode = holdRaw != 0
            Task { @MainActor in
                let engine = ServiceContainer.shared.mappingEngine
                switch action {
                case "oskPress":
                    engine.handleOnScreenKeyboardPressed(button, holdMode: holdMode)
                case "oskRelease":
                    engine.handleOnScreenKeyboardReleased(button)
                case "laserPress":
                    engine.handleLaserPointerPressed(button, holdMode: holdMode)
                case "laserRelease":
                    engine.handleLaserPointerReleased(button)
                case "navPress":
                    engine.handleDirectoryNavigatorPressed(button, holdMode: holdMode)
                case "navRelease":
                    engine.handleDirectoryNavigatorReleased(button)
                case "wheelPress":
                    engine.handleCommandWheelPressed(button, holdMode: holdMode)
                case "wheelRelease":
                    engine.handleCommandWheelReleased(button)
                default:
                    break
                }
            }
            logFirstReceive("ui \(action)")
        case "wheel":
            guard parts.count == 4,
                  let stickX = Double(parts[1]),
                  let stickY = Double(parts[2]),
                  let alternateRaw = Int(parts[3]) else { return }
            Task { @MainActor in
                CommandWheelManager.shared.setShowingAlternate(alternateRaw != 0)
                CommandWheelManager.shared.updateSelection(stickX: stickX, stickY: stickY)
            }
            logFirstReceive("wheel update")
        case "fb":
            guard parts.count == 4,
                  let actionData = Data(base64Encoded: String(parts[1])),
                  let action = String(data: actionData, encoding: .utf8),
                  let typeData = Data(base64Encoded: String(parts[2])),
                  let typeRaw = String(data: typeData, encoding: .utf8),
                  let type = InputEventType(rawValue: typeRaw),
                  let heldRaw = Int(parts[3]) else { return }
            Task { @MainActor in
                ActionFeedbackIndicator.shared.show(action: action, type: type, isHeld: heldRaw != 0)
            }
            logFirstReceive("feedback")
        case "fd":
            guard parts.count == 2 else { return }
            let action: String?
            if parts[1] == "-" {
                action = nil
            } else if let data = Data(base64Encoded: String(parts[1])),
                      let decoded = String(data: data, encoding: .utf8) {
                action = decoded
            } else {
                return
            }
            Task { @MainActor in
                ActionFeedbackIndicator.shared.dismissHeld(action: action)
            }
            logFirstReceive("dismiss feedback")
        default:
            return
        }
    }

    private func handleClient(line: String) {
        let parts = line.split(separator: " ")
        guard parts.count == 7,
              parts[0] == "pos",
              let x = Double(parts[1]),
              let y = Double(parts[2]),
              let minX = Double(parts[3]),
              let maxX = Double(parts[4]),
              let minY = Double(parts[5]),
              let maxY = Double(parts[6]) else { return }

        lock.lock()
        remoteCursorStatus = RemoteCursorStatus(
            point: CGPoint(x: x, y: y),
            bounds: CGRect(
                x: minX,
                y: minY,
                width: max(0, maxX - minX),
                height: max(0, maxY - minY)
            )
        )
        lock.unlock()
    }

    private func sendRemoteCursorStatus(on connection: NWConnection) {
        let point = currentRemoteCGPoint()
        let bounds = remoteScreenBounds()
        let line = "pos \(Double(point.x)) \(Double(point.y)) \(Double(bounds.minX)) \(Double(bounds.maxX)) \(Double(bounds.minY)) \(Double(bounds.maxY))\n"
        guard let data = line.data(using: .utf8) else { return }
        connection.send(content: data, completion: .contentProcessed { error in
            if let error {
                NSLog("[UCMouseRelay] Could not send cursor status: %@", String(describing: error))
            }
        })
    }

    private func updateRemoteMouseButtonState(keyCode: CGKeyCode, isDown: Bool) {
        guard KeyCodeMapping.isMouseButton(keyCode) else { return }
        let (_, button) = mouseEventType(for: keyCode, down: isDown)
        lock.lock()
        if isDown {
            remoteMouseButtonsHeld.insert(button)
        } else {
            remoteMouseButtonsHeld.remove(button)
        }
        lock.unlock()
    }

    private func mouseEventType(for keyCode: CGKeyCode, down: Bool) -> (CGEventType, CGMouseButton) {
        switch keyCode {
        case KeyCodeMapping.mouseLeftClick:
            return (down ? .leftMouseDown : .leftMouseUp, .left)
        case KeyCodeMapping.mouseRightClick:
            return (down ? .rightMouseDown : .rightMouseUp, .right)
        case KeyCodeMapping.mouseMiddleClick:
            return (down ? .otherMouseDown : .otherMouseUp, .center)
        default:
            return (down ? .leftMouseDown : .leftMouseUp, .left)
        }
    }

    private func logFirstReceive(_ description: String) {
        lock.lock()
        let shouldLog = !didLogFirstReceive
        didLogFirstReceive = true
        lock.unlock()
        if shouldLog {
            NSLog("[UCMouseRelay] Received first %@", description)
        }
    }

    private func warpRemoteMouse(dx: Int, dy: Int) {
        let next = clampedRemotePoint(dx: dx, dy: dy)
        CGWarpMouseCursorPosition(next)
        CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
    }

    private func postRemoteMouseButton(keyCode: CGKeyCode, down: Bool) {
        let (type, button) = mouseEventType(for: keyCode, down: down)
        let location = currentRemoteCGPoint()
        let clickCount: Int64

        lock.lock()
        if down {
            remoteMouseButtonsHeld.insert(button)
            remoteMouseEventNumber += 1

            let now = Date()
            if let lastTime = remoteLastClickTime[button],
               now.timeIntervalSince(lastTime) < Config.multiClickThreshold {
                clickCount = (remoteClickCounts[button] ?? 0) + 1
            } else {
                clickCount = 1
            }
            remoteClickCounts[button] = clickCount
            remoteLastClickTime[button] = now
        } else {
            remoteMouseButtonsHeld.remove(button)
            clickCount = remoteClickCounts[button] ?? 1
        }
        let eventNumber = remoteMouseEventNumber
        lock.unlock()

        CGWarpMouseCursorPosition(location)

        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: location,
            mouseButton: button
        ) else {
            NSLog("[UCMouseRelay] Could not create remote mouse button event")
            return
        }
        event.setIntegerValueField(.mouseEventClickState, value: clickCount)
        event.setIntegerValueField(.mouseEventNumber, value: eventNumber)
        event.setIntegerValueField(.mouseEventDeltaX, value: 0)
        event.setIntegerValueField(.mouseEventDeltaY, value: 0)
        event.setDoubleValueField(.mouseEventPressure, value: down ? 1.0 : 0.0)
        event.post(tap: .cghidEventTap)
    }

    private func postRemoteMouseDrag(dx: Int, dy: Int) {
        lock.lock()
        let button = remoteMouseButtonsHeld.first ?? .left
        let eventNumber = remoteMouseEventNumber
        lock.unlock()

        let type: CGEventType
        switch button {
        case .right:
            type = .rightMouseDragged
        case .center:
            type = .otherMouseDragged
        default:
            type = .leftMouseDragged
        }

        let next = clampedRemotePoint(dx: dx, dy: dy)
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: next,
            mouseButton: button
        ) else {
            NSLog("[UCMouseRelay] Could not create remote mouse drag event")
            return
        }
        event.setIntegerValueField(.mouseEventNumber, value: eventNumber)
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy))
        event.setDoubleValueField(.mouseEventPressure, value: 1.0)
        event.post(tap: .cghidEventTap)
        CGWarpMouseCursorPosition(next)
    }

    private func currentRemoteCGPoint() -> CGPoint {
        if let event = CGEvent(source: nil) {
            return event.location
        }

        let bounds = remoteScreenBounds()
        guard bounds != .zero else { return .zero }

        let screenHeight = bounds.height
        let current = NSEvent.mouseLocation
        return CGPoint(x: current.x, y: screenHeight - current.y)
    }

    private func clampedRemotePoint(dx: Int, dy: Int) -> CGPoint {
        let bounds = remoteScreenBounds()
        let current = currentRemoteCGPoint()
        return CGPoint(
            x: max(bounds.minX, min(bounds.maxX - 1, current.x + CGFloat(dx))),
            y: max(bounds.minY, min(bounds.maxY - 1, current.y + CGFloat(dy)))
        )
    }

    private func remoteScreenBounds() -> CGRect {
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetActiveDisplayList(displayCount, &displays, &displayCount)

        let bounds = displays.reduce(CGRect.null) { result, display in
            result.union(CGDisplayBounds(display))
        }
        if !bounds.isNull {
            return bounds
        }
        return NSScreen.main?.frame ?? .zero
    }

    private func logSendFailureOnce(_ error: NWError) {
        lock.lock()
        if didLogSendFailure {
            lock.unlock()
            return
        }
        didLogSendFailure = true
        lock.unlock()

        NSLog("[UCMouseRelay] Send failed: %@", String(describing: error))
    }

    private func logFirstSend(dx: Int, dy: Int) {
        lock.lock()
        let shouldLog = !didLogFirstSend
        didLogFirstSend = true
        lock.unlock()

        if shouldLog {
            NSLog("[UCMouseRelay] Sent first move dx=%d dy=%d", dx, dy)
        }
    }
}
