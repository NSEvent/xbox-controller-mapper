## 2024-06-25 - [Accessibility Context in Lists]
**Learning:** In repeated lists or loops, icon-only buttons with generic `.accessibilityLabel()` or `.help()` (like "Edit" or "Delete") lose context, confusing screen reader users.
**Action:** Always inject dynamic context from the current item (e.g., `item.displayName`) into the accessibility label and help modifiers to disambiguate the action (e.g., "Edit Home Button").
