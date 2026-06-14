import Foundation

/// Step-by-step pairing instructions for one controller family, surfaced in the
/// empty state when no controller is connected (see `ControllerPairingHintView`).
///
/// Every *concrete* `ControllerPreviewLayout` — i.e. all cases except `.active`,
/// which only resolves to a real device at runtime — maps to a guide, so the
/// "how do I connect *this* controller?" question is answerable for any device
/// the app can preview. `ControllerPairingGuideTests` enforces that completeness
/// guarantee, so adding a new preview layout without a guide fails the build's
/// test gate.
///
/// Strings are localized here at the model layer (`loc` / `String(format:)`)
/// against `Localizable.strings`, English source doubling as the key per the
/// app's convention. Device names ("DualSense Wireless Controller"), button
/// labels, and the 8BitDo model names are intentionally left untranslated since
/// macOS shows them verbatim. Step strings use Markdown emphasis (`**bold**`)
/// for the buttons/labels the user has to find; `ControllerPairingHintView`
/// renders them via `Text(inlineMarkdown:)`.
struct ControllerPairingGuide: Equatable {
    /// e.g. "Pair Your DualSense".
    let title: String
    /// One-line context shown under the title.
    let tagline: String
    /// SF Symbol beside the title (mirrors the picker's `systemImage`).
    let systemImage: String
    /// Ordered Bluetooth pairing steps. Always at least two.
    let bluetoothSteps: [String]
    /// Optional wired / USB fallback note.
    let wiredNote: String?
    /// Optional extra tip (mode combos, model caveats, hardware revisions).
    let tip: String?
    /// Optional macOS-version / native-support caveat.
    let nativeSupportNote: String?
    /// Optional link to the full web guide.
    let guideURL: URL?
    /// The buttons that appear on this controller's minimap and are part of the
    /// pairing combo — highlighted "pressed" on the `PairingMinimapView` so the
    /// user can see *where* to press. Empty when the pairing button isn't on the
    /// front face (e.g. the Xbox top Pair button, the Nintendo top sync button,
    /// or the 8BitDo Micro/Lite Pair button + S/D slider), in which case only
    /// the controller body is shown and the steps describe the physical button.
    let pairingButtons: Set<ControllerButton>

    init(
        title: String,
        tagline: String,
        systemImage: String,
        bluetoothSteps: [String],
        wiredNote: String? = nil,
        tip: String? = nil,
        nativeSupportNote: String? = nil,
        guideURL: URL? = nil,
        pairingButtons: Set<ControllerButton> = []
    ) {
        self.title = title
        self.tagline = tagline
        self.systemImage = systemImage
        self.bluetoothSteps = bluetoothSteps
        self.wiredNote = wiredNote
        self.tip = tip
        self.nativeSupportNote = nativeSupportNote
        self.guideURL = guideURL
        self.pairingButtons = pairingButtons
    }
}

/// Localizes a controller-pairing string against `Localizable.strings`. The
/// English source doubles as the key, matching the app's localization style.
private func loc(_ key: String) -> String {
    NSLocalizedString(key, comment: "Controller pairing guide")
}

// MARK: - Web guide links

private enum PairingGuideURL {
    static let xbox = URL(string: "https://www.kevintang.xyz/apps/xbox-controller-mapper/guides/connect-xbox-controller-mac.html")
    static let ps5 = URL(string: "https://www.kevintang.xyz/apps/xbox-controller-mapper/guides/connect-ps5-controller-mac.html")
}

// MARK: - Per-controller guides

extension ControllerPreviewLayout {
    /// The pairing guide for this preview, or `nil` for `.active` (which has no
    /// single device to describe — the empty state shows a controller chooser
    /// instead).
    var pairingGuide: ControllerPairingGuide? {
        switch self {
        case .active:
            return nil

        case .xbox:
            return ControllerPairingGuide(
                title: loc("Pair Your Xbox Controller"),
                tagline: loc("Xbox Series X|S, or a Bluetooth Xbox One controller"),
                systemImage: systemImage,
                bluetoothSteps: [
                    loc("Press the **Xbox button** to turn the controller on — it lights up."),
                    loc("Hold the **Pair button** on top (next to the charge port) for ~3 seconds, until the Xbox button flashes rapidly."),
                    loc("On your Mac, open **System Settings → Bluetooth**."),
                    loc("Click **Connect** next to **Xbox Wireless Controller**.")
                ],
                wiredNote: loc("Prefer wired? Plug in a USB-C cable (Series X|S) or Micro-USB (Xbox One) — it connects instantly, no pairing."),
                tip: loc("Only Bluetooth models pair wirelessly: any Xbox Series controller, or an Xbox One controller from model 1708 (2016) onward."),
                guideURL: PairingGuideURL.xbox,
                // Xbox button (power on); the top Pair button isn't on the face.
                pairingButtons: [.xbox]
            )

        case .xboxElite:
            return ControllerPairingGuide(
                title: loc("Pair Your Xbox Elite Series 2"),
                tagline: loc("Xbox Elite Wireless Controller Series 2"),
                systemImage: systemImage,
                bluetoothSteps: [
                    loc("Press the **Xbox button** to turn the controller on."),
                    loc("Hold the **Pair button** on top (beside the charge port) for ~3 seconds, until the Xbox button flashes rapidly."),
                    loc("On your Mac, open **System Settings → Bluetooth**."),
                    loc("Click **Connect** next to **Xbox Elite Wireless Controller**.")
                ],
                wiredNote: loc("A USB-C cable also works and charges at the same time."),
                tip: loc("The Elite Series 2 pairs exactly like a standard Xbox controller. Back paddles map just like any other button once connected."),
                guideURL: PairingGuideURL.xbox,
                pairingButtons: [.xbox]
            )

        case .dualSense:
            return ControllerPairingGuide(
                title: loc("Pair Your DualSense"),
                tagline: loc("PS5 DualSense Wireless Controller"),
                systemImage: systemImage,
                bluetoothSteps: [
                    loc("If the controller is on, hold the **PS button** ~10 seconds until the light bar turns off — it must be off first."),
                    loc("Hold the **Create button** (small button left of the touchpad) **and the PS button** together for ~3 seconds, until the light bar flashes blue."),
                    loc("On your Mac, open **System Settings → Bluetooth**."),
                    loc("Click **Connect** next to **DualSense Wireless Controller**.")
                ],
                wiredNote: loc("Or just plug in a USB-C cable — it works immediately with no pairing."),
                nativeSupportNote: loc("Native DualSense support requires macOS 11.3 or later."),
                guideURL: PairingGuideURL.ps5,
                // Create button (left of touchpad) + PS button.
                pairingButtons: [.view, .xbox]
            )

        case .dualSenseEdge:
            return ControllerPairingGuide(
                title: loc("Pair Your DualSense Edge"),
                tagline: loc("PS5 DualSense Edge Wireless Controller"),
                systemImage: systemImage,
                bluetoothSteps: [
                    loc("If the controller is on, hold the **PS button** ~10 seconds until the light bar turns off."),
                    loc("Hold the **Create button** (left of the touchpad) **and the PS button** together for ~3 seconds, until the light bar flashes blue."),
                    loc("On your Mac, open **System Settings → Bluetooth**."),
                    loc("Click **Connect** next to **DualSense Edge Wireless Controller**.")
                ],
                wiredNote: loc("A USB-C cable also works instantly. The Edge's braided cable has a locking connector — press the release to unplug."),
                tip: loc("Edge paddles and Fn buttons appear automatically once connected."),
                nativeSupportNote: loc("Native support requires macOS 13 Ventura or later."),
                guideURL: PairingGuideURL.ps5,
                pairingButtons: [.view, .xbox]
            )

        case .dualShock:
            return ControllerPairingGuide(
                title: loc("Pair Your DualShock 4"),
                tagline: loc("PS4 DualShock 4 Wireless Controller"),
                systemImage: systemImage,
                bluetoothSteps: [
                    loc("With the controller off, hold the **Share button and the PS button** together for ~3 seconds."),
                    loc("The light bar flashes white in double-pulses — it's now discoverable."),
                    loc("On your Mac, open **System Settings → Bluetooth**."),
                    loc("Click **Connect** next to **Wireless Controller**.")
                ],
                wiredNote: loc("Or connect a Micro-USB cable for a wired, lower-latency link."),
                nativeSupportNote: loc("Native DualShock 4 support requires macOS 11 Big Sur or later."),
                guideURL: PairingGuideURL.ps5,
                // Share button + PS button.
                pairingButtons: [.view, .xbox]
            )

        case .nintendo:
            return ControllerPairingGuide(
                title: loc("Pair Your Switch Pro Controller"),
                tagline: loc("Nintendo Switch Pro Controller or Joy-Con"),
                systemImage: systemImage,
                bluetoothSteps: [
                    loc("Hold the small **sync button** on top (next to the USB-C port) until the player LEDs run back and forth."),
                    loc("On your Mac, open **System Settings → Bluetooth**."),
                    loc("Under **Nearby Devices**, select **Pro Controller** to connect.")
                ],
                wiredNote: loc("A USB-C cable connects too, but macOS reads Switch controllers reliably only over Bluetooth — wireless is recommended."),
                tip: loc("Joy-Con: hold the small **sync button** on the side rail (between SR and SL) until the LEDs run. Pair each Joy-Con separately."),
                nativeSupportNote: loc("Native Nintendo support requires macOS 13 Ventura or later.")
            )

        case .steam:
            return ControllerPairingGuide(
                title: loc("Pair Your Steam Controller"),
                tagline: loc("Valve Steam Controller over Bluetooth LE"),
                systemImage: systemImage,
                bluetoothSteps: [
                    loc("With the controller off, hold the **Steam button and the B button** together to power on directly into Bluetooth LE pairing mode."),
                    loc("The Steam button blinks while it's discoverable."),
                    loc("On your Mac, open **System Settings → Bluetooth**."),
                    loc("Select the **Steam Controller** under Nearby Devices.")
                ],
                wiredNote: loc("Or plug in the USB wireless dongle (2.4 GHz) — it connects without any Bluetooth pairing."),
                tip: loc("If **Steam + B** doesn't work on your hardware revision, try holding **Y** while pressing the Steam button."),
                // Steam button (guide) + B face button.
                pairingButtons: [.xbox, .b]
            )

        case .eightBitDoZero2:
            // The keychain-sized Zero 2 picks its mode with a startup button
            // combo, and each mode presents as a *different* device to macOS.
            return ControllerPairingGuide(
                title: loc("Pair Your 8BitDo Zero 2"),
                tagline: loc("8BitDo Zero 2 — choose a startup mode"),
                systemImage: systemImage,
                bluetoothSteps: [
                    loc("Power on by holding a mode button **+ Start**. For this Zero 2 layout, use **Android / D-input**: hold **B + Start** until the LED blinks."),
                    loc("On your Mac, open **System Settings → Bluetooth**."),
                    loc("Connect to **8BitDo Zero 2** under Nearby Devices.")
                ],
                wiredNote: loc("A USB-C cable works wired too."),
                tip: loc("The Zero 2 has three Mac-ready modes — hold the button while powering on with **Start**: **B** = Android/D-input (pairs as an *8BitDo Zero 2*, matching this layout), **Y** = Switch (pairs as a *Switch Pro Controller*), **A** = macOS (pairs as a *DualShock 4*). All three work with ControllerKeys."),
                // Android / D-input startup combo: B + Start. (Start = +/menu.)
                pairingButtons: [.b, .menu]
            )
        case .eightBitDoMicro:
            return Self.eightBitDoSwitchSelectorGuide(model: "Micro", systemImage: systemImage)
        case .eightBitDoLite2:
            return Self.eightBitDoSwitchSelectorGuide(model: "Lite 2", systemImage: systemImage)
        case .eightBitDoLiteSE:
            return Self.eightBitDoSwitchSelectorGuide(model: "Lite SE", systemImage: systemImage)

        case .appleTVRemote:
            return ControllerPairingGuide(
                title: loc("Pair Your Siri Remote"),
                tagline: loc("Apple TV Siri Remote (2nd or 3rd gen)"),
                systemImage: systemImage,
                bluetoothSteps: [
                    loc("If you have an Apple TV nearby, **unplug it first** — the remote has to disconnect from the Apple TV before it can pair to your Mac."),
                    loc("On the remote, hold **Volume Up (+) and the Back button** together until it enters pairing mode."),
                    loc("On your Mac, open **System Settings → Bluetooth**."),
                    loc("Select the remote under **Nearby Devices** to connect — it joins as a Bluetooth HID device.")
                ],
                tip: loc("Keep the Apple TV unplugged for the whole pairing process so the remote doesn't reconnect to it mid-pair."),
                // Volume Up (+) + Back button.
                pairingButtons: [.appleTVRemoteVolumeUp, .view]
            )
        }
    }

    /// The 8BitDo Micro, Lite 2, and Lite SE carry a physical **S / D** mode
    /// slider (rather than the Zero 2's startup button combos): **S** pairs as a
    /// Switch Pro Controller, **D** (D-input / Android) pairs as the 8BitDo pad
    /// itself — which is what makes the per-model minimap resolve. The model name
    /// is a `%@` argument (untranslated) so all three pads share one set of keys.
    private static func eightBitDoSwitchSelectorGuide(model: String, systemImage: String) -> ControllerPairingGuide {
        ControllerPairingGuide(
            title: String(format: loc("Pair Your 8BitDo %@"), model),
            tagline: String(format: loc("8BitDo %@ — set the S/D mode switch"), model),
            systemImage: systemImage,
            bluetoothSteps: [
                String(format: loc("Slide the bottom **mode switch to D** (D-input) so it pairs as an 8BitDo %@, then turn it on — an LED blinks."), model),
                loc("Hold the **Pair button** (next to the USB-C port) for ~3 seconds, until the LED blinks rapidly."),
                loc("On your Mac, open **System Settings → Bluetooth**."),
                String(format: loc("Connect to **8BitDo %@** under Nearby Devices."), model)
            ],
            wiredNote: loc("A USB-C cable works wired too."),
            tip: String(format: loc("Bottom switch: **D** = D-input/Android (pairs as an *8BitDo %@*, matching this layout); **S** = Switch mode (pairs as a *Switch Pro Controller*). Both work with ControllerKeys."), model)
        )
    }
}
