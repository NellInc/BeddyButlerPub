# Beddy Butler revival notes

## Revival working line at the time of the rebuild

- Folder: `Beddy Butler Revision`
- Branch used for the rebuild: `revival/swift6-modernization`
- Base: `NellInc/beddybutlerpub`
- Behavioral donor: `NellInc/beddybutler`

The active local checkout is now `master` at the time of this improvement programme. The historical repositories remain separate so their source and commit histories are still available for comparison.

## What was folded into the Swift 6 revision

The donor repository's useful default-branch behavior is represented here:

1. Shy, Insistent, and Zombie personalities.
2. Previewable voice sets, with all 91 original MP3 files preserved.
3. Progressive escalation after a randomized two or three nudges.
4. A new reset at the start of each bedtime window.
5. Time-zone-aware scheduling without manual GMT offset arithmetic.
6. Recalculation after time-zone changes, system clock changes, system sleep, and wake.
7. Pause for the current or upcoming bedtime window.
8. Launch at login.

## Confirmed historical defects repaired

| Historical defect | Revision behavior |
| --- | --- |
| GMT offsets were manually added to absolute dates | Local wall-clock components are resolved through `Calendar` |
| Same-day arithmetic broke overnight windows | Begin times later than bedtime explicitly create a cross-midnight window |
| Random interval math did not match the described range | A base frequency now produces a tested range from 1.0 to 1.7 times the base |
| Timer state became stale after sleep, travel, or a manual clock correction | The scheduler recalculates on wake, time-zone, and system-clock notifications |
| A fire-and-forget audio player could be released early | `AudioPlayer` retains the active `AVAudioPlayer` and reports playback failure |
| Login items used removed `LSSharedFileList` APIs | `SMAppService.mainApp` is the only login-item integration |
| Builds rewrote the tracked Info.plist build number | Version and build values now use Xcode build settings |
| The storyboard and custom double slider produced layout warnings | Preferences use resizable SwiftUI controls with native time pickers |
| Removing the storyboard also removed its hidden AppDelegate connection | A programmatic application bootstrap now owns and installs the delegate explicitly |
| Tests depended on app state, user Documents, and removed APIs | The suite is deterministic and uses isolated settings and pure calculators |
| Playback requested microphone access | The unnecessary audio-input entitlement was removed |

## Deliberately excluded experiment

The unmerged `feedback_feature` branch was not transplanted. It coupled a feedback window to local logging and email-era behavior, and it was never part of the product's default branch. A future feedback feature should be designed with an explicit destination, privacy statement, offline behavior, and accessibility requirements.

## Product-quality pass completed

This section records the July 2026 candidate. Its machine, signing, runtime, and human evidence does not transfer automatically to later source, asset, metadata, or signing changes.

The post-revival pass adds a fresh-install welcome state, legacy-aware onboarding migration, an above-the-fold Tonight dashboard, a compact menu-bar Tonight panel, a 30-minute snooze with exact resume, pause and resume controls, active nights, named primary and second schedules, selected-weekday or rotating-cycle assignment, and a one-night adjustment. It also adds adjustable voice volume, nonrepeating shuffled clips, larger original character artwork, clearer menu commands, a dynamic menu-bar tooltip, an adaptive SF Symbol menu-bar icon, persistent counted visual nudges for deaf and situational accessibility, optional silent local notifications with actions, a modern full application icon, spoken accessibility announcements, locale-tested schedule times, and explicit accessibility metadata. The neutral second-schedule model supports religious observance, shift work, weekends, and other recurring routines, while existing Friday and Saturday settings migrate automatically. Users can choose sound, visual, or combined delivery. The complete rationale, user journey, measurable acceptance criteria, and release evidence plan live in `PERFECTION_PLAN.md`.

The final four-state visual audit is preserved as an editable [Figma design file](https://www.figma.com/design/nRJGkl878UwqqJZ5zbC4mb), covering Sound, Visual, Both, and the detailed scheduling and accessibility state.

The native-material pass gives the preferences window an edge-to-edge translucent backdrop, restrained color-responsive depth, inset standard-material content cards, the real application icon, explicit selection marks, and system Liquid Glass for the few top-level controls that merit it. The design follows macOS light and dark appearances and responds to Reduced Transparency and Reduced Motion without changing the underlying information hierarchy.

## Audio restoration

All 91 source MP3s are preserved byte-for-byte under `Audio Sources/Originals`. The release catalogue contains 103 peak-safe, loudness-balanced clips. Zombie recordings 09, 17, 18, 19, and 20 contained multiple performances; they are split at measured natural silences into 17 clips between 0.82 and 5.91 seconds. No playable Zombie clip exceeds 10 seconds. `Tools/prepare_audio.py` makes the transformation reproducible, its `--check` mode performs a nonmutating hash and decode audit, and `Audio Sources/PROCESSING_REPORT.json` records the evidence.

## Publication decisions still requiring Nell

1. Choose the final bundle identifier, signing team, and release channel.
2. Confirm rights and credits for the voice recordings, character, icon, and brand assets.
3. Decide whether launch at login should remain opt-in. This revision defaults it to off and reports macOS approval state.
4. Decide whether the legacy GitHub repositories and project website should be archived, redirected, or retained.
5. Confirm that GitHub Releases and GitHub Issues are the intended public update and feedback destinations.

## Recommended next product improvements

1. Complete the person-led VoiceOver, Full Keyboard Access, notification-action, multiple-display, and real sleep/wake beta checklist.
2. Localize user-visible strings beyond English.
3. Store the `beddy-butler-notary` Keychain profile and run the prepared signed release script.
4. Confirm distribution rights and the public GitHub destinations before publishing.
