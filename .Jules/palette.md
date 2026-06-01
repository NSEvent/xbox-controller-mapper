## 2024-05-18 - Missing Accessibility Labels for Icon-Only Buttons
**Learning:** Found several icon-only buttons (like Edit/Trash) in the UI that lack accessibility labels and tooltips, which are crucial for screen reader users and normal users to understand their function.
**Action:** Always add `.help("Description")` and `.accessibilityLabel("Description")` to icon-only buttons.
