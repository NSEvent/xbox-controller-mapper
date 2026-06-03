## 2024-05-24 - Accessibility standards for icon-only buttons
**Learning:** In SwiftUI macOS apps, icon-only buttons (like edit or trash icons in lists) require both `.help()` tooltips for sighted mouse users and `.accessibilityLabel()` for screen reader users to be fully accessible and understandable.
**Action:** Add `.help("Label")` to all icon-only buttons that currently only have `.accessibilityLabel()`.
