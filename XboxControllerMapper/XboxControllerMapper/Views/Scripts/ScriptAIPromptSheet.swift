import SwiftUI
import AppKit

struct ScriptAIPromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var userDescription: String = ""
    @State private var copied = false

    private let inspirationChips: [InspirationChip] = [
        InspirationChip("Toggle mute in different apps"),
        InspirationChip("Open a specific app and type something"),
        InspirationChip("Cycle through a list of actions"),
        InspirationChip("Different behavior per button"),
        InspirationChip("Search the selected text online"),
        InspirationChip("Take a screenshot and notify me"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Generate with AI")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Describe what you want the script to do, then copy the prompt and paste it into ChatGPT, Claude, or any AI assistant.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    // User description
                    VStack(alignment: .leading, spacing: 4) {
                        Text("What should the script do?")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        TextEditor(text: $userDescription)
                            .font(.system(size: 13))
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .frame(minHeight: 80, maxHeight: 120)
                            .background(Color.black.opacity(0.2))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                            .overlay(alignment: .topLeading) {
                                if userDescription.isEmpty {
                                    Text("e.g. \"When I press the button in Safari, bookmark the page. In other apps, do nothing.\"")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary.opacity(0.4))
                                        .padding(12)
                                        .allowsHitTesting(false)
                                }
                            }
                    }

                    // Inspiration chips
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ideas:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        FlowLayout(data: inspirationChips, spacing: 6) { chip in
                            Button(action: { userDescription = chip.text }) {
                                Text(chip.text)
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.8))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.white.opacity(0.08))
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // What gets copied
                    VStack(alignment: .leading, spacing: 4) {
                        Text("The copied prompt will include:")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.6))

                        VStack(alignment: .leading, spacing: 2) {
                            promptIncludesRow("Your description above")
                            promptIncludesRow("Complete API reference (all functions)")
                            promptIncludesRow("Common macOS key codes")
                            promptIncludesRow("Variable expansion list")
                            promptIncludesRow("Controller button names")
                            promptIncludesRow("Example scripts for context")
                        }
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Spacer()

                Button(action: copyPrompt) {
                    Label(copied ? "Copied!" : "Copy Prompt", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(userDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .frame(width: 520, height: 500)
    }

    private func promptIncludesRow(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 9))
                .foregroundColor(.green.opacity(0.6))
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
        }
    }

    private func copyPrompt() {
        let prompt = buildPrompt()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }

    private func buildPrompt() -> String {
        let description = userDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        return """
        Write a JavaScript script for ControllerKeys (a macOS app that maps game controller buttons to actions).

        ## What the script should do

        \(description)

        ## Rules

        - Write top-level JavaScript code (no exports, no modules, no async/await)
        - The script runs in JavaScriptCore (no DOM, no fetch, no Node.js APIs)
        - Use delay() between sequential actions that interact with the UI (e.g., opening an app then typing)
        - delay() max is 5 seconds
        - shell() has a 5-second timeout and returns stdout as a string
        - paste() is preferred over type() for long text (it uses the clipboard)
        - Return ONLY the JavaScript code, no markdown fences

        ## Complete API Reference

        ### Input Simulation
        - press(keyCode) — Press a key by macOS key code
        - press(keyCode, {command: true, shift: true, option: true, control: true}) — Press with modifiers
        - hold(keyCode, seconds) — Hold a key for a duration
        - click() — Left mouse click. Also: click("right"), click("middle")
        - type("text") — Type text character by character
        - paste("text") — Paste text via clipboard (preserves original clipboard)
        - pressKey("name") — Press a named key (see Named Keys below)
        - pressKey("name", {command: true}) — Named key with modifiers

        ### Application Context
        - app.name — Frontmost app display name (e.g., "Safari")
        - app.bundleId — Frontmost app bundle ID (e.g., "com.apple.Safari")
        - app.is("com.apple.Safari") — Check if a specific app is focused

        ### System
        - clipboard.get() — Read clipboard text
        - clipboard.set("text") — Set clipboard text
        - shell("command") — Run shell command, returns stdout (5s timeout)
        - openURL("https://...") — Open URL in default browser
        - openApp("com.apple.Safari") — Launch app by bundle ID
        - expand("template") — Expand variables in template string (see Variables below)
        - delay(seconds) — Pause execution (max 5 seconds)

        ### Persistent State (survives across button presses)
        - state.get("key") — Read a stored value
        - state.set("key", value) — Store any value
        - state.toggle("key") — Toggle a boolean, returns the new value

        ### Feedback
        - haptic() — Default haptic feedback. Also: haptic("light"), haptic("heavy")
        - notify("message") — Show a floating HUD notification on screen

        ### Trigger Context (read-only, set by the system)
        - trigger.button — Which button triggered this: "a", "b", "x", "y", "leftBumper", "rightBumper", "leftTrigger", "rightTrigger", "dpadUp", "dpadDown", "dpadLeft", "dpadRight", "menu", "view", "share", "xbox", "leftThumbstick", "rightThumbstick"
        - trigger.pressType — "press", "longHold", or "doubleTap"
        - trigger.holdDuration — Hold duration in seconds (only for longHold)

        ### Logging
        - log("message") — Log for debugging (visible in input log)

        ## Named Keys (for pressKey())
        space, return, enter, tab, escape, esc, delete, backspace, forwarddelete,
        up, down, left, right, home, end, pageup, pagedown,
        f1-f15, volumeup, volumedown, mute

        ## Common macOS Key Codes
        0=A, 1=S, 2=D, 3=F, 4=H, 5=G, 6=Z, 7=X, 8=C, 9=V,
        11=B, 12=Q, 13=W, 14=E, 15=R, 16=Y, 17=T, 18=1, 19=2,
        20=3, 21=4, 22=6, 23=5, 24==, 25=9, 26=7, 27=-, 28=8,
        29=0, 30=], 31=O, 32=U, 33=[, 34=I, 35=P, 37=L, 38=J,
        39=', 40=K, 41=;, 42=\\, 43=,, 44=/, 45=N, 46=M, 47=.,
        49=Space, 50=`, 51=Delete, 53=Escape, 36=Return, 48=Tab

        ## expand() Variables
        {date}, {date.us}, {date.eu}, {date.long}, {date.short}, {date.year},
        {date.month}, {date.month.name}, {date.day}, {date.weekday},
        {date.yesterday}, {date.tomorrow}, {date.week}, {date.quarter},
        {time}, {time.12}, {time.short}, {time.hour}, {time.minute}, {time.second},
        {datetime}, {datetime.long}, {time.iso}, {unix},
        {clipboard}, {selection}, {hostname}, {username},
        {app}, {app.bundle}, {home}, {desktop}, {downloads},
        {newline}, {tab}, {uuid}, {random}

        ## Example Scripts

        ### App-Aware Paste
        ```
        if (app.is("com.apple.Terminal") || app.is("com.googlecode.iterm2")) {
            press(9, {control: true, shift: true});
        } else {
            press(9, {command: true});
        }
        ```

        ### Quick Note with Timestamp
        ```
        openApp("com.apple.Notes");
        delay(0.5);
        press(45, {command: true});
        delay(0.3);
        paste(expand("--- {date} {time} ---\\n"));
        ```

        ### Cycle Through URLs
        ```
        var sites = [
            "https://news.ycombinator.com",
            "https://reddit.com",
            "https://github.com"
        ];
        var idx = state.get("siteIndex") || 0;
        openURL(sites[idx]);
        state.set("siteIndex", (idx + 1) % sites.length);
        ```
        """
    }
}

// MARK: - Inspiration Chip

private struct InspirationChip: Identifiable {
    let id = UUID()
    let text: String
    init(_ text: String) { self.text = text }
}
