# Xbox Controller Research & Hardware Integration

## Apple TV / Siri Remote Microphone R&D

Date: 2026-05-30

Goal: determine whether ControllerKeys can expose the Apple TV / Siri Remote built-in microphone as a macOS input source.

### Summary

The path is technically plausible at the BLE HID protocol layer, but not practical inside a normal macOS app. macOS does not expose the Siri Remote as a CoreAudio input device, and Apple's private `AppleBluetoothRemote` driver appears to own or consume the microphone HID stream before ControllerKeys can receive audio frames.

Product decision: do not ship direct Siri Remote microphone support on macOS unless macOS later exposes it as CoreAudio. Use the Siri/mic button as a push-to-talk trigger for an existing Mac input device instead.

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

ControllerKeys is a macOS app, not a Bluetooth stack replacement. On macOS, the HID-over-GATT report characteristics are mediated by Apple's Bluetooth/HID stack and the private `AppleBluetoothRemote` driver. The known Linux approach depends on bypassing the platform HID owner and directly addressing every per-instance HID Report characteristic. That route is not exposed cleanly to a sandbox-normal macOS app.

Potential non-product paths:

- A Linux/Raspberry Pi sidecar could own the BLE remote, decode Opus, then stream audio to the Mac as a network or virtual mic.
- A private entitlement, kernel, or DriverKit path might replace/compete with `AppleBluetoothRemote`, but that is not appropriate for ControllerKeys distribution.
- Future macOS versions could expose the remote as CoreAudio; if so, ControllerKeys should use normal CoreAudio device discovery rather than private HID decoding.

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
