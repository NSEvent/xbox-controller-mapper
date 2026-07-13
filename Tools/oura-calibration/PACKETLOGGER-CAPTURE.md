# Sniffing the official Oura app's tap-to-tag enable sequence

The in-app probe (rounds 1-3) found feature 0x07 answers reads and has an
"armed" state (bitmask bits 0x01/0x02) but never pushed tap events. The only
way to learn the *real* enable command is to capture the official Oura app
talking to the ring. That traffic is between the **iPhone and the ring**, so
the capture must happen on the phone, not the Mac.

## Step 0 — go/no-go (30 seconds, do this first)

ControllerKeys adopted the ring with its own auth key. The official app and
ControllerKeys can't both hold the ring at once, and if adoption replaced the
official key, the official app may be locked out entirely.

1. Quit ControllerKeys (or toggle Oura off in its settings) so the ring is free.
2. Open the official Oura app on the phone and confirm the ring **connects and
   syncs**.
   - Connects → proceed.
   - Won't connect → the ring is adopted away; this experiment is impossible
     without re-pairing to the official app first. Stop here.

## Step 1 — arm iOS Bluetooth logging

1. On the phone, install Apple's **Bluetooth** logging profile:
   developer.apple.com/bug-reporting/profiles-and-logs/ → Bluetooth → install,
   then Settings → General → VPN & Device Management → approve → reboot.
   (The profile makes iOS write a PacketLogger `.pklg` into every sysdiagnose.)

## Step 2 — reproduce + capture

1. In the official Oura app, perform the tap-to-tag / tag action (the feature
   where you tap the ring to mark a moment — often inside a workout/session).
   Do it a few times so the enable sequence + any tap frames are on the wire.
2. Immediately trigger a sysdiagnose: press **Volume-Up + Volume-Down + Side**
   for ~1s (a short buzz confirms). It bakes for ~10 min.
3. Retrieve it: Settings → Privacy & Security → Analytics & Improvements →
   Analytics Data → `sysdiagnose_…tar.gz` → share → AirDrop to the Mac.

## Step 3 — decode (hand it to me)

Drop the sysdiagnose (or just the `.pklg` from inside it) somewhere on the Mac.
The `.pklg` lives at `sysdiagnose_*/bluetooth/*.pklg` inside the tarball.

```
python3 decode_pklg.py <capture>.pklg
```

Look for the write right before tap frames start: a `2F .. 28 07` PUSH from the
ring, or a realtime `06 07 <bitmask>` with a bit the probe didn't try. That
byte sequence is the answer — it becomes the ring's start command and
hardware-rate tap detection ships.

## Honest caveat

Tap-to-tag may be a **stored marker** — the ring records a tagged timestamp in
memory for later cloud sync, with no live BLE push at all. Round 3 (armed
state, zero pushes on knock) is consistent with that. If the capture shows the
enable command but no per-tap frames, that confirms tap-to-tag isn't usable for
realtime input, and the ML pipeline stays the best available path.
