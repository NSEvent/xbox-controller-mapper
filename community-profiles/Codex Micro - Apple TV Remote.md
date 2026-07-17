# Codex Micro—Apple TV Remote

Turns a paired second-generation Apple TV Siri Remote into the Codex Micro control surface inside the ChatGPT macOS app.

ChatGPT does not listen for ordinary keyboard shortcuts from Codex Micro. It discovers a Work Louder HID device and consumes vendor RPC events. ControllerKeys supplies those events through an opt-in local shim based on [Marcel Pociot's Stream Deck emulator](https://github.com/mpociot/codex-micro-stream-deck-emulator).

## Remote layout

| Remote input | Codex Micro input |
| --- | --- |
| Clickpad edge rotation | Dial rotation |
| Clickpad click | Dial click |
| Clickpad directions | Analog stick |
| TV/Home | Fast |
| Volume Up | Approve |
| Volume Down | Decline |
| Back | Fork |
| Hold Siri | Push to talk |
| Play/Pause | Submit |
| Hold Power + the six side buttons above | Agent 1–6 |

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
