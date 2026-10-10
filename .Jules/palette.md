## 2024-06-03 - Missing tooltips and accessibility on list item actions
**Learning:** Icon-only buttons used for item actions (like 'Edit', 'Delete', 'Remove') within list views often lack tooltips and accessibility labels. This omission makes the UI ambiguous for mouse users on macOS and inaccessible to screen readers.
**Action:** Always add `.help("Action Name")` and `.accessibilityLabel("Action Name Item Type")` to icon-only buttons, especially those located at the trailing edge of list rows.

## 2024-11-20 - Ensure Symmetry in Accessibility and Tooltips for SwiftUI Icon Buttons
**Learning:** In macOS SwiftUI applications, icon-only buttons often have either `.help()` (for hover tooltips) or `.accessibilityLabel()` (for VoiceOver), but frequently lack both. Both are necessary because they serve different user interaction models—`.help` for visual hover feedback and `.accessibilityLabel` for screen readers.
**Action:** When adding or reviewing icon-only buttons in SwiftUI, always ensure symmetry by defining both `.help("Description")` and `.accessibilityLabel("Description")` to cover all accessibility and usability vectors.
## 2026-06-06 - Ensure Symmetry in Accessibility and Tooltips for SwiftUI Icon Buttons
**Learning:** In macOS SwiftUI applications, icon-only buttons often have either `.help()` (for hover tooltips) or `.accessibilityLabel()` (for VoiceOver), but frequently lack both. Both are necessary because they serve different user interaction models—`.help` for visual hover feedback and `.accessibilityLabel` for screen readers.
**Action:** When adding or reviewing icon-only buttons in SwiftUI, always ensure symmetry by defining both `.help("Description")` and `.accessibilityLabel("Description")` to cover all accessibility and usability vectors.

## 2024-05-19 - [Missing Accessibility on Dynamic Form Dictionary Buttons]
**Learning:** Icon-only buttons used for adding/removing items in dynamic dictionary forms (e.g., webhook headers with `plus.circle.fill` and `minus.circle.fill`) are frequent vectors for missing accessibility labels and tooltips, because they are often implemented with plain button styles without considering screen reader context.
**Action:** Always verify that inline addition/removal buttons in repeated form elements have explicit `.help()` and `.accessibilityLabel()` modifiers attached to them to ensure they can be understood and navigated accurately by all users.
## 2024-05-14 - [Icon Button Accessibility Gap]
**Learning:** In standard SwiftUI development for macOS, icon-only buttons (`Image(systemName: ...)`) are frequently missing `.help()` (for hover tooltips) and `.accessibilityLabel()` (for VoiceOver). Several core navigation components (like Layer tabs and Sidebar buttons) suffered from this pattern.
**Action:** Always verify that every `Button` wrapping an `Image` has both `.help()` and `.accessibilityLabel()` strings defined, unless explicitly marked as decorative.

## 2024-06-08 - Ensure Symmetry in Accessibility and Tooltips for SwiftUI Icon Buttons
**Learning:** Verified the necessity of ensuring full symmetry in accessibility and tooltips for icon-only buttons (`Image(systemName: ...)`). These buttons often get one but not the other (`.help()` without `.accessibilityLabel()`, or vice-versa), which causes poor UX for some group of users.
**Action:** When adding or modifying icon buttons, always apply both `.help("Action")` and `.accessibilityLabel("Action")`.
## 2026-06-16 - Ensure Symmetry in Accessibility and Tooltips for SwiftUI Icon Buttons
**Learning:** Verified the necessity of ensuring full symmetry in accessibility and tooltips for icon-only buttons (`Image(systemName: ...)`). These buttons often get one but not the other (`.help()` without `.accessibilityLabel()`, or vice-versa), which causes poor UX for some group of users.
**Action:** When adding or modifying icon buttons, always apply both `.help("Action")` and `.accessibilityLabel("Action")`.
## 2026-06-23 - [SwiftUI Button Accessibility]
**Learning:** Found a pattern where SwiftUI icon-only buttons or minimal UI elements were given `.help()` modifiers for hover tooltips but lacked `.accessibilityLabel()` modifiers for screen readers.
**Action:** When adding `.help()` to buttons, always pair it with a corresponding `.accessibilityLabel()` to ensure full accessibility.

## 2024-07-12 - [Dynamic Accessibility Labels for List Item Actions]
**Learning:** Icon-only buttons (like Edit/Delete) inside lists pose a major accessibility challenge for VoiceOver users when identical labels ("Edit") are repeated without context, making it impossible to know which row is being acted on.
**Action:** Always interpolate the dynamic item context (e.g., `item.name`) into both `.help()` tooltips and `.accessibilityLabel()` modifiers in repeated SwiftUI lists. Include fallback text for empty states (e.g., `"Unnamed Item"`).
## 2024-08-08 - Use Button instead of .onTapGesture for Accessibility
**Learning:** In SwiftUI, attaching `.onTapGesture` directly to structural views (like `HStack` or `VStack`) makes them interactive for mouse/touch users but entirely opaque to keyboard navigation (Tab key) and screen readers (VoiceOver). This is a major accessibility failure for lists and interactive cards.
**Action:** When a view needs to act as a button, always wrap its contents in a `Button(action: {})` and apply `.buttonStyle(.plain)` if you need to preserve custom styling. Also, remember to include `.contentShape(Rectangle())` inside the button if you need empty space to remain tappable.

## 2024-05-18 - [SwiftUI Button Accessibility]
**Learning:** Using `.onTapGesture` on generic views like `HStack` prevents interactive elements from properly supporting keyboard focus and VoiceOver accessibility.
**Action:** Always wrap interactive list rows in a `Button` with `.buttonStyle(.plain)` instead of attaching `.onTapGesture` to views, ensuring `.contentShape(Rectangle())` is applied within the button to maintain the clickable area.
## 2024-07-28 - Do not wrap list rows containing explicit action buttons
**Learning:** In SwiftUI, wrapping a list row containing an `.onTapGesture` in a transparent `Button` to make it accessible to VoiceOver can create a 'Ghost Tab Stop' and redundant screen reader announcements if the row *already* contains explicit action buttons (like Edit or Delete icons). This degrades the keyboard navigation experience by creating invisible focus points and requiring double-tabbing.
**Action:** When evaluating `.onTapGesture` accessibility, check if the list row already has adjacent, explicit action buttons. If it does, leave the `.onTapGesture` as a pointer convenience. Ensure accessibility by adding context to the explicit buttons (e.g., using `item.name` in their `.help()` and `.accessibilityLabel()`) rather than making the entire row focusable.
||||||| 9353de56
## 2024-05-13 - [Icon Button Accessibility Gap in Modals and Sheets]
**Learning:** Found a pattern where small UI utility elements, like dismiss buttons (`xmark`) in floating sheets (`FeedbackKit.swift`) or selection toggles in lists (`CommunityProfilePreview.swift`), are implemented as icon-only buttons but completely lack `.help()` tooltips and/or `.accessibilityLabel()`.
**Action:** Always verify that every `Button` wrapping an `Image` without accompanying text has both `.help()` and `.accessibilityLabel()` defined to ensure full accessibility and usability across all input methods.
||||||| f1ceae4c
## 2024-08-30 - Replace .onTapGesture with Button for A11y
**Learning:** Using `.onTapGesture` prevents interactive UI elements from being focusable by VoiceOver and keyboard navigation. Wrapping them in a `Button` with `.buttonStyle(.plain)` restores full accessibility and interactive traits.
**Action:** When making custom views tappable (like custom rows or list items), use `Button(action:)` combined with `.buttonStyle(.plain)` instead of `.onTapGesture`. Ensure `.contentShape(Rectangle())` is applied to maintain the hit area.
## 2026-09-26 - [Maintainer] Do NOT convert draggable rows to Buttons
**Rule:** Rows inside `.onMove` / `.onDrag` containers (chord & sequence lists, profile sidebar, macro steps, command wheel actions) intentionally use `.onTapGesture`. Wrapping them in a `Button` can swallow the mouse-down that starts a drag on macOS, and each row already has an explicit, labeled Edit button for keyboard/VoiceOver users. Never wrap a view that contains its own buttons in another `Button`. PRs doing either will be closed.
## 2026-09-26 - [Maintainer] Stay in scope; never touch debug logging
**Rule:** Do not delete or comment out `#if DEBUG` `print` statements (MappingEngine, LED, ProfileManager, etc.) and do not commit helper scripts. Each PR must change only the files its title describes. Do not add labels/tooltips to buttons that already show the same visible text.

## 2024-10-25 - [Dynamic Context in List Iteration Actions]
**Learning:** Generic accessibility labels and tooltips (e.g., "Delete", "Move up") on icon buttons repeated inside list/ForEach loops offer no context. VoiceOver announces "Delete, Button" multiple times, forcing the user to deduce which item it targets based on focus order.
**Action:** Always interpolate the looped item's specific context (e.g., `item.displaySummary` or `item.name`) into both `.help()` and `.accessibilityLabel()` modifiers for icon-only action buttons inside loops.

## 2024-10-25 - [Maintainer] Stay in scope; never touch debug logging
**Rule:** When assigned to fix an unrelated CI failure (like a deadlock due to excessive `print` statements in a high-frequency backend component), strictly adhere to the agent boundaries: never change backend logic or performance code. Complete all in-scope work, run pre-commit verification, and submit the PR normally. Do not attempt to fix the CI failure.
