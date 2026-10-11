# Share your controller setup

## Touchpad baseline

General app profiles use the same calibrated touchpad tuning as the built-in
Default profile. A single-finger tap or physical touchpad press sends a left click;
holding a press supports dragging. Right-hand touchpads use the same bindings.
AnKing's quadrant controls and the Codex Micro Apple TV remote keep their specialized
behavior. Import an updated copy from the library to get these changes; existing
local profiles are not automatically overwritten.

## Contribute a profile

You can contribute a profile without learning Git or creating a pull request.

1. In ControllerKeys, right-click your profile and choose **Share to Community…**.
   You can also use **Share Your Profile…** in the community library.
2. Give the setup a public name, describe what it does, and name the controller you
   tested. Include the target app, any dependencies and a first action to try.
3. Review the shared copy. Controller identities and default status are removed.
   Custom automations/text are omitted unless you explicitly include them. Your
   working profile stays unchanged.
4. Choose **Save & Open GitHub Draft**. Sign in to GitHub, drag the prepared JSON
   file from Finder into the draft description, and submit the issue.

The JSON and setup guide are saved in **Downloads → ControllerKeys Community**.
Attachments become public as soon as you upload them to GitHub. Review labels,
text, scripts, links, credentials and local paths before attaching anything.
The reminder scan cannot guarantee that a profile is free of private data.

A maintainer reviews the submission before adding it to this library. Submitting
an issue does not immediately make the profile available in the app.

If your app version does not have sharing yet, [open a profile submission](https://github.com/NSEvent/xbox-controller-mapper/issues/new)
and attach a carefully reviewed exported JSON file. Please include the same setup
details and explicitly agree to contribute under this repository's
**PolyForm Noncommercial 1.0.0** license. A matching Markdown setup guide is welcome.

Contributors comfortable with Git may submit a pull request instead. Give the
reviewed JSON and optional Markdown guide the same basename. Keep profiles
self-contained, document required apps/hardware, and never include credentials or
personal controller identities. Existing import safety review still applies.
