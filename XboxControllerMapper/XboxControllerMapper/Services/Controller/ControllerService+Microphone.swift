import Foundation
import CoreAudio
import AudioToolbox
import AVFoundation

// MARK: - Microphone / Audio Control

@MainActor
extension ControllerService {

    /// Enables the microphone on the DualSense controller using CoreAudio
    func enableMicrophone(device: IOHIDDevice) {
        #if DEBUG
        print("[Mic] enableMicrophone called, searching for DualSense audio device...")
        #endif
        // Use CoreAudio to find and unmute the DualSense microphone
        unmuteDualSenseMicrophone()
    }

    /// Finds the DualSense audio input device and unmutes it via CoreAudio
    func unmuteDualSenseMicrophone() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else {
            #if DEBUG
            print("[Mic] Failed to get audio devices size: \(status)")
            #endif
            return
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var audioDevices = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &audioDevices
        )

        guard status == noErr else {
            #if DEBUG
            print("[Mic] Failed to get audio devices: \(status)")
            #endif
            return
        }

        // Find and unmute ALL DualSense microphone devices
        // (There may be multiple audio devices for the same controller)
        var foundAny = false
        for deviceID in audioDevices {
            guard let deviceName = getAudioDeviceName(deviceID) else { continue }

            // Check if this is a DualSense device
            if deviceName.lowercased().contains("dualsense") ||
               deviceName.lowercased().contains("wireless controller") {

                // Check if it has input channels (is a microphone)
                if hasInputChannels(deviceID) {
                    #if DEBUG
                    print("[Mic] Found DualSense microphone: \(deviceName) (ID: \(deviceID))")
                    #endif
                    unmuteMicrophone(deviceID: deviceID)
                    foundAny = true
                }
            }
        }

        #if DEBUG
        if !foundAny {
            print("[Mic] DualSense microphone not found in audio devices")
        } else {
            print("[Mic] micDeviceID is now: \(String(describing: micDeviceID))")
        }
        #endif
    }

    func getAudioDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &name
        )

        guard status == noErr, let deviceName = name else { return nil }
        return deviceName as String
    }

    func hasInputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)

        guard status == noErr, dataSize > 0 else { return false }

        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferListPointer.deallocate() }

        let getStatus = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, bufferListPointer)
        guard getStatus == noErr else { return false }

        let bufferList = bufferListPointer.pointee
        return bufferList.mNumberBuffers > 0
    }

    func unmuteMicrophone(deviceID: AudioDeviceID) {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        // Check if mute property exists
        guard AudioObjectHasProperty(deviceID, &propertyAddress) else {
            #if DEBUG
            print("[Mic] Device \(deviceID) does not have mute property, trying channel 1")
            #endif
            // Try with channel 1
            unmuteMicrophoneChannel(deviceID: deviceID, channel: 1)
            return
        }

        // Store this device as the controllable mic device
        micDeviceID = deviceID

        // Get current mute state
        var currentMuted: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)

        var status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &currentMuted)
        #if DEBUG
        if status == noErr {
            print("[Mic] Current mute state for device \(deviceID): \(currentMuted == 1 ? "muted" : "unmuted")")
        }
        #endif

        // Set mute to false (0)
        var muteValue: UInt32 = 0
        status = AudioObjectSetPropertyData(deviceID, &propertyAddress, 0, nil, dataSize, &muteValue)

        if status == noErr {
            #if DEBUG
            print("[Mic] Successfully unmuted DualSense microphone (device \(deviceID))")
            #endif
            isMicMuted = false
        } else {
            #if DEBUG
            print("[Mic] Failed to unmute microphone: \(status)")
            #endif
            // Try channel-specific unmute
            unmuteMicrophoneChannel(deviceID: deviceID, channel: 1)
        }
    }

    func unmuteMicrophoneChannel(deviceID: AudioDeviceID, channel: UInt32) {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: channel
        )

        guard AudioObjectHasProperty(deviceID, &propertyAddress) else {
            #if DEBUG
            print("[Mic] Channel \(channel) does not have mute property")
            #endif
            return
        }

        var muteValue: UInt32 = 0
        let dataSize = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectSetPropertyData(deviceID, &propertyAddress, 0, nil, dataSize, &muteValue)

        #if DEBUG
        if status == noErr {
            print("[Mic] Successfully unmuted channel \(channel)")
        } else {
            print("[Mic] Failed to unmute channel \(channel): \(status)")
        }
        #endif
    }

    func hasMuteProperty(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        return AudioObjectHasProperty(deviceID, &propertyAddress)
    }

    // MARK: - Public Microphone Control

    /// Sets the mute state of the DualSense microphone
    func setMicMuted(_ muted: Bool) {
        guard let deviceID = micDeviceID else {
            #if DEBUG
            print("[Mic] No DualSense microphone device available")
            #endif
            return
        }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var muteValue: UInt32 = muted ? 1 : 0
        let dataSize = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectSetPropertyData(deviceID, &propertyAddress, 0, nil, dataSize, &muteValue)

        if status == noErr {
            isMicMuted = muted
            #if DEBUG
            print("[Mic] Microphone \(muted ? "muted" : "unmuted")")
            #endif
        } else {
            #if DEBUG
            print("[Mic] Failed to set mute state: \(status)")
            #endif
        }
    }

    /// Starts monitoring the microphone audio level using AVAudioEngine
    func startMicLevelMonitoring() {
        stopMicLevelMonitoring()

        guard let deviceID = micDeviceID else {
            #if DEBUG
            print("[Mic] No DualSense microphone device for level monitoring")
            #endif
            return
        }

        // Request microphone permission first
        requestMicrophonePermission { [weak self] granted in
            guard granted else {
                #if DEBUG
                print("[Mic] Microphone permission denied")
                #endif
                return
            }

            guard let self = self else { return }

            Task { @MainActor in
                self.startAudioEngine()
            }
        }
    }

    /// Requests microphone permission from the user
    func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            #if DEBUG
            print("[Mic] Microphone permission already granted")
            #endif
            completion(true)
        case .notDetermined:
            #if DEBUG
            print("[Mic] Requesting microphone permission...")
            #endif
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                #if DEBUG
                print("[Mic] Microphone permission \(granted ? "granted" : "denied")")
                #endif
                completion(granted)
            }
        case .denied, .restricted:
            #if DEBUG
            print("[Mic] Microphone permission denied or restricted")
            #endif
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    /// Starts the audio engine for level monitoring (called after permission granted)
    func startAudioEngine() {
        // Set DualSense as the input device BEFORE creating the engine
        setDualSenseAsInputDevice()

        // Small delay to let the system recognize the device change
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }

            let engine = AVAudioEngine()

            // Force the engine to use the new default device
            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)

            #if DEBUG
            print("[Mic] Audio format: \(format)")
            #endif

            // Install tap on input node to monitor audio levels
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                guard let self = self else { return }

                let channelData = buffer.floatChannelData?[0]
                let frameLength = Int(buffer.frameLength)

                guard let data = channelData, frameLength > 0 else { return }

                // Calculate RMS (root mean square) for audio level
                var sum: Float = 0
                for i in 0..<frameLength {
                    sum += data[i] * data[i]
                }
                let rms = sqrt(sum / Float(frameLength))

                // Convert to a 0-1 scale (with some amplification for visibility)
                let level = min(1.0, rms * 8.0)

                Task { @MainActor in
                    self.micAudioLevel = level
                }
            }

            do {
                try engine.start()
                self.audioEngine = engine
                #if DEBUG
                print("[Mic] Audio level monitoring started successfully")
                #endif
            } catch {
                #if DEBUG
                print("[Mic] Failed to start audio engine: \(error)")
                #endif
            }
        }
    }

    /// Stops monitoring the microphone audio level
    func stopMicLevelMonitoring() {
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            audioEngine = nil
            #if DEBUG
            print("[Mic] Audio level monitoring stopped")
            #endif
        }
        micLevelTimer?.invalidate()
        micLevelTimer = nil
        micAudioLevel = 0
    }

    /// Gets the current default input device
    func getCurrentDefaultInputDevice() -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        return status == noErr ? deviceID : nil
    }

    /// Sets the DualSense microphone as the system input device for monitoring
    func setDualSenseAsInputDevice() {
        guard let deviceID = micDeviceID else { return }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceIDCopy = deviceID
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceIDCopy
        )

        #if DEBUG
        if status == noErr {
            print("[Mic] Set DualSense (device \(deviceID)) as default input device")
        } else {
            print("[Mic] Failed to set DualSense as input: \(status)")
        }
        #endif
    }

    /// Refreshes microphone mute state from the device
    func refreshMicMuteState() {
        guard let deviceID = micDeviceID else { return }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var isMuted: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &isMuted)
        if status == noErr {
            self.isMicMuted = isMuted == 1
        }
    }
}
