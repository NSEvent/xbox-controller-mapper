import Foundation

/// Example scripts showcasing different API capabilities
struct ScriptExample: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let source: String
    let icon: String       // SF Symbol name
    let tags: [String]     // API highlights
}

enum ScriptExamplesData {
    static let all: [ScriptExample] = [
        ScriptExample(
            name: "App-Aware Paste",
            description: "Pastes with Cmd+V in most apps, but uses Ctrl+Shift+V in Terminal to avoid escape codes.",
            source: """
                if (app.is("com.apple.Terminal") || app.is("com.googlecode.iterm2")) {
                    press(9, {control: true, shift: true}); // Ctrl+Shift+V
                } else {
                    press(9, {command: true}); // Cmd+V
                }
                """,
            icon: "doc.on.clipboard",
            tags: ["app.is()", "press()"]
        ),

        ScriptExample(
            name: "Quick Note with Timestamp",
            description: "Opens Apple Notes and pastes a timestamped entry.",
            source: """
                openApp("com.apple.Notes");
                delay(0.5);
                // Cmd+N for new note
                press(45, {command: true});
                delay(0.3);
                paste(expand("--- {date} {time} ---\\n"));
                """,
            icon: "note.text.badge.plus",
            tags: ["openApp()", "expand()", "paste()"]
        ),

        ScriptExample(
            name: "Toggle Mute (Zoom/Meet)",
            description: "Mutes/unmutes in Zoom or Google Meet with the right shortcut for each app.",
            source: """
                if (app.is("us.zoom.xos")) {
                    press(0, {command: true, shift: true}); // Cmd+Shift+A
                    var muted = state.toggle("zoom_muted");
                    notify(muted ? "Muted" : "Unmuted");
                    haptic(muted ? "heavy" : "light");
                } else if (app.bundleId.includes("google.Chrome")) {
                    press(2, {command: true}); // Cmd+D (Meet toggle)
                    notify("Toggled mic");
                } else {
                    notify("Not in a meeting app");
                }
                """,
            icon: "mic.slash",
            tags: ["state.toggle()", "app.is()", "haptic()", "notify()"]
        ),

        ScriptExample(
            name: "Screenshot to Clipboard",
            description: "Takes a screenshot of a selected region and copies it to the clipboard. Uses shellAsync so controller input isn't blocked during selection.",
            source: """
                shellAsync("screencapture -ic", function() {
                    notify("Screenshot copied!");
                    haptic();
                });
                """,
            icon: "camera.viewfinder",
            tags: ["shellAsync()", "notify()"]
        ),

        ScriptExample(
            name: "Window Snap Left/Right",
            description: "Snaps the current window left on D-pad Left, right on D-pad Right. Uses macOS Sequoia window tiling.",
            source: """
                if (trigger.button === "dpadLeft") {
                    // Ctrl+Globe+Left for left half
                    press(123, {control: true, option: true});
                } else if (trigger.button === "dpadRight") {
                    // Ctrl+Globe+Right for right half
                    press(124, {control: true, option: true});
                }
                """,
            icon: "rectangle.split.2x1",
            tags: ["trigger.button", "press()"]
        ),

        ScriptExample(
            name: "Search Selected Text",
            description: "Copies the selected text and searches for it in your default browser.",
            source: """
                // Copy selection
                press(8, {command: true}); // Cmd+C
                delay(0.2);
                var text = clipboard.get();
                if (text && text.length > 0) {
                    openURL("https://www.google.com/search?q=" + encodeURIComponent(text));
                } else {
                    notify("No text selected");
                }
                """,
            icon: "magnifyingglass",
            tags: ["clipboard.get()", "openURL()", "press()"]
        ),

        ScriptExample(
            name: "Cycle Through URLs",
            description: "Each press opens the next URL in a list. Cycles back to the start.",
            source: """
                var sites = [
                    "https://news.ycombinator.com",
                    "https://reddit.com",
                    "https://github.com"
                ];
                var idx = state.get("siteIndex") || 0;
                openURL(sites[idx]);
                state.set("siteIndex", (idx + 1) % sites.length);
                """,
            icon: "arrow.triangle.2.circlepath",
            tags: ["state.get()", "state.set()", "openURL()"]
        ),

        ScriptExample(
            name: "Type Email Signature",
            description: "Pastes a formatted email signature with today's date.",
            source: """
                paste(expand("Best regards,\\n{username}\\n{date}"));
                """,
            icon: "envelope",
            tags: ["paste()", "expand()"]
        ),
    ]

    /// A few featured examples for the empty state
    static var featured: [ScriptExample] {
        Array(all.prefix(4))
    }
}
