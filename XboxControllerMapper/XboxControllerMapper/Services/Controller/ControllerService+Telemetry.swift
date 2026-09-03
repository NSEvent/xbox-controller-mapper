import Foundation
import GameController

@MainActor
extension ControllerService {
    /// Converts local controller metadata to a coarse family. No product name,
    /// serial, address, or stable controller identifier leaves the Mac.
    func reportControllerConnectionForTelemetry(
        fallback: TelemetryService.ControllerFamily? = nil
    ) {
        let family: TelemetryService.ControllerFamily
        if let fallback {
            family = fallback
        } else if threadSafeIsPlayStation {
            family = .playstation
        } else if threadSafeIsNintendo {
            family = .nintendo
        } else if threadSafeIsSteamController {
            family = .steam
        } else if threadSafeIsAppleTVRemote {
            family = .appleTVRemote
        } else {
            let localDescription = [
                controllerName,
                connectedController?.vendorName,
                connectedController?.productCategory,
            ]
                .compactMap { $0 }
                .joined(separator: " ")
                .lowercased()
            family = localDescription.contains("xbox") || localDescription.contains("microsoft")
                ? .xbox
                : .generic
        }
        TelemetryService.shared.controllerConnected(family: family)
    }
}
