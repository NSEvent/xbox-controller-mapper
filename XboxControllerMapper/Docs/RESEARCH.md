# Xbox Controller Research & Hardware Integration

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
