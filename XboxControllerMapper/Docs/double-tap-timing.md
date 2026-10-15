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
selects the window action without waiting for its release. Chord resolution still
precedes execution. Other profile settings stay unchanged.

## Chord-buffer follow-up

Engine arrival time alone still loses part of the interval to chord detection.
A regression with a 250 ms interval, 150 ms chord window, and a second physical
press 180 ms after the first release reproduced two single actions.

ControllerService now carries physical timestamps as internal callback metadata.
Its existing event callback continues to receive only resolved events. An early
press observation reserves an eligible pending double without executing it;
normal chord resolution still decides whether to dispatch the double or a chord.
The first single's deadline uses the physical release time. Fast flushes and
backlogged queues retain both in-time doubles and genuinely separate singles.

Profile, pause and lock boundaries cancel reserved physical presses so a delayed callback
cannot reinterpret an old press under a new mapping. No saved schema, mappings,
or configured intervals change. This applies only to ordinary single/double
bindings; hold, repeat, smooth-scroll and long-hold precedence keep their paths.
Near-boundary presses may now count as doubles where buffering previously caused
a single. Single actions can dispatch sooner because chord delay is no longer
added on top of the configured interval.

BufferedDoubleTapTimingTests covers both directions, Shift, chord priority in
standard/realtime mode, delayed queues, late taps, pause/lock cleanup and profile
changes. The full suite also exercises existing gesture and callback behavior.
