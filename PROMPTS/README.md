# Prompts

This directory contains the intent that tests cannot capture.

Tests encode **what** the program does: given this input, produce this output. But some constraints are architectural, behavioral, or framework-specific in ways that resist unit testing. A SwiftUI timing issue. A UX invariant about keyboard shortcuts. A schema evolution rule. These are things an AI needs to know to regenerate the codebase correctly, but that no test suite can practically verify.

Together, `PROMPTS/` and the test suite form the intent specification for this program. The tests verify behavior. The prompts guide generation. The code is the compiled output.

See ["Backwards Compatible for Life"](https://kevin.md/backwards-compatible-for-life.md) for the full thesis.

## Organization

Each file covers a domain. Rules are written as directives an AI can follow when generating or regenerating code.

| File | Domain |
|------|--------|
| [ui.md](ui.md) | SwiftUI views, dialogs, keyboard shortcuts, user interaction patterns |
| [data.md](data.md) | Configuration schema, Codable conventions, backwards compatibility |
| [architecture.md](architecture.md) | Service layer, threading, controller pipeline, state management |

## How to use this

When building new features or regenerating existing code, load the relevant prompt file(s) alongside the task. These are constraints and patterns that must hold across the codebase. Violations cause real bugs, even if no test catches them.

When you discover a new pattern or fix a bug that a test can't cover, add it here.
