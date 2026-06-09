## 2024-06-03 - Missing tooltips and accessibility on list item actions
**Learning:** Icon-only buttons used for item actions (like 'Edit', 'Delete', 'Remove') within list views often lack tooltips and accessibility labels. This omission makes the UI ambiguous for mouse users on macOS and inaccessible to screen readers.
**Action:** Always add `.help("Action Name")` and `.accessibilityLabel("Action Name Item Type")` to icon-only buttons, especially those located at the trailing edge of list rows.

## 2024-11-20 - Ensure Symmetry in Accessibility and Tooltips for SwiftUI Icon Buttons
**Learning:** In macOS SwiftUI applications, icon-only buttons often have either `.help()` (for hover tooltips) or `.accessibilityLabel()` (for VoiceOver), but frequently lack both. Both are necessary because they serve different user interaction models—`.help` for visual hover feedback and `.accessibilityLabel` for screen readers.
**Action:** When adding or reviewing icon-only buttons in SwiftUI, always ensure symmetry by defining both `.help("Description")` and `.accessibilityLabel("Description")` to cover all accessibility and usability vectors.
## 2026-06-06 - Ensure Symmetry in Accessibility and Tooltips for SwiftUI Icon Buttons
**Learning:** In macOS SwiftUI applications, icon-only buttons often have either `.help()` (for hover tooltips) or `.accessibilityLabel()` (for VoiceOver), but frequently lack both. Both are necessary because they serve different user interaction models—`.help` for visual hover feedback and `.accessibilityLabel` for screen readers.
**Action:** When adding or reviewing icon-only buttons in SwiftUI, always ensure symmetry by defining both `.help("Description")` and `.accessibilityLabel("Description")` to cover all accessibility and usability vectors.
## 2026-06-09 - Found instances lacking symmetric accessibility labels
**Learning:** Found two icon-only buttons ("Add profile" in `ProfileSidebarViews.swift` and "Settings" in `ContentToolbar.swift`) that only had `.accessibilityLabel()` but lacked `.help()` for hover tooltips.
**Action:** Always ensure symmetry in accessibility modifiers on SwiftUI icon buttons by pairing `.accessibilityLabel()` with `.help()`.
