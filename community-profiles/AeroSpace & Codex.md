# AeroSpace & Codex

A three-layer workflow inspired by [Jon Winsley's “Unconventional Inputs”](https://www.jonwinsley.com/notes/unconventional-inputs), published July 21, 2026. Reconstructed from his public screenshots and descriptions, rather than an export of his configuration. Jon has not reviewed this preset.

The Luna controller in the article uses the standard Xbox button layout. Xbox, Luna and PlayStation controllers can use this preset; on PlayStation, A/B/X/Y correspond to Cross/Circle/Square/Triangle. Controller availability still depends on macOS and the connection method.

## Setup

1. Install and run [AeroSpace](https://github.com/nikitabobko/AeroSpace). Its CLI must be on PATH, `/opt/homebrew/bin` or `/usr/local/bin`.
2. Import this profile and select it manually. It deliberately has no app auto-switching rule: the AeroSpace layer should remain usable across apps.
3. For optional [Handy](https://github.com/cjpais/Handy) dictation, configure its push-to-talk shortcut to **Control-Shift-Space**. Hold LB to dictate. That shortcut is a preset choice, not a recovered setting from Jon's screenshot. If another app uses it, change both ends or remove LB.
4. Open Codex and check **Settings → Keyboard Shortcuts**. The mappings below use the defaults documented on October 5, 2026; customize them for an older standalone Codex build or changed personal shortcuts.
5. Select **AeroSpace** or **Codex** in ControllerKeys' layer tabs to inspect the colored overrides. Only controls explicitly overridden in that layer receive a border on the controller graphic; inherited controls remain unoutlined. Stick rings outline the wells. AeroSpace is purple; Codex is cyan. These colors also drive supported PlayStation lightbars.

Import warns about the visible AeroSpace shell commands. They control local windows/workspaces; this profile contains no credentials, webhooks, AppleScript or imported JavaScript. Neither importing nor opening the guide runs its commands.

## Base

| Input | Action |
| --- | --- |
| Left stick / right stick | Pointer / scroll |
| A | Hold left mouse button for click/drag |
| B | Backspace; long hold deletes to line start; double tap deletes a word |
| X | Return; long hold sends Command-Return |
| Y | Escape |
| LB | Hold Control-Shift-Space for configured Handy dictation |
| RB / View | Tab / Shift-Tab |
| D-pad | Arrow keys with repeat |
| Left / right stick click | Previous / next AeroSpace workspace |
| Menu | Toggle floating/tiling |
| Guide / Xbox / PS | Codex command menu (Command-K) |
| LT / RT | Hold AeroSpace / Codex layer |

## Hold LT: AeroSpace

| Input | CLI action | Reconstruction |
| --- | --- | --- |
| D-pad | `focus up/down/left/right` | Visible labels and article |
| X / Y | `workspace --wrap-around prev/next` | Visible labels and article |
| A / B | `move-node-to-workspace --wrap-around prev/next` | Purpose stated; direction assignment inferred |
| Left / right stick click | `layout tiles` / `layout accordion` | Article and visible labels |
| Menu | `balance-sizes` | Visible label |
| RB | `move-node-to-monitor --wrap-around next` | Inferred from clipped “Move…” label |
| View | `move-workspace-to-monitor --wrap-around next` | Inferred from clipped “Move…” label |
| Guide | `focus-back-and-forth` | Inferred from clipped “Previous…” label |

The inferred monitor/window actions are editable choices, not verified copies of Jon's commands. Workspace changes use AeroSpace's workspace ordering. Window-to-workspace actions leave focus behind; add `--focus-follows-window` if preferred. See [AeroSpace's command reference](https://nikitabobko.github.io/AeroSpace/commands.html).

## Hold RT: Codex

| Input | Action | Shortcut |
| --- | --- | --- |
| D-pad Up / Down | Previous / next chat | Control-Shift-Tab / Control-Tab |
| D-pad Left / Right | Back / forward through visited chats | Command-[ / Command-] |
| View | Toggle sidebar | Command-B |
| Menu | New task/chat | Command-N |
| RB | Command menu | Command-K |
| Left stick click | Open review | Control-Shift-G |
| Y | New standalone chat | Command-Option-O |
| B | Model/reasoning picker | Control-Shift-M |

The screenshot's **Quick Chat**, **Cycle Reasoning Effort**, **Toggle Review Panel** and recency commands do not expose their underlying shortcuts. This preset adapts those intentions to [current documented commands](https://learn.chatgpt.com/docs/reference/commands). B opens the model picker; it does not automatically cycle reasoning effort. Y opens a standalone Codex chat; the current docs reserve “Quick chat” for ChatGPT. Left/right use navigation history rather than claiming an exact recency sort. Neither action automatically sends a prompt.

A, X, LB, right-stick click and unmapped inputs fall through to the base layer. Keep Codex focused when using its layer; ordinary keyboard mappings act on the focused app.
