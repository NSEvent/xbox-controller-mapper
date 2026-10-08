# Starting-purpose onboarding

The welcome screen asks **What would you like to do first?** with seven optional
choices: Anki/studying, photos/video, mouse/Mac control, games, music,
coding/automation, and exploring/other. Skip clears only this preference.

The preference is saved immediately in `onboardingStartingPurpose.v1`, so quitting
during permissions does not lose it. Fresh runs see Welcome even when permissions
are already granted. Explicit permission-repair/controller-intro entry points
retain their existing behavior. Advancing skips permissions already granted.

When the controller and Accessibility are ready, the final screen offers:

- Anki: existing Anki guided starter plus the community library.
- Photos/video: explicit Photo Mechanic or Final Cut starters plus the library.
- Mouse/Mac control: existing left/right one-handed starter plus the library.
- Games, music, coding and exploration: searchable community profiles.

Opening a starter reuses `GuidedPresetSheet`, including review, explicit profile
creation, app/default routing, and its optional real-action test. Choosing a purpose
does not create a profile, change default mappings, or promise game compatibility.
Canceling a starter returns to the onboarding summary. Permissions/controller
repair stays primary when setup is incomplete; users may still choose Set Up Later.

## Measurement

`onboarding_purpose_selected` records an allowlisted `use_case` at selection time;
`onboarding_purpose_skipped` records null. Milestones are acknowledged/deduplicated
once per choice, permitting a changed choice without duplicate retries. Completion
still records the final choice on `onboarding_completed`. Existing telemetry opt-out
applies. No typed text, app names or medical details are collected by this choice.

New values are `photo_video`, `mac_control`, `music`, and `coding`. Historical
`creative_tools`, `accessibility`, `couch_control`, `presentations`, `study`, `gaming`
and `other` remain accepted. Deploy the compatible analytics allowlist before an
app release; no database migration is necessary. Keep null/skipped distinct from
other/exploring. Multiple choice milestones are not multiple users: join by install
and order by event time, using the final completion choice when available.

## Next experiments, not implemented

1. Measure first useful actions and mature paid conversion by purpose. Checkout
   comments sample buyers; onboarding answers include only observed activity.
2. Have five unfamiliar users complete a first task without coaching. The existing
   action metric means dispatched output, not verified success in the target app.
3. Improve app-specific game setup/help if the large gaming answer group repeatedly
   struggles; do not infer low conversion from intent counts alone.
4. Surface saved/unfinished workflow setup after Set Up Later or cancellation.
5. Add controller-specific button labels, localized setup copy and compatibility
   guidance where the current flow still leaves users guessing.
