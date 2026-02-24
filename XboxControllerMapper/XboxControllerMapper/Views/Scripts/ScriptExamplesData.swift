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
            name: "App-Aware Undo",
            description: "Sends Cmd+Z in most apps, but Cmd+Shift+Z in Photoshop (which uses Cmd+Z for toggle undo/redo).",
            source: """
                if (app.is("com.adobe.Photoshop")) {
                    press(6, {command: true, shift: true}); // Cmd+Shift+Z (step backward)
                } else {
                    press(6, {command: true}); // Cmd+Z
                }
                """,
            icon: "arrow.uturn.backward",
            tags: ["app.is()", "press()"]
        ),

        ScriptExample(
            name: "Quick Note with Timestamp",
            description: "Opens Apple Notes and pastes a timestamped entry.",
            source: """
                openApp("com.apple.Notes");
                delay(0.2);
                // Cmd+N for new note
                press(45, {command: true});
                delay(0.1);
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
            name: "Screenshot Window to Clipboard",
            description: "Captures the focused window and copies it to the clipboard.",
            source: """
                if (screenshotWindow()) {
                    notify("Copied to clipboard!");
                } else {
                    notify("Failed — check Screen Recording permission");
                }
                haptic();
                """,
            icon: "camera.viewfinder",
            tags: ["screenshotWindow()", "notify()", "haptic()"]
        ),

        ScriptExample(
            name: "Screenshot Window to Desktop",
            description: "Captures the focused window and saves it to the Desktop as a PNG.",
            source: """
                var ts = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
                var path = "~/Desktop/screenshot-" + ts + ".png";
                if (screenshotWindow(path)) {
                    notify("Saved to Desktop!");
                } else {
                    notify("Failed — check Screen Recording permission");
                }
                haptic();
                """,
            icon: "desktopcomputer",
            tags: ["screenshotWindow()", "notify()", "haptic()"]
        ),

        ScriptExample(
            name: "Window Snap Left/Right",
            description: "Snaps the current window left on D-pad Left, right on D-pad Right using Rectangle or similar window manager.",
            source: """
                if (trigger.button === "dpadLeft") {
                    // Ctrl+Option+Left (Rectangle: left half)
                    press(123, {control: true, option: true});
                } else if (trigger.button === "dpadRight") {
                    // Ctrl+Option+Right (Rectangle: right half)
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
                // Save current clipboard, then copy selection
                var before = clipboard.get();
                press(8, {command: true}); // Cmd+C
                delay(0.5);
                var after = clipboard.get();
                if (after !== before && after.length > 0) {
                    openURL("https://www.google.com/search?q=" + encodeURIComponent(after));
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

        ScriptExample(
            name: "Screenshot Region to Desktop",
            description: "Opens the interactive screenshot tool (Cmd+Shift+4) to select a window or region. Saves to the Desktop.",
            source: """
                var ts = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
                var path = expand("~/Desktop/screenshot-" + ts + ".png");
                shellAsync("screencapture -i " + path, function(result) {
                    if (result) {
                        notify("Screenshot saved to Desktop!");
                    } else {
                        notify("Screenshot cancelled");
                    }
                });
                haptic();
                """,
            icon: "crop",
            tags: ["shellAsync()", "notify()", "haptic()"]
        ),
    ]

    /// A few featured examples for the empty state
    static var featured: [ScriptExample] {
        Array(all.prefix(4))
    }
}
