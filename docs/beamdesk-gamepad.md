# Quest gamepads through Beamdesk

Choose **Settings → Controls → Controller → ControllerKeys** in Beamdesk on Quest.
Keep this updated ControllerKeys app running on the selected Mac. Its current profile and
layers apply to the remote gamepad through the normal button/stick pipeline. Beamdesk never
copies, selects, or rewrites profiles. Use hands for Beamdesk menus and to switch back to
Beamdesk's gaze navigation.

Supported: face buttons, bumpers, analog triggers, D-pad, stick clicks, both analog sticks,
Menu/View/Guide when Horizon OS delivers them. The Quest's PlayStation Share button maps to
ControllerKeys View, matching GameController's Options binding. Touchpad gestures, motion
sensors and haptics are not forwarded yet.

The existing Beamdesk command notification carries `controllerkeys.gamepad.v1` with a JSON
snapshot in `argument`: version, UUID session, increasing sequence, active flag, held button
names and six axes (left X/Y, right X/Y, triggers; up positive). Analog snapshots are capped
at 30 Hz with a 500 ms heartbeat; button edges are preserved individually. A silent stream
expires after 1.5 seconds. Disconnect, mode/host changes and doff release held inputs; a new
or expired lease must return neutral before forwarding again. Invalid, reordered and retired
session packets are ignored. Protocol source: Beamdesk's `protocol/CONTROLLERKEYS.md`.

Regression tests use an in-memory input simulator and isolated profiles. Run tests on
kmacstudio; they exercise profile mapping and held-modifier cleanup without typing or moving
the real pointer. `BeamdeskGamepadInputTests`, `BeamdeskGamepadMappingTests`, existing
`BeamdeskInputServiceTests`, and `ControllerServiceCallbackProxyTests` cover the integration.
