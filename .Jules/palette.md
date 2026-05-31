## 2024-06-03 - Missing tooltips and accessibility on list item actions
**Learning:** Icon-only buttons used for item actions (like 'Edit', 'Delete', 'Remove') within list views often lack tooltips and accessibility labels. This omission makes the UI ambiguous for mouse users on macOS and inaccessible to screen readers.
**Action:** Always add `.help("Action Name")` and `.accessibilityLabel("Action Name Item Type")` to icon-only buttons, especially those located at the trailing edge of list rows.
