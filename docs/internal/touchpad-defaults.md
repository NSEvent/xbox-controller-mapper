# Touchpad defaults

New settings, new profiles, first-run Default, and missing-field decoding share
`TouchpadDefaults` (calibrated from Kevin's Default profile on 2026-10-11).
Keep its full-precision values; rounded UI percentages are not the stored tuning.
First-run Default retains tap/press left click, including hold-to-drag.

Explicit saved/imported values remain authoritative. The historical legacy-preset
migration keeps its previous 0.005 deadzone target so changing the new-user baseline
does not silently retune existing profiles. Specialized presets can override tuning.

`TouchpadDefaultsTests` covers creation, first-run click bindings, decoding,
round trips, migration stability, and preservation of explicit custom settings.
