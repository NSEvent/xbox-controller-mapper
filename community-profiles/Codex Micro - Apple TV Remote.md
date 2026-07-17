# Codex Micro—Apple TV Remote

Turns a paired second-generation Apple TV Siri Remote into the Codex Micro control surface inside the ChatGPT macOS app.

ChatGPT does not listen for ordinary keyboard shortcuts from Codex Micro. It discovers a Work Louder HID device and consumes vendor RPC events. ControllerKeys supplies those events through an opt-in local shim based on [Marcel Pociot's Stream Deck emulator](https://github.com/mpociot/codex-micro-stream-deck-emulator).

## Remote layout

| Remote input | Codex Micro input |
| --- | --- |
| Clickpad edge rotation | Dial rotation |
| Clickpad click | Dial click; hold 500 ms for Codex Micro settings |
| Clickpad directions | Analog stick |
| TV/Home | Fast |
| Volume Up | Approve |
| Volume Down | Decline |
| Back | Fork |
| Mute (hold / double-tap) | Push to talk / hands-free recording |
| Play/Pause | Submit |
| Hold Siri + Back | Agent 1 |
| Hold Siri + TV/Home | Agent 2 |
| Hold Siri + Play/Pause | Agent 3 |
| Hold Siri + Mute | Agent 4 |
| Hold Siri + Volume Up | Agent 5 |
| Hold Siri + Volume Down | Agent 6 |

While holding Siri, press an Agent button once to switch chats without foregrounding ChatGPT. Double-tap it within 350 ms—keeping Siri held through both taps—to switch and bring ChatGPT forward. Power is intentionally unmapped to avoid TV power side effects.

## One-time setup

1. Pair the Siri Remote in macOS Bluetooth settings and import this profile.
2. Keep ControllerKeys running.
3. Quit ChatGPT normally.
4. Launch ChatGPT through the ControllerKeys shim:

   ```bash
   /bin/bash "/Applications/ControllerKeys.app/Contents/Resources/launch-chatgpt-with-codex-micro.sh"
   ```

5. If macOS asks, grant ChatGPT **Input Monitoring**. ChatGPT's Codex Micro integration requires it even though ControllerKeys owns the physical remote.

Use this launcher after each full ChatGPT quit or update. It does not modify or re-sign ChatGPT; it only injects the fake HID adapter into that launch and communicates with ControllerKeys over a user-only Unix socket.
