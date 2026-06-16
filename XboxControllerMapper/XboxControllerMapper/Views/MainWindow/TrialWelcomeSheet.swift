import SwiftUI
import AppKit

/// Shown once on first launch: explains the free trial and lets customers who
/// already bought on Gumroad paste their key and activate immediately.
struct TrialWelcomeSheet: View {
    @ObservedObject private var license = LicenseManager.shared
    var onDone: () -> Void

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
                Label("Full access during your free trial — no account needed.", systemImage: "checkmark.circle.fill")
                Label("Map any controller to keys, mouse, macros, scripts, and more.", systemImage: "gamecontroller.fill")
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

                if let url = URL(string: Config.updateCheckGumroadURL) {
                    Link("Get your license key on Gumroad", destination: url)
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
        .padding(24)
        .frame(width: 460)
    }

    private var headline: String {
        switch license.status {
        case .licensed:
            return "Your license is active — you're all set."
        case .trial(let days):
            return "You're on a \(days)-day free trial with full access."
        case .expired:
            return "Your free trial has ended. Enter a license key to keep using ControllerKeys."
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
}
