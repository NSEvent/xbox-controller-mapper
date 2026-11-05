# Wii Sensor Bar

For an original Nintendo Wii Remote and a powered infrared sensor bar. Import
`Wii Sensor Bar.json` into a build with Wii Remote support.

1. Power the sensor bar and place it centered above or below the display.
2. Open **Hardware → Wii Remote → Pair Wii Remote**. Tap the red SYNC button
   under the battery cover every few seconds while scanning. Use fresh AAs.
3. Select **Wii Sensor Bar**. In Hardware → Wii Remote, enable **IR aiming**
   and disable **Tilt steering** for sensor-bar-only movement.
4. Point toward the bar and press **B** once to start pointing. Press B again
   to stop. Pointing begins off and resets off on profile change, disconnect,
   controller lock, or disabling mapping.

| Button | Action |
| --- | --- |
| B | Toggle pointing |
| A | Left click; hold to drag |
| 1 | Right click |
| 2 | Escape |
| + / − | Scroll up / down |
| D-pad | Arrow keys |
| Home | Lock / unlock controller input |

Movement is relative to your hand movement, not calibrated absolute screen
position. Toggle pointing off to reposition your hand, then on again. If the
remote loses sight of the bar, the pointer stops with tilt disabled; reacquiring
the bar reanchors without a large cursor jump. Adjust IR speed and smoothing in
Hardware → Wii Remote.

The bar supplies infrared light; it does not pair with the Mac. The remote pairs
over Bluetooth using the in-app pairing flow. If waking a paired remote does not
reconnect, run Pair Wii Remote again. The original RVL-CNT-01 was used in earlier
hardware development; Remote Plus detection is included but remains unverified.

Protocol reference: [WiiBrew Wii Remote documentation](https://wiibrew.org/wiki/Wiimote).
