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
        var props: Unmanaged<CFMutableDictionary>? = nil
        let result = IORegistryEntryCreateCFProperties(object, &props, kCFAllocatorDefault, 0)

        if result == kIOReturnSuccess, let properties = props?.takeRetainedValue() as? [String: Any] {
            let name = properties["Name"] as? String ?? properties["Product"] as? String ?? "Unknown"
            let className = IOObjectCopyClass(object).takeRetainedValue() as String

            print("\(prefix)Object: \(className) | Name/Product: \(name)")

            let keys = properties.keys.sorted()
            for key in keys {
                if let val = properties[key] {
                    // Filter out large binary data like ReportDescriptor for readability
                    if val is Data && (val as! Data).count > 64 {
                        print("\(prefix)  -> \(key): <Binary Data (\((val as! Data).count) bytes)>")
                    } else {
                        print("\(prefix)  -> \(key): \(val)")
                    }
                }
            }
        }
    }

    static func scanForXboxControllers() {
        let classesToScan = ["IOHIDDevice", "IOBluetoothDevice", "AppleBLEHIDDevice"]

        print("Starting HID Property Scan for Xbox Controllers...\n")

        for cls in classesToScan {
            let matchingDict = IOServiceMatching(cls)
            var iterator: io_iterator_t = 0
            IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)

            var service: io_object_t = 0
            while true {
                service = IOIteratorNext(iterator)
                if service == 0 { break }

                let product = getProperty(service, "Product") as? String ?? ""
                let name = getProperty(service, "Name") as? String ?? ""

                if product.localizedCaseInsensitiveContains("Xbox") || name.localizedCaseInsensitiveContains("Xbox") {
                    print("================================================================")
                    print("FOUND DEVICE: \(product.isEmpty ? name : product)")
                    print("================================================================")
                    printAllProperties(service)
                    print("\n")
                }

                IOObjectRelease(service)
            }
            IOObjectRelease(iterator)
        }

        print("Scan complete.")
    }
}
