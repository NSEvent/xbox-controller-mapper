# Intent Mappings

Map buttons to intentions ("Save", "Undo") instead of key codes (Cmd+S, Cmd+Z). The app resolves the intent dynamically by walking the frontmost app's menu bar via the Accessibility API.

**Why this is different:** Every controller mapper is a key-code translator. This would be the first semantic input layer — configure once, works everywhere, even in apps with non-standard shortcuts.

## Research: Universal macOS Menu Actions

Tested by enumerating full menu hierarchies of 10 apps (Finder, Safari, Terminal, TextEdit, Notes, Preview, Xcode, Music, Chrome, GitHub Desktop) via `System Events` AX API.

### Tier 1: Virtually Every App (9-10/10)

~33 actions provided automatically by AppKit with consistent naming.

**Edit Menu:**
- Undo, Redo, Cut, Copy, Paste, Select All
- Emoji & Symbols, Start Dictation, AutoFill

**App Menu** (title = app name, items are consistent):
- About, Settings/Preferences, Hide App, Hide Others, Show All, Quit, Quit and Keep Windows, Services

**Window Menu:**
- Minimize, Minimize All, Zoom, Zoom All, Fill, Center
- Move & Resize, Full Screen Tile, Remove Window from Set
- Bring All to Front, Arrange in Front

**View Menu:**
- Enter Full Screen

**Writing Tools** (macOS 15+, system-injected):
- Show Writing Tools, Proofread, Rewrite, Make Friendly, Make Professional, Make Concise, Summarize, Create Key Points, Make List, Make Table, Compose

### Tier 2: Most Apps (6-8/10)

~28 additional actions, mainly in document/text apps.

**Edit > Find submenu:**
- Find..., Find Next, Find Previous, Use Selection for Find, Jump to Selection

**Edit (continued):**
- Delete, Paste and Match Style, Spelling and Grammar, Substitutions, Transformations, Speech

**File Menu:**
- Close / Close Window, Close All, New (varies: Window/Tab/Document)
- Print, Open, Save, Save As, Share, Export as PDF

**Window Menu:**
- Show Previous Tab, Show Next Tab, Move Tab to New Window, Merge All Windows

**View Menu:**
- Show Tab Bar, Show All Tabs, Zoom In, Zoom Out, Actual Size, Customize Toolbar

### Tier 3: Many Apps (3-5/10)

~30+ actions, app-category-specific.

**File:** Open Recent, Duplicate, Rename, Move To, Revert To, Page Setup
**View:** Show/Hide Sidebar, Show/Hide Toolbar, Show/Hide Status Bar, Sort By
**Navigation:** Back, Forward, Home, History, Bookmarks, Reload, Stop (browsers/Finder)

## Viability Assessment

**Strong viability.** Key findings:

1. **Naming is highly consistent** — AppKit enforces conventions. "Undo" is always "Undo", "Copy" is always "Copy". Fuzzy matching barely needs to be fuzzy.

2. **~20-25 high-confidence intents** resolve reliably in any app. Another ~15-20 work in most contexts.

3. **`AXEnabled` check** — can query whether a menu item is enabled before invoking, enabling graceful fallback to key codes.

4. **No extra permissions** — already requires Accessibility.

5. **Minor naming variations to handle:**
   - "Close" vs "Close Window"
   - "Settings..." vs "Preferences..." (macOS version dependent)
   - "New Tab" vs "New Window" vs "New Document" (need a generic "New" intent)

## Implementation Sketch

1. Get frontmost app's `AXUIElement` via `NSWorkspace.shared.frontmostApplication`
2. Get `kAXMenuBarAttribute` → walk `kAXChildrenAttribute` to find menu bar items by title
3. Walk submenu children to find target menu item by title
4. Check `kAXEnabledAttribute` — if disabled, fall back to key code mapping
5. Invoke via `AXUIElementPerformAction(element, kAXPressAction)`

**Fuzzy matching strategy:** Normalize strings (lowercase, strip "...", strip leading/trailing whitespace), then exact match first, substring match second.

## Recommended v1 Intent Vocabulary

The strongest candidates — high universality, high value, minimal naming ambiguity:

| Intent | Menu Path | Why |
|--------|-----------|-----|
| Undo | Edit > Undo | Universal |
| Redo | Edit > Redo | Universal |
| Cut | Edit > Cut | Universal |
| Copy | Edit > Copy | Universal |
| Paste | Edit > Paste | Universal |
| Select All | Edit > Select All | Universal |
| Find | Edit > Find > Find... | Near-universal |
| Find Next | Edit > Find > Find Next | Near-universal |
| Find Previous | Edit > Find > Find Previous | Near-universal |
| Save | File > Save | Most document apps |
| Close Window | File > Close / Close Window | Near-universal |
| New | File > New* (fuzzy) | Near-universal |
| Print | File > Print... | Most apps |
| Minimize | Window > Minimize | Universal |
| Full Screen | View > Enter Full Screen | Universal |
| Zoom In | View > Zoom In | Most apps |
| Zoom Out | View > Zoom Out | Most apps |
| Previous Tab | Window > Show Previous Tab | Most tabbed apps |
| Next Tab | Window > Show Next Tab | Most tabbed apps |
| Quit | App Menu > Quit | Universal |
| Hide App | App Menu > Hide | Universal |
| Settings | App Menu > Settings... | Universal |
