# Beddy Butler perfection plan

## Goal

Make Beddy Butler feel immediately understandable, charming, calm, and dependable. A new user should be able to launch it, understand where it lives, configure tonight in under a minute, hear the chosen personality, and trust that the next nudge will happen at the stated time.

## Definition of done

The revision is ready for release preparation when all of these are true:

1. **Discoverable:** a fresh install opens a concise welcome state and explains the menu bar home.
2. **Fast to configure:** bedtime start, bedtime, frequency, voice, volume, progressive behavior, and startup are available in one resizable window without an explicit Save step.
3. **Calm and legible:** the next scheduled action is above the fold, the interface uses a restrained visual hierarchy, and explanatory copy is brief.
4. **Delightful:** original character art is prominent, personality previews are immediate, copy retains the app's dry butler voice, and progressive behavior is understandable before enabling it.
5. **Forgiving:** users can snooze briefly, pause for the night, resume, preview safely, and recover from audio or login-item errors.
6. **Accessible:** controls have meaningful labels and hints, state is not conveyed by color alone, keyboard access works through native controls and menu shortcuts, and content remains usable at the minimum window size.
7. **Reliable:** wall-clock schedules survive midnight, travel, daylight saving changes, sleep, and wake; settings migrate from old releases; all audio resources are verified.
8. **Proven:** formatting, plist validation, the full test suite, static analysis, Release build, source asset validation, runtime launch, and inspected screenshots pass.

## Current experience audit

Evidence captured on 21 July 2026 at `/tmp/beddybutler-design-audit-2026-07-21/01-current-preferences.png`.

### Strengths

* Native SwiftUI controls already provide a strong macOS baseline.
* Schedule, personality, progressive behavior, startup, time zone, and live status are grouped coherently.
* The time-zone explanation and overnight handling create useful trust.
* The original three personalities and voice preview preserve the app's identity.
* The layout is resizable and scrollable.

### Structural risks

1. A first-time user receives no explanation that Beddy Butler lives in the menu bar.
2. The most important answer, “what happens next?”, appears below the fold.
3. Pause is available only from the menu and its duration is not visible in the main window.
4. The app can pause for a whole night, but it cannot provide a short, low-consequence snooze.
5. Voice loudness cannot be adjusted independently of the Mac's output volume.
6. Fresh installation, upgrade migration, and completed onboarding are not distinguished.

### Polish risks

1. Dense helper paragraphs make a small utility feel longer than it is.
2. The original character artwork is visually subordinate even though personality is the memorable product feature.
3. “Preview Butler” and “Not Now, Old Chap” are charming but insufficiently explicit as standalone menu commands.
4. The live schedule status needs stronger hierarchy and an immediate action.
5. The menu bar tooltip does not communicate the next nudge.

### Accessibility verification limits

The screenshot confirms visible labels, contrast, and reflow only. VoiceOver reading order, keyboard traversal, spoken state changes, and focus restoration require runtime accessibility testing before distribution.

## Intended user journey

```text
First launch
  -> Welcome: what it does and where it lives
  -> Choose tonight's window
  -> Choose and preview a personality
  -> Choose progressive behavior and volume
  -> Start Beddy Butler
  -> See “Next nudge” confirmation

Everyday use
  -> Click menu bar icon
  -> See exact next nudge and current personality
  -> Hear a sample, snooze 30 minutes, pause tonight, or open settings
  -> Scheduler recalculates after travel, clock changes, sleep, and wake
```

## Action plan

### Phase 1: Product clarity and onboarding

* Detect a genuine fresh install without treating an existing 2016 preference domain as new.
* Open Preferences automatically for a fresh install.
* Show a concise welcome card explaining menu bar residence, automatic saving, and tonight's setup.
* Provide a single “Start Beddy Butler” action that marks onboarding complete and confirms the next nudge.
* Keep every preference editable during onboarding so the experience is setup rather than a slideshow.

**Working if:** a clean preference suite opens the window, shows welcome guidance, and becomes an ordinary preferences window after one explicit completion action; migrated settings skip onboarding.

### Phase 2: Information hierarchy and visual character

* Move live schedule status directly below the header.
* Present the next nudge prominently with exact time, personality, and paused state.
* Increase the selected butler artwork and keep it aspect-correct.
* Use one restrained indigo accent, native materials, standard typography, and full-width cards.
* Shorten technical helper text and progressively disclose secondary explanation.
* Preserve scrolling and a practical minimum window size.

**Working if:** the first viewport answers what the app will do, when it will do it, and which voice it will use.

### Phase 3: Control and forgiveness

* Add a voice volume control with a sensible default and legacy-safe persistence.
* Add “Snooze 30 Minutes” alongside “Pause Tonight” and “Resume Nudges”.
* Make a snoozed nudge fire at the stated resume time when that time is inside the bedtime window.
* Clarify menu labels while retaining the app's voice in supporting copy.
* Update the menu bar tooltip with the next scheduled nudge.
* Keep login-at-startup opt-in and expose macOS approval state clearly.

**Working if:** a user can recover from an inconvenient moment without disabling the whole app or editing the bedtime window.

### Phase 4: Accessibility and state communication

* Add explicit labels, values, hints, and help text to custom groupings and action buttons.
* Ensure pause, snooze, login approval, onboarding, and playback errors use text and symbols rather than color alone.
* Add keyboard equivalents to the most useful menu commands.
* Keep focusable native controls and avoid decorative motion.
* Verify the preferences window at its default and minimum sizes.

**Working if:** every actionable control has a meaningful accessible name and the full setup remains operable through standard macOS keyboard navigation.

### Phase 5: Functional resilience

* Test fresh-install and upgrade onboarding migration.
* Test volume clamping and persistence.
* Test short snooze inside a window, snooze beyond bedtime, pause tonight, and resume.
* Preserve existing time-zone, daylight saving, overnight, progressive, audio-catalog, and login-item coverage.
* Keep timer ownership and audio playback on the main actor.

**Working if:** deterministic tests cover every new state transition and the complete suite passes without shared user state.

### Phase 6: Release evidence

* Capture fresh screenshots of the completed default and welcome states.
* Inspect visual hierarchy, clipping, spacing, and minimum-size reflow.
* Run `swift-format`, `git diff --check`, plist and scheme validation, the full XCTest suite, static analysis, and a Release build.
* Decode every MP3 and confirm the Release bundle contains all resources.
* Launch the real Release app, confirm its menu bar process and onscreen preferences window, and inspect runtime logs.
* Run the required design lint and classify its applicability to native SwiftUI.

**Working if:** every claimed outcome has direct build, test, runtime, or screenshot evidence from the finished source.

## Publication gates

These are person or distribution decisions rather than implementation defects:

1. Final bundle identifier and Apple Developer team.
2. Signing, notarization, and release channel.
3. Confirmed rights and credits for the voice, character, logo, and brand assets.
4. Whether to add an updater or a privacy-preserving feedback route.
5. Whether the historical repositories and website should be archived or redirected.

## Recommended release sequence

Complete the in-app perfection work first. Then run a small signed beta with fresh-install, upgrade, VoiceOver, multiple-display, sleep and wake, and travel or time-zone scenarios. Use that evidence to choose the public 2.0 release channel.

## Completion record, 22 July 2026

This completion record belongs to the July 2026 candidate described below. Later source, asset, copy, metadata, or signing changes require fresh evidence and acceptance.

The locally executable product and release-preparation phases are complete:

* The 46-test deterministic suite passes, including active nights, named second schedules, selected-weekday and rotating-cycle patterns, one-night adjustments, legacy Friday and Saturday migration, nonrepeating audio selection, sound, persistent counted visual and combined delivery, all 103 release clips, and the 10-second Zombie ceiling.
* Static analysis, the unsigned Release build, plist validation, Swift formatting, and design lint pass.
* A universal Developer ID archive succeeds with hardened runtime and App Sandbox. The app, ZIP, disk image, mounted disk-image app, designated requirement, and SHA-256 checksums verify.
* The signed application passes real-window runtime smoke and an 11-control accessibility smoke covering preferences and the compact Tonight panel. The menu-bar icon, preferences window, and glass popover were inspected onscreen.
* All 91 original MP3s match the pre-revival Git blobs, while the release assets are reproducibly normalized and spliced.
* CI, privacy disclosure, GitHub issue intake, update and feedback links, and a Keychain-backed notarization script are prepared.

The signed local beta is available under `build/BeddyButler-2.0-1-local`. Notarization remains credential-blocked because the `beddy-butler-notary` Keychain profile does not exist. Public distribution also retains the rights, destination, VoiceOver, multiple-display, and real-world transition gates in `RELEASE_CHECKLIST.md`.
