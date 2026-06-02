# Xbox Controller Research & Hardware Integration

## Apple TV / Siri Remote Microphone R&D

Date: 2026-05-30

Goal: determine whether ControllerKeys can expose the Apple TV / Siri Remote built-in microphone as a macOS input source.

### Summary

The path is technically plausible at the BLE HID protocol layer, but not practical inside a normal macOS app. macOS does not expose the Siri Remote as a CoreAudio input device, and Apple's private `AppleBluetoothRemote` driver appears to own or consume the microphone HID stream before ControllerKeys can receive audio frames.

Product decision: do not ship direct Siri Remote microphone support on macOS unless macOS later exposes it as CoreAudio. Use the Siri/mic button as a push-to-talk trigger for an existing Mac input device instead.

2026-06-02 update: admin-backed capture is proven, so a power-user path is possible. The normal app-store/Gumroad app still should not depend on this path by default, but ControllerKeys could offer an advanced helper that exposes the remote mic as a virtual CoreAudio input device.

### PacketLogger Follow-up

Prompt from an Apple-platform developer: install Apple's Bluetooth logging profile, then run PacketLogger from `Additional_Tools_for_Xcode_26.5.dmg` as administrator. That should show whether microphone data is arriving over Bluetooth while the Siri button is held.

Apple's Bluetooth developer page confirms PacketLogger ships in Additional Tools for Xcode: <https://developer.apple.com/bluetooth/>

Apple's Profiles and Logs page publishes a `Bluetooth for macOS` profile and logging instructions, but both require Apple Developer sign-in: <https://developer.apple.com/feedback-assistant/profiles-and-logs/?name=bluetooth>

Decision gate:

- If PacketLogger shows report `0xFA` microphone frames while `Scripts/apple-tv-remote-mic-probe.swift` sees no IOHID reports, the stream is on-air but consumed by macOS before apps can read it. That is not shippable in ControllerKeys without a privileged/private Bluetooth, HCI capture, or DriverKit path.
- If the probe sees report `0xFA` or macOS's wrapped audio report `0xFF`, the next product work is Opus CELT decode plus either direct transcription support or a virtual CoreAudio input device. External transcription apps such as VoiceInk cannot use decoded PCM unless it is exposed as an input device.

Probe command:

```bash
swift Scripts/apple-tv-remote-mic-probe.swift --seconds 30
```

If the audio HID child is locked by the system or ControllerKeys:

```bash
swift Scripts/apple-tv-remote-mic-probe.swift --seconds 30 --seize
```

Admin capture scanner:

```bash
swift Scripts/apple-tv-remote-pklg-scan.swift ~/Downloads/Bluetooth.pklg
```

Admin capture decoder:

```bash
Scripts/apple-tv-remote-pklg-decode.py ~/Downloads/Bluetooth.pklg -o ~/Downloads/siri-remote-mic.wav
```

Saved-capture transcription:

```bash
Scripts/apple-tv-remote-pklg-transcribe.sh ~/Downloads/Bluetooth.pklg
```

PacketLogger CLI replay:

```bash
/Applications/PacketLogger.app/Contents/Resources/packetlogger convert \
  --input ~/Downloads/Bluetooth.pklg \
  --format ir \
  --stdout \
| ./Scripts/apple-tv-remote-packetlogger-live.py \
  -o ~/Downloads/siri-remote-packetlogger-cli.wav \
  --transcribe
```

Timed live admin capture:

```bash
./Scripts/apple-tv-remote-packetlogger-live.py \
  --capture \
  --enable-hid \
  --stop-on-release \
  --seconds 20 \
  -o ~/Downloads/siri-remote-live.wav \
  --transcribe
```

The live command does not require the PacketLogger GUI to be open. It uses the PacketLogger CLI and will prompt for `sudo`; the Bluetooth logging profile still must be installed. `--stop-on-release` watches the remote's Siri button notification and ends the capture shortly after release, while `--seconds` remains a safety cap. Release detection comes from IOHID immediately; the script then terminates PacketLogger and drains any raw rows still buffered in stdout before decoding.

Saved GUI capture recipe:

1. Install Apple's `Bluetooth for macOS` logging profile from the Profiles and Logs page.
2. Open `PacketLogger.app` from Additional Tools for Xcode as administrator.
3. Start capture, pair/connect the Apple TV Remote, then hold the Siri/mic button while speaking.
4. Save the capture as `.pklg`.
5. Run `Scripts/apple-tv-remote-pklg-scan.swift` against the capture.

Expected success signals:

- `WRITE_0xAF` means the host or tool sent the known input-enable byte.
- `REPORT_REFERENCE ... reportID=0xFA type=input` means the mic report descriptor is visible in the capture.
- `MIC_CANDIDATE ... payloadLen=99` means the capture contains HID mic payloads that match the known 20 ms Opus frame container.
- `faPrefixedNotifications` is a fallback for captures that include the report ID in the notification value.
- The decoder extracts the Opus frames from those 99-byte payloads, decodes them with `libopus`, and writes 48 kHz mono Int16 WAV.
- The transcriber wraps the decoder and `whisper.cpp` for an end-to-end saved-capture proof.
- The live prototype wraps Apple's `packetlogger convert --stdout --format ir` CLI, optionally runs the IOHID probe to send the mic enable byte, parses raw HCI rows, tracks the Siri button PTT boundary from PacketLogger and IOHID probe output, writes decoded WAV, and can run `whisper.cpp`.

### Local Findings

- `system_profiler SPAudioDataType` did not show the remote as an input device.
- `system_profiler SPBluetoothDataType` showed the remote as connected BLE device:
  - Vendor ID: `0x004C`
  - Product ID: `0x0315`
  - Services: BLE only
- `hidutil list` / `ioreg` showed multiple Apple Bluetooth Remote HID interfaces for the same device, including:
  - `AppleEmbeddedBluetoothAudio`
  - `AppleEmbeddedBluetoothButtons`
  - `AppleEmbeddedBluetoothTouch`
  - `AppleEmbeddedBluetoothInfrared`
  - `AppleEmbeddedBluetoothRadio`
- `AppleEmbeddedBluetoothAudio` is under `com.apple.driver.AppleBluetoothRemote`, with:
  - Primary Usage Page: `0x0C` (Consumer)
  - Primary Usage: `0x04` (Microphone)
  - Max input/feature report size: `209`
  - `Privileged = true`
- A temporary IOHID probe could open the private audio HID interface only when ControllerKeys was not also holding the remote.
- The probe could successfully write the known enable byte `0xAF` as a feature report.
- Even after registering an input report callback before writing `0xAF`, pressing and holding the Siri/mic button produced no user-space input reports through IOHID.
- A temporary CoreBluetooth probe could not retrieve the already-connected HID-over-GATT remote from macOS using service `0x1812`, and scanning did not expose a usable connected peripheral during the test.
- 2026-06-01 follow-up while remote `C08QMZ6M2330` was connected:
  - `system_profiler SPBluetoothDataType` showed the remote connected over BLE, Vendor ID `0x004C`, Product ID `0x0315`.
  - `IOHID` exposed `AppleEmbeddedBluetoothAudio` as an `IOHIDUserDevice` with Primary Usage Page `0x0C`, Primary Usage `0x04`, Max input/feature report size `209`.
  - On macOS, that audio child presents input and feature report ID `0xFF`, not Linux's raw report ID `0xFA`.
  - `IOHIDDeviceOpen` returned success and `0xAF` feature writes returned success, but no `0xFF` input reports arrived during the probe window.
  - A broader probe opened all seven Apple TV Remote HID children and wrote `0xAF` to every exposed feature report. Feature writes succeeded on all children except one stripped-payload touch write that required the `0xFF` report ID prefix. No input report callbacks arrived.
  - The broader probe also registered `IOHIDManagerRegisterInputValueCallback` to match ControllerKeys' button path. No HID value callbacks arrived during the probe window.
  - `CoreBluetooth.retrieveConnectedPeripherals(withServices: [0x1812, 0x180F])` returned the remote, but service discovery exposed only Battery service `0x180F` with `2A19` and `2A1A`; HID service `0x1812` was not accessible via public CoreBluetooth.
  - `Scripts/apple-tv-remote-gatt-probe.swift` confirms the paired/connected state only exposes Battery service `0x180F` through public CoreBluetooth. It does not expose HID service `0x1812` while macOS owns the paired remote.
  - After unpairing/disconnecting from the normal macOS path and putting the remote in pairing mode, BLE advertisements did include service `0x1812`, with rotating CoreBluetooth peripheral identifiers.
  - Connecting to those advertisements from the probe still did not expose HID service `0x1812`. Initial service discovery returned only Battery `0x180F`; full service discovery returned Battery `0x180F`, Device Information `0x180A`, and an Apple vendor service `F5873412-D314-B885-A5AA-EFA546123981`.
  - The Apple vendor characteristic `F5873413-D314-B885-A5AA-EFA546123982` was readable/writable, but reading returned 16 zero bytes and no descriptors. The probe did not issue blind writes to that vendor characteristic.
  - No HID Report characteristics `0x2A4D`, Report Reference descriptors `0x2908`, or mic/button/touch reports were visible through public CoreBluetooth even in this direct pairing-mode test.
  - Running PacketLogger as the normal user only captured the Siri button HID input (`0xFB 20 00` down, `0xFB 00 00` up), not the microphone stream.
  - Running PacketLogger as root after installing the Bluetooth logging profile captured fragmented ATT notifications on handle `0x0036`. After L2CAP reassembly, `Scripts/apple-tv-remote-pklg-scan.swift` found 323 contiguous 99-byte mic payloads (`seq=0...322`).
  - `Scripts/apple-tv-remote-pklg-decode.py` decoded those packets with Homebrew `opus`/`libopus` into a 6.46 second 48 kHz mono WAV. `ffmpeg` reported mean volume `-20.3 dB`, confirming real audio signal.
  - `whisper.cpp` with `ggml-base.en.bin` transcribed the decoded WAV as: "Hey, I'm just testing speaking in the mic and seeing if that does anything if I speak in the mic."
  - Additional Tools also installs `/Applications/PacketLogger.app/Contents/Resources/packetlogger`. Its `convert --stdout --format ir` mode emits timestamped raw HCI rows.
  - `Scripts/apple-tv-remote-packetlogger-live.py` parsed that CLI output from `test2.pklg`, recovered the same 323 packets with no sequence gaps, wrote a 6.46 second WAV, and produced the same `whisper.cpp` transcript.
  - 2026-06-02 live PacketLogger CLI capture with `--enable-hid` succeeded without saving a `.pklg` first: 964 raw rows, 312 contiguous mic packets (`seq=0...311`), 6.24 second WAV at `~/Downloads/siri-remote-live.wav`, and transcript: "Hey, I'm just testing this and seeing if this works. So this is it has one two three"
  - The same live run showed the normal IOHID button path still reports the Siri button (`0xFB 20 00` down, `0xFB 00 00` up), while PacketLogger captures the mic stream in parallel.

Interpretation: the failed path is not only the already-paired macOS HID-owner path. Public CoreBluetooth on macOS can see HID in the advertisement, but filters or withholds the HID-over-GATT service after connection. A third-party app could still plausibly get app-level audio by using a private/privileged Bluetooth capture path, by parsing PacketLogger/HCI capture data, or by running the Linux direct-owner approach on a sidecar. Those are different from "ControllerKeys reads the mic while macOS/GameController also owns the remote."

### External Protocol Notes

Linux reverse-engineering work confirms the gen-3 Siri Remote microphone protocol:

- HID-over-GATT service: `0x1812`
- HID Report characteristic: `0x2A4D`
- The remote remains silent until userspace writes `0xAF` to writable non-input HID reports.
- Report `0xFA` carries microphone audio.
- Audio payloads are Opus CELT wideband frames, 20 ms at 48 kHz mono, inside 99-byte HID payloads.
- Report `0xFB` carries buttons.
- Report `0xFC` carries touchpad frames.

Useful reference: `~/projects/oss/siri-remote` (`azais-corentin/siri-remote`).

Important license note: `azais-corentin/siri-remote` is GPL-3.0. Use it only as protocol research context; do not copy code into ControllerKeys.

### Why This Is Not Shippable Today

ControllerKeys is a macOS app, not a Bluetooth stack replacement. On macOS, the HID-over-GATT report characteristics are mediated by Apple's Bluetooth/HID stack and the private `AppleBluetoothRemote` driver. The known Linux approach depends on bypassing the platform HID owner and directly addressing every per-instance HID Report characteristic. That route is not exposed cleanly to a sandbox-normal macOS app, and the public CoreBluetooth direct-owner probe still cannot enumerate the HID service.

Potential non-product paths:

- A Linux/Raspberry Pi sidecar could own the BLE remote, decode Opus, then stream audio to the Mac as a network or virtual mic.
- PacketLogger/admin HCI capture could prove and possibly decode the stream, but it would be diagnostic or power-user tooling, not a normal app-level ControllerKeys feature.
- A private entitlement, kernel, HCI, or DriverKit path might replace/compete with `AppleBluetoothRemote`, but that is not appropriate for ControllerKeys distribution.
- Future macOS versions could expose the remote as CoreAudio; if so, ControllerKeys should use normal CoreAudio device discovery rather than private HID decoding.

### Next Implementation Step

The saved-capture path is proven:

```text
PacketLogger .pklg -> L2CAP reassembly -> 99-byte mic packets -> Opus decode -> WAV -> whisper.cpp transcript
```

The remaining engineering problem is live capture. Apple's PacketLogger CLI provides a practical prototype path before building a custom helper:

```text
sudo packetlogger convert --stdout --format ir + IOHID 0xAF enable -> raw HCI rows -> handle 0x0036 mic packets + handle 0x003A PTT boundary -> Opus decode -> WAV/transcript
```

The longer-term implementation would be a privileged helper that directly receives Bluetooth controller packet events, filters the Apple TV Remote ATT notifications on the mic handle, decodes Opus frames continuously, and sends PCM/transcript events to ControllerKeys over XPC or a local socket.

Implementation constraints:

- The helper must run with elevated privileges or a private Bluetooth/HCI capability; normal ControllerKeys cannot see the mic packets.
- ControllerKeys should remain a normal app. It can request/start/stop the helper and use the Siri button as push-to-talk state.
- For transcription-only support, decoded PCM can feed `whisper.cpp` directly.
- For third-party apps such as VoiceInk, decoded PCM must be exposed as a virtual CoreAudio input device, which is a separate driver/plugin problem.

### Product Architecture Direction

Best product shape: a virtual microphone that is always present as a macOS input device, with the Apple TV Remote stream filling it only while the Siri/mic button is active.

Do not treat this as a truly always-on remote microphone yet. In every successful capture so far, the remote streamed mic packets while the Siri/mic button was held and stopped after release. The app should therefore keep the virtual device registered continuously, but output silence when the remote is idle or unavailable.

Recommended pipeline:

```text
Apple TV Remote -> privileged Bluetooth/PacketLogger helper -> Opus decode -> PCM ring buffer -> virtual CoreAudio input device
```

Runtime behavior:

- Virtual mic appears in Sound settings and third-party apps as something like `ControllerKeys Remote Mic`.
- Helper runs only when the virtual mic feature is enabled.
- Siri button down starts filling the virtual mic buffer with decoded PCM.
- Siri button up drains a short tail, then outputs silence.
- If the remote disconnects, helper stops feeding audio and the virtual device stays present with silence.
- ControllerKeys UI should show helper status, selected remote, packet count, and last transcript/debug message.

### ControllerKeys Prototype Implemented

The branch now includes an app-side prototype bridge and the first installable virtual CoreAudio input component:

- `AppleTVRemoteMicBridge` builds the admin `osascript` command for live PacketLogger capture, writes WAV/transcript output under `~/Library/Application Support/ControllerKeys/RemoteMic`, and exposes status to SwiftUI.
- ControllerKeys copies the three runtime scripts into app resources during build: `apple-tv-remote-packetlogger-live.py`, `apple-tv-remote-pklg-decode.py`, and `apple-tv-remote-mic-probe.swift`.
- The Apple TV Remote microphone section appears when an Apple TV Remote is connected.
- When the bridge toggle is enabled, the deduped Siri button press automatically starts a push-to-talk capture. The manual button remains useful for debugging.
- `RemoteMic/ControllerKeysRemoteMicDriver.c` builds an AudioServerPlugIn HAL driver that registers `ControllerKeys Remote Mic` as a 48 kHz mono input device.
- `RemoteMic/controllerkeys-remote-mic-capture.c` builds a fixed-purpose setuid helper that runs the installed PacketLogger live-capture script without a per-capture administrator prompt.
- `Scripts/install-remote-mic-components.sh` installs:
  - `/Library/Audio/Plug-Ins/HAL/ControllerKeysRemoteMic.driver`
  - `/Library/Application Support/ControllerKeys/RemoteMicBridge/controllerkeys-remote-mic-capture`
  - root-owned PacketLogger bridge scripts under `/Library/Application Support/ControllerKeys/RemoteMicBridge/Scripts`
- `make install-remote-mic-components BUILD_FROM_SOURCE=1` is the one-admin-prompt install path for the HAL driver and helper.
- The app prefers the installed helper. If it is missing, it falls back to the old admin `osascript` PacketLogger command.
- `Scripts/apple_tv_remote_coreaudio_ring.py` publishes decoded PCM into a file-backed mmap ring at `/tmp/controllerkeys-remote-mic.pcm`.
- `RemoteMic/ControllerKeysRemoteMicRingReader.h` maps that ring from the HAL driver and converts Int16 PCM into the Float32 CoreAudio input callback format, returning silence when the helper is idle or unavailable.

2026-06-02 verification:

- The HAL driver must expose a box object, an empty output stream list, an empty control list, and a mono preferred channel layout before CoreAudio will publish it.
- The installed driver is signed with Team ID `542GXYT5Z2` and appears in CoreAudio as `ControllerKeys Remote Mic` with one input stream.
- The installed helper is root-owned and setuid (`root:wheel`, mode `4755`).
- Direct helper smoke launched PacketLogger without a macOS administrator dialog. It exited with the expected "no mic packets found" error when the Siri/mic button was not held.
- Saved PacketLogger replay with `--feed-coreaudio` filled the shared ring with 310,080 decoded 48 kHz mono Int16 samples from `test2.pklg`.
- A direct C reader using the same ring reader header copied nonzero PCM from the shared ring, confirming the helper-to-driver buffer format.
- CoreAudio enumeration sees `ControllerKeys Remote Mic` by UID `com.kevintang.ControllerKeys.RemoteMic`.
- After switching the HAL stream to 48 kHz mono Float32 and tightening the device owned-object scopes, a throwaway AudioQueue recorder can start and stop the virtual input without wedging `coreaudiod`.
- Feeding `test2.pklg` into `/tmp/controllerkeys-remote-mic.pcm` in realtime produced nonzero samples from the virtual CoreAudio input: `bytes=385024 nonzero=130410 abssum=255097050`.
- Focused tests passed: `AppleTVRemoteMicBridgeTests`, `MainWindowSectionVisibilityTests`, and `ControllerServiceCallbackProxyTests` ran 43 tests with 0 failures.

Current limitation: the PCM bridge still depends on Apple's PacketLogger CLI and the Bluetooth logging profile. The virtual mic is therefore a power-user/admin tooling path, not yet a normal distribution-grade capture backend.

Open engineering questions:

- Whether to keep the AudioServerPlugIn HAL backend or move to a DriverKit audio extension for distribution.
- Whether the PacketLogger CLI can be shipped or whether the helper needs a direct private/HCI capture implementation.
- Whether continuous streaming without holding Siri is possible by changing the enable/write sequence; current evidence only proves push-to-talk streaming.
- How to install, uninstall, notarize, and permission the privileged helper and virtual audio component without making normal ControllerKeys brittle.

## HID Property Findings
During the development of the Battery Monitor workaround, we investigated the IORegistry properties for Xbox Series X/S controllers (Model 1914).

### Key Properties Exposed
- **Product:** `Xbox Wireless Controller`
- **VendorID:** `1118` (Microsoft)
- **ProductID:** `2835` (Series X/S)
- **SerialNumber:** Unique hardware ID (e.g., `09710002261334`)
- **DeviceAddress:** Bluetooth MAC Address (e.g., `0c-35-26-fe-24-b6`)
- **kBTFirmwareRevisionKey:** Controller firmware version (e.g., `5.9.2709.0`)

### Battery Reporting (GATT Workaround)
Standard macOS `GameController.framework` often fails to report battery for Xbox controllers (returning -1 or 0%). 
**Solution:** We implemented a `BluetoothBatteryMonitor` that connects via `CoreBluetooth` to the standard GATT Battery Service:
- **Service UUID:** `0x180F`
- **Characteristic UUID:** `0x2A19` (Battery Level)

## Future Feature Ideas
### 1. Hardware-Linked Profiles
Use `SerialNumber` or `DeviceAddress` to bind mapping profiles to specific physical controllers.
- **Scenario:** A user has two controllers. "Controller A" is mapped for RPGs, "Controller B" is mapped for FPS. 
- **Implementation:** `ProfileManager` could store a `linkedControllerID` in the profile JSON and automatically switch when that ID is detected.

### 2. Firmware Compatibility Warnings
Monitor `kBTFirmwareRevisionKey` via IOKit.
- **Scenario:** Older firmware has known issues with button mapping on macOS.
- **Implementation:** Alert the user if their firmware is below a certain version.

## Diagnostic Tools
- `Utilities/HIDPropertyScanner.swift`: A standalone Swift script to dump all IORegistry properties for connected controllers.
