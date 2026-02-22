# UI Patterns

Constraints and patterns for SwiftUI views that resist unit testing.

---

## Every dialog must support Escape and Cmd+Return

All sheets, alerts, and modal dialogs must have:
- **Escape** to cancel/dismiss: `.keyboardShortcut(.cancelAction)` on the Cancel or Done button
- **Cmd+Return** to save/confirm: `.keyboardShortcut(.return, modifiers: .command)` on the primary action button

Use `.keyboardShortcut(.return, modifiers: .command)` explicitly, not `.keyboardShortcut(.defaultAction)`. The `.defaultAction` shortcut binds to plain Return, which conflicts with TextField input (pressing Return in a text field would trigger the save button instead of inserting a newline or submitting the field).

**Why this matters:** Users operate the app with a game controller. Controller buttons map to keyboard shortcuts. If a dialog doesn't respond to Escape or Cmd+Return, users get stuck in modal dialogs with no way out.

**Why tests can't catch this:** Keyboard shortcut registration is a SwiftUI modifier side effect. No unit test can verify that a `.keyboardShortcut` modifier is attached to a button.

### Do not use native `.alert()` for text input

Native SwiftUI `.alert()` dialogs have unreliable Escape handling on macOS when they contain TextFields. Convert any alert with a TextField to a custom `.sheet()` with explicit Cancel and Save buttons that have keyboard shortcuts.

```swift
// BAD: native alert with text input
.alert("Rename", isPresented: $showing) {
    TextField("Name", text: $name)
    Button("Cancel", role: .cancel) { }
    Button("Rename") { save() }
}

// GOOD: custom sheet with keyboard shortcuts
.sheet(isPresented: $showing) {
    VStack {
        TextField("Name", text: $name)
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Rename") { save(); dismiss() }
                .keyboardShortcut(.return, modifiers: .command)
        }
    }
}
```

---

## Set state before presenting sheets

When a sheet depends on state (e.g., prefilling a form), set the state **before** triggering the sheet presentation. SwiftUI's `.sheet(isPresented:)` may evaluate its content closure before all state changes in the same render pass have propagated. If the sheet reads stale state in `.onAppear`, it will appear blank.

```swift
// BAD: state and presentation in the same synchronous block
prefilledData = data
showingSheet = true  // sheet may capture prefilledData as nil

// GOOD: defer presentation to the next render cycle
prefilledData = data
DispatchQueue.main.async {
    showingSheet = true
}
```

**When dismissing one sheet to present another** (e.g., gallery → editor), use `onDismiss` instead of setting both booleans simultaneously. SwiftUI cannot present two sheets from the same view at once.

```swift
// BAD: two sheets from the same view simultaneously
.sheet(isPresented: $showingGallery) {
    GalleryView { item in
        selectedItem = item
        showingEditor = true  // ignored: gallery sheet is still visible
    }
}

// GOOD: chain via onDismiss
.sheet(isPresented: $showingGallery, onDismiss: {
    if selectedItem != nil {
        showingEditor = true
    }
}) {
    GalleryView { item in
        selectedItem = item
        // gallery dismisses itself; onDismiss triggers editor
    }
}
```

**Why tests can't catch this:** The bug manifests only in the SwiftUI rendering pipeline's state propagation timing. Unit tests don't run the render loop.

---

## Controller button display names respect controller type

When displaying button names in the UI, always use `button.displayName(forDualSense:)` with the current controller type. PlayStation controllers use different names (Cross/Circle/Square/Triangle vs A/B/X/Y). Hardcoding Xbox names breaks the experience for DualSense users.

---

## Sheet width should accommodate content type

Sheets that contain a visual keyboard (`KeyboardVisualView`) should expand to ~750pt width when the keyboard is visible. Use `.animation` on the frame to smooth the transition.

Sheets with system command fields (webhooks, OBS, shell commands) need ~580pt. Standard sheets use ~520pt.
