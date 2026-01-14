import Foundation
import IOKit

/**
 HID Property Scanner Utility

 This class scans the macOS IORegistry to discover properties of connected Xbox controllers.
 It is useful for identifying battery-related keys, hardware identifiers (Serial Number, MAC),
 and HID configuration details that standard APIs like GameController might miss.
 */
class HIDPropertyScanner {
    static func getProperty(_ object: io_object_t, _ key: String) -> Any? {
        guard let value = IORegistryEntryCreateCFProperty(object, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        return value.takeRetainedValue()
    }

    static func printAllProperties(_ object: io_object_t, prefix: String = "") {
        // Diagnostic method - kept for potential future debugging
    }

    static func scanForXboxControllers() {
        // Diagnostic method - kept for potential future debugging
    }
}
