import SwiftUI
import AppKit

/// Shown once on first launch: explains the free trial and lets customers who
/// already bought on Gumroad paste their key and activate immediately.
struct TrialWelcomeSheet: View {
    @ObservedObject private var license = LicenseManager.shared
    var onDone: () -> Void
    /// Which surface presented this sheet (expired_sheet, locked_toggle,
    /// menubar_expired, expiry_notification) — flows into paywall/checkout
    /// telemetry so each entry point's conversion is separately measurable.
    var paywallSurface: String = "expired_sheet"
    /// True when opened from a purchase-intent surface (notification click,
    /// menu-bar row, locked toggle). The sheet then leads with the priced buy
    /// button even while the trial is still live — a last-day notification
    /// promising "buy or enter a license" must not land on a first-run layout
    /// whose primary action is "Start Free Trial".
    var emphasizeBuy: Bool = false

    @State private var licenseKeyInput = ""
    @State private var isVerifying = false
    @State private var message: String?
    @State private var messageIsError = false

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)

            VStack(spacing: 6) {
                Text("Welcome to ControllerKeys")
                    .font(.title2.bold())
                Text(headline)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 8) {
                if isExpired {
                    Label("Your profiles and settings are untouched — activate to pick up where you left off.", systemImage: "checkmark.circle.fill")
                    Label("One-time purchase, no subscription. Use it on all your Macs.", systemImage: "laptopcomputer.and.iphone")
                } else {
                    Label("Full access during your free trial — no account needed.", systemImage: "checkmark.circle.fill")
                    Label("Map any controller to keys, mouse, macros, scripts, and more.", systemImage: "gamecontroller.fill")
                }
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Existing customers
            VStack(alignment: .leading, spacing: 8) {
                Text("Already purchased on Gumroad?")
                    .font(.callout.weight(.semibold))
                Text("Find your license key in your Gumroad receipt or library, then paste it here to activate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    TextField("License key", text: $licenseKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .disableAutocorrection(true)
                        .onSubmit { activate() }
                    Button {
                        activate()
                    } label: {
                        if isVerifying {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Activate")
                        }
                    }
                    .disabled(isVerifying || licenseKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if URL(string: Config.updateCheckGumroadURL) != nil {
                    Button("Get your license key on Gumroad") {
                        openCheckout(surface: "trial_welcome_link")
                    }
                        .buttonStyle(.link)
                        .font(.caption)
                }

                if let message {
                    Label(message, systemImage: messageIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(messageIsError ? .red : .green)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))

            if showsBuyPrimary {
                // Expired or purchase-intent: buying is the primary action;
                // dismissing is quiet. The price is on the button so the ask
                // is concrete before the checkout page loads.
                Button {
                    openCheckout(surface: paywallSurface)
                } label: {
                    Text(String(format: String(localized: "Buy ControllerKeys — %@"), Config.licensePriceDisplay))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                Button("Not Now") {
                    onDone()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            } else {
                Button {
                    onDone()
                } label: {
                    Text(license.isLicensed ? "Continue" : "Start Free Trial")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear {
            if showsBuyPrimary {
                TelemetryService.shared.paywallViewed(surface: paywallSurface)
            } else if !license.isLicensed {
                TelemetryService.shared.trialWelcomeViewed()
            }
            // This sheet is the user-attributable moment to ask for
            // notification consent — it's the surface that talks about the
            // trial the notifications track. The notifier itself never
            // prompts (an hourly timer at login isn't attributable).
            if !license.isLicensed {
                UserNotificationHub.shared.requestAuthorizationIfNeeded()
            }
        }
    }

    private var isExpired: Bool {
        if case .expired = license.status { return true }
        return false
    }

    /// Buy leads whenever the trial is over, or the user arrived via a
    /// purchase-intent surface while still trialing.
    private var showsBuyPrimary: Bool {
        isExpired || (emphasizeBuy && !license.isLicensed)
    }

    private var headline: String {
        switch license.status {
        case .licensed:
            return String(localized: "Your license is active — you're all set.")
        case .trial(let days):
            return String(format: String(localized: "You're on a %lld-day free trial with full access."), days)
        case .expired:
            return String(localized: "Your free trial has ended. Enter a license key to keep using ControllerKeys.")
        }
    }

    private func activate() {
        let key = licenseKeyInput
        guard !key.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isVerifying = true
        message = nil
        Task {
            let result = await license.verify(key: key)
            isVerifying = false
            message = result.message
            messageIsError = !result.success
            if result.success {
                onDone()
            }
        }
    }

    private func openCheckout(surface: String) {
        guard let url = URL(string: Config.updateCheckGumroadURL) else { return }
        if NSWorkspace.shared.open(url) {
            TelemetryService.shared.checkoutOpened(surface: surface)
        }
    }
}
