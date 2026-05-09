# Anki - AnKing (USMLE) — Setup Guide

A controller profile built for med students reviewing AnKing Overhaul cards. Three layers cover everything you need without taking your hand off the controller:

- **Base layer** — review actions (Again / Hard / Good / Easy, edit, replay audio, undo)
- **Shift Layer 1** *(hold Right Trigger, lightbar red)* — productivity (copy/paste, page up/down, suspend/bury card)
- **Shift Layer 2** *(hold Right Bumper, lightbar green)* — jump straight to a resource section on the back of the card (First Aid, Sketchy, Pathoma, etc.)

> Layer 2 is the killer feature, and it requires a one-time setup inside Anki. **Without the steps below, the Layer 2 buttons will fire keystrokes that Anki doesn't understand and nothing will happen.** Layers 1 and the base layer work out of the box.

Profile contributed by **anonrandomdoc** in the ControllerKeys Discord.

---

## Prerequisites

1. **AnKing Overhaul note type** installed in Anki. If you're using the AnKing v12 deck this is already in place.
2. **The resource sections you want to scroll to are enabled to "auto show"** on each card. AnKing's template has a UI for toggling each section (First Aid, Sketchy, Pathoma, etc.) — turn on the ones you actually use. If a section isn't enabled the scroll-to shortcut for it will do nothing.

---

## Step 1 — Import the controller profile

1. Open **ControllerKeys → Profiles → Community Profiles**
2. Find **Anki - AnKing (USMLE)** and import it
3. Done — the base layer and Layer 1 will work immediately

To test, open Anki, plug in your controller, and try:

- **A** → show answer / Good
- **X / B / Y** → Again / Hard / Easy
- **Hold Right Trigger** → lightbar turns red — press L Bumper / R Bumper to scroll the card up/down

---

## Step 2 — Add the section-jump shortcuts to your AnKing template

Layer 2 fires `Opt+Shift+0` through `Opt+Shift+8` when you press different buttons while holding Right Bumper. To make Anki actually scroll to a section in response, paste a small JavaScript snippet into the **Back Template** of the AnKing Overhaul card.

1. In Anki: **Tools → Manage Note Types**
2. Select **AnKing Overhaul** → click **Cards**
3. In the editor, switch to the **Back Template** tab
4. Scroll to the bottom and paste the following block:

```html
<!-- ControllerKeys: jump to resource section shortcuts -->
<script>
(function() {
  function scrollToSection(id) {
    const el = document.getElementById(id);
    if (!el) return;
    el.scrollIntoView({ behavior: "smooth", block: "start" });
  }

  document.addEventListener("keydown", (evt) => {
    if (!(evt.altKey && evt.shiftKey)) return;

    switch (evt.code) {
      case "Digit0": evt.preventDefault(); scrollToSection("missed");     break; // Missed Questions
      case "Digit1": evt.preventDefault(); scrollToSection("firstaid");   break; // First Aid
      case "Digit2": evt.preventDefault(); scrollToSection("sketchy");    break; // Sketchy
      case "Digit3": evt.preventDefault(); scrollToSection("pixorize");   break; // Pixorize
      case "Digit4": evt.preventDefault(); scrollToSection("pathoma");    break; // Pathoma
      case "Digit5": evt.preventDefault(); scrollToSection("lecture");    break; // Lecture Notes
      case "Digit6": evt.preventDefault(); scrollToSection("bnb");        break; // Boards and Beyond
      case "Digit7": evt.preventDefault(); scrollToSection("additional"); break; // Additional Resources
      case "Digit8": evt.preventDefault(); scrollToSection("extra");      break; // Extra
    }
  });
})();
</script>
```

5. Click **Save** / close the note type editor.

> The same snippet also works for desktop Anki shortcut presses (Alt+Shift+1 etc. on the keyboard) — you don't need a controller to use it.

---

## Layer 2 reference — controller buttons → resource sections

While holding **Right Bumper** (lightbar turns green):

| Button | Section |
|---|---|
| Right thumbstick click | Top of card (Main Question / Cloze) |
| D-pad Up | Missed Questions |
| **X** | First Aid |
| **B** | Sketchy |
| **A** | Pixorize |
| **Y** | Pathoma |
| D-pad Left | Lecture Notes |
| D-pad Down | Boards and Beyond |
| D-pad Right | Additional Resources |
| Menu (Start) | Extra |

The face button cluster (X/B/A/Y) is mnemonic order for the four most-used resources: **First Aid → Sketchy → Pixorize → Pathoma**.

---

## Notes

- The profile assumes a DualSense (PS5) controller for the lightbar feedback. It works fine on Xbox controllers too — you just won't get the colored layer indicator.
- A few base-layer bindings (D-pad Up/Down/Left, L3/R3, top-left touchpad click) are tied to specific Anki addons that the original contributor uses. If a binding doesn't do anything for you, you're missing the corresponding addon — feel free to remap those buttons to whatever you prefer.
- If `Opt+Shift+1` (or any other section shortcut) does nothing after pasting the snippet, double-check that the section is enabled to auto-show in the AnKing template config — the script can only scroll to sections that are actually rendered on the page.
