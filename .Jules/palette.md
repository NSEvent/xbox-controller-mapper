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
