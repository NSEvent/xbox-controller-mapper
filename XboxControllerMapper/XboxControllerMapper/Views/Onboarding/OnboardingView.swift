import SwiftUI
import AppKit

/// First-run guided permissions wizard.
///
/// Replaces the old behavior of firing every TCC prompt at launch with a
/// sequential flow: one permission at a time, each with an explanation and a
/// **live** status pill that flips to "Granted ✓" the moment the user toggles
/// the switch in System Settings (driven by `PermissionsManager.startPolling`).
/// Accessibility — the permission "prone to breaking" — gets a troubleshooting
/// disclosure and a relaunch fallback for the stale-TCC-after-update case.
struct OnboardingView: View {
    @ObservedObject private var permissions = PermissionsManager.shared
    /// Called when the user finishes (or skips through) the wizard.
    var onComplete: () -> Void

    @State private var step: OnboardingStep = .welcome
    @State private var showAccessibilityHelp = false
    @State private var bluetoothRequested = false

    private var stepState: OnboardingStepState {
        OnboardingStepState(
            accessibility: permissions.accessibility,
            inputMonitoring: permissions.inputMonitoring,
            bluetooth: permissions.bluetooth
        )
    }

    var body: some View {
        VStack(spacing: 18) {
            header

            Divider()

            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
            .frame(maxHeight: .infinity)

            footer
        }
        .padding(24)
        .frame(width: 480, height: 580)
        .onAppear {
            permissions.startPolling()
            // Re-running setup with everything already granted? Jump near the end
            // so the user isn't re-walked through prompts they've already handled.
            if stepState.firstIncompleteStep == .done {
                step = .done
            }
        }
        .onChange(of: permissions.accessibility) { _, _ in advancePastGrantedRequiredStepIfNeeded() }
        .onChange(of: permissions.inputMonitoring) { _, _ in advancePastGrantedRequiredStepIfNeeded() }
        .onDisappear { permissions.stopPolling() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)

            Text(headerTitle)
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            if step != .welcome && step != .done {
                progressDots
            }
        }
    }

    private var headerTitle: String {
        switch step {
        case .welcome: return "Welcome to ControllerKeys"
        case .accessibility: return "Allow Accessibility"
        case .inputMonitoring: return "Allow Input Monitoring"
        case .bluetooth: return "Bluetooth (Optional)"
        case .done: return "You're all set"
        }
    }

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.permissionSteps) { permissionStep in
                Circle()
                    .fill(permissionStep == step ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            welcomeContent
        case .accessibility:
            accessibilityContent
        case .inputMonitoring:
            inputMonitoringContent
        case .bluetooth:
            bluetoothContent
        case .done:
            doneContent
        }
    }

    private var welcomeContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ControllerKeys turns any game controller into a full keyboard and mouse for your Mac.")
                .font(.callout)

            Text("macOS needs your permission before the app can read your controller and control the pointer. We'll set these up one at a time — it takes about 30 seconds.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                upcomingRow(icon: "accessibility", title: "Accessibility", subtitle: "Required — move the mouse and press keys")
                upcomingRow(icon: "keyboard", title: "Input Monitoring", subtitle: "Required — read every controller type")
                upcomingRow(icon: "dot.radiowaves.left.and.right", title: "Bluetooth", subtitle: "Optional — wireless battery level")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
        }
    }

    private func upcomingRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var accessibilityContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusPill(for: permissions.accessibility)

            Text("Accessibility lets ControllerKeys move the pointer, click, and press keys on your behalf. **Without it the app can't do anything**, so this one is required.")
                .font(.callout)

            instructionList([
                "Click **Open System Settings** below.",
                "Turn on the switch next to **ControllerKeys**.",
                "**Don't see it in the list?** Drag the **ControllerKeys** icon below straight into the list (or click **+** there and pick it).",
                "Come back here — this page updates on its own."
            ])

            if permissions.accessibility != .granted {
                permissionActions(request: permissions.requestAccessibility)
            }

            DisclosureGroup("It's on but still says \u{201C}Needed\u{201D}?", isExpanded: $showAccessibilityHelp) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("macOS sometimes keeps a stale entry after an app update — the switch looks on but the running app still isn't trusted. Try, in order:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    instructionList([
                        "Toggle ControllerKeys **off and back on** in the list.",
                        "Or remove it with the **\u{2013}** button, then drag it back in (or use **+**).",
                        "Still stuck? Relaunch the app to pick up the change."
                    ], font: .caption)
                    Button("Relaunch ControllerKeys") { permissions.relaunchApp() }
                        .controlSize(.small)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
            .font(.callout)
        }
    }

    private var inputMonitoringContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusPill(for: permissions.inputMonitoring)

            Text("Input Monitoring lets ControllerKeys read input from **Steam controllers, generic USB/Bluetooth gamepads, the Apple TV remote, and the Xbox guide button**. Standard Xbox and PlayStation pads work without it, but granting it covers every controller.")
                .font(.callout)

            instructionList([
                "Click **Open System Settings** below.",
                "Turn on the switch next to **ControllerKeys**.",
                "**Don't see it in the list?** Drag the **ControllerKeys** icon below straight into the list (or click **+** there and pick it).",
                "Return here — the status updates automatically."
            ])

            if permissions.inputMonitoring != .granted {
                permissionActions(request: permissions.requestInputMonitoring)
            }
        }
    }

    private var bluetoothContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusPill(for: permissions.bluetooth)

            Text("Bluetooth is optional. It lets ControllerKeys show the **battery level** of wireless controllers (Xbox pads and the Apple TV remote). Skip it if you don't need battery readouts — you can enable it later in Settings.")
                .font(.callout)

            if permissions.bluetooth != .granted {
                Button {
                    permissions.requestBluetooth()
                    bluetoothRequested = true
                } label: {
                    Label("Enable Bluetooth", systemImage: "dot.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if bluetoothRequested && permissions.bluetooth == .denied {
                    Button("Open Bluetooth Settings") { permissions.openBluetoothSettings() }
                        .controlSize(.small)
                }
            }
        }
    }

    private var doneContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                Text("ControllerKeys is ready to go.")
                    .font(.title3.weight(.semibold))
            }

            grantedSummaryRow("Accessibility", state: permissions.accessibility)
            grantedSummaryRow("Input Monitoring", state: permissions.inputMonitoring)
            grantedSummaryRow("Bluetooth", state: permissions.bluetooth, optional: true)

            Text("You can revisit any of these anytime from **Settings \u{203A} Permissions**.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
    }

    private func grantedSummaryRow(_ title: String, state: PermissionState, optional: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: state == .granted ? "checkmark.circle.fill" : (optional ? "minus.circle" : "exclamationmark.triangle.fill"))
                .foregroundStyle(state == .granted ? .green : (optional ? .secondary : .orange))
            Text(title)
            Spacer()
            Text(state == .granted ? "Granted" : (optional ? "Skipped" : "Not granted"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if let previous = step.previous, step != .done {
                Button("Back") { withAnimation { step = previous } }
                    .controlSize(.large)
            }

            Spacer()

            if step.isRequired && !stepState.canAdvance(from: step) {
                Button("Skip for now") { goNext() }
                    .controlSize(.large)
            } else if step == .bluetooth && permissions.bluetooth != .granted {
                Button("Skip") { goNext() }
                    .controlSize(.large)
            }

            Button(primaryButtonTitle) {
                if step == .done { onComplete() } else { goNext() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!stepState.canAdvance(from: step))
        }
    }

    private var primaryButtonTitle: String {
        switch step {
        case .welcome: return "Get Started"
        case .done: return "Start Using ControllerKeys"
        default: return "Continue"
        }
    }

    // MARK: - Permission actions

    /// Shared action block for the Accessibility / Input Monitoring steps: the
    /// "Open System Settings" CTA plus a draggable app-icon well. Dragging the
    /// icon straight into the System Settings permission list is the reliable fix
    /// when macOS didn't auto-add ControllerKeys — it's equivalent to clicking
    /// "+" and picking the app, but without the file chooser.
    @ViewBuilder
    private func permissionActions(request: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Button {
                request()
            } label: {
                Label("Open System Settings", systemImage: "gear")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            HStack(spacing: 12) {
                DraggableAppIcon()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Not in the list?")
                        .font(.caption.weight(.semibold))
                    Text("Drag the icon at left into the permission list — or click **+** there and pick ControllerKeys.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Reveal in Finder instead") { permissions.revealAppInFinder() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
        }
    }

    // MARK: - Status pill

    private func statusPill(for state: PermissionState) -> some View {
        let granted = state == .granted
        let denied = state == .denied
        let title = granted ? "Granted" : (denied ? "Denied — turn it on in Settings" : "Waiting for permission\u{2026}")
        let symbol = granted ? "checkmark.circle.fill" : (denied ? "xmark.circle.fill" : "clock.fill")
        let color: Color = granted ? .green : (denied ? .red : .orange)
        return Label(title, systemImage: symbol)
            .font(.callout.weight(.semibold))
            .foregroundStyle(color)
    }

    private func instructionList(_ lines: [String], font: Font = .callout) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(index + 1).")
                        .font(font.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(.init(line))
                        .font(font)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Navigation

    private func goNext() {
        guard let next = step.next else { onComplete(); return }
        withAnimation { step = next }
    }

    /// When the user grants a required permission while sitting on its step, flip
    /// the page forward automatically so the flow feels responsive (the pill has
    /// already turned green; this just saves a click).
    private func advancePastGrantedRequiredStepIfNeeded() {
        switch step {
        case .accessibility where permissions.accessibility == .granted:
            goNext()
        case .inputMonitoring where permissions.inputMonitoring == .granted:
            goNext()
        default:
            break
        }
    }
}

/// The app's own icon, draggable straight out of the wizard and into a System
/// Settings permission list. The drag carries the app bundle as a file, so
/// dropping it on the Accessibility / Input Monitoring list adds ControllerKeys
/// exactly as the "+" button would.
private struct DraggableAppIcon: View {
    private var icon: NSImage { NSApp.applicationIconImage }

    var body: some View {
        VStack(spacing: 5) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 56, height: 56)
            Label("Drag me", systemImage: "arrow.up.forward.app")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                .foregroundStyle(.secondary.opacity(0.4))
        )
        // Provide the bundle as a file so the Settings list accepts the drop.
        .onDrag {
            NSItemProvider(contentsOf: Bundle.main.bundleURL) ?? NSItemProvider()
        } preview: {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 56, height: 56)
        }
    }
}
