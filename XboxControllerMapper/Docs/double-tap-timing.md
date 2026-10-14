# Remote double-tap timing

## Reproduction (2026-10-14)

The Apple TV Remote profile, shared with the Xiaomi Remote 2 Pro, maps single
Up/Down taps to app switching and double taps to next/previous window. A live
capture showed intended double taps sometimes emitting the single-tap Tab
shortcut instead of the double-tap backtick shortcut. The correct Shift flag
was present when Down was recognized as a double tap; CodexBar did not intercept
those modified backtick events.

The release-based path scheduled the single after the first release, then waited
until the second release to cancel it. A second press inside the interval could
still lose if held past the deadline: the first single fired while the second
press was held, and its release scheduled another single.

## Fix

For ordinary tap mappings, the second press claims a pending double immediately.
It cancels the single fallback and consumes its own release. Cancelled fallback
closures also check their original tap timestamp before touching state, so a
stale closure cannot clear a newer gesture. Held, repeated and long-hold mappings
retain their existing handling.

Regression coverage reproduces the held second press for both Up and Down,
checks the reverse-window Shift flag, and verifies isolated single taps and taps
outside the interval. Tests use a recording simulator on kmacstudio; no keyboard
events are injected by these cases.

Kevin's local Apple TV Remote profile uses a 0.6-second Up/Down double-tap
interval. A single app-switch tap waits that interval; an in-time second press
dispatches the window action immediately. Other profile settings stay unchanged.
