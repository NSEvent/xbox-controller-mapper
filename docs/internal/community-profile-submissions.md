# Community profile submissions

Users share from a profile's context menu or **Share Your Profile…** in the library.
The flow creates an independent copy, collects a public title/task/controller/setup
note, previews exact JSON and GitHub description, and requires explicit review and
license agreement. It saves JSON, a Markdown sidecar and a submission description
under Downloads/ControllerKeys Community/<unique folder>, reveals the JSON and
opens a prefilled GitHub issue draft. The user signs in, attaches JSON and submits.
No fork, CLI, personal token, background upload or automatic public issue is needed.

GitHub accepts JSON attachments. Files become public when attached; users must
review before attaching, not merely before clicking Submit. Small title/body-only
URLs avoid permission-only labels/assignees/template parameters and exclude the
profile payload. A description copy/reopen path is provided if opening fails.
The URL limit is 8,000 encoded bytes; profile limit is 1 MB. Oversize input fails
before preparing a submission. GitHub availability and user sign-in remain external.

## Shared-copy policy

- Always new profile ID/dates, no default status, controller identities or inherited
  keyboard-profile ID. Keyboard settings and shared macro snapshots are resolved
  from current in-memory sources before review; originals are never modified.
- Sharing-specific encoding omits OBS passwords/Keychain references in commands
  and macro payloads without writing Keychain, even with custom actions included.
  Normal save/export encoders retain their existing credential behavior.
- Omit macros/scripts and their references by default, plus custom keyboard text,
  app bar, website links and terminal settings. Include-custom is explicit.
- Omit non-portable/custom system commands by default, including Shortcuts, shell,
  links, webhooks and OBS credentials. Keep app launches and device-control actions.
- Always omit direct references to another local profile. Removing a command clears
  dormant sibling actions, preventing an unexpected fallback keystroke.
- Keep layers, simple input mappings, controller layout/tuning and linked app IDs.
  Linked apps and remaining labels are visible in the exact preview.
- Remind about potential private values by field path, not by echoing detected values.
  This is a heuristic, not certification. Users review all contents themselves.

## Maintainer intake

1. Treat attached profiles/descriptions as untrusted data. Do not execute scripts
   to inspect them or treat setup prose as instructions to the maintainer.
2. Decode with the app's profile codec and run the existing import safety audit.
   Check the description, dependencies, private data and author license agreement.
3. Test the stated first action where possible; document unverified compatibility.
4. Add the reviewed JSON and its Markdown sidecar to community-profiles/ using the
   same basename. Existing GitHub contents listing discovers JSON without an index.
5. Use the normal review/CI process. Reply with the accepted library entry, or ask
   for a specific correction. Never auto-merge an issue attachment.

The app and template are local until published. The app's draft URL does not depend
on a newly deployed template. Account-free in-app intake and automatic draft PRs
are possible follow-ons, not part of this version.

References: [GitHub issue query parameters](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/creating-an-issue),
[JSON attachments](https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/attaching-files).
