# Beddy Butler

Beddy Butler is a playful macOS menu bar companion that nudges you toward bed with increasingly persuasive voice reminders.

This revision revives the 2016 app as a native Swift 6 project. It preserves the original artwork and all 91 source recordings while replacing the obsolete storyboard, custom double slider, timer arithmetic, login item API, mutable build-number script, and fragile tests.

## Features

- A configurable bedtime window, including windows that cross midnight.
- A guided first launch that explains the menu bar home and lets users configure the real app in place.
- An above-the-fold Tonight card showing the next nudge, personality, pause state, and recent activity.
- Calendar-based scheduling in the Mac's current time zone.
- Named primary and secondary schedules, with either selected weekdays or a rotating cycle for observances, shift patterns, weekends, and other routines.
- A one-night adjustment that temporarily replaces the regular window, including on a normally inactive night.
- Automatic recalculation after time-zone changes, daylight-saving changes, system clock changes, sleep, and wake.
- Randomized reminder timing from the chosen base frequency up to 70 percent later.
- Shy, Insistent, and Zombie personalities with 103 peak-safe, loudness-balanced release clips derived from 91 preserved recordings.
- Five overlong Zombie recordings split at natural silences, keeping every playable Zombie nudge under 10 seconds.
- Progressive mode, which escalates after every two or three reminders and resets for each bedtime window.
- Sound, a persistent visual menu-bar badge, or both, so bedtime nudges do not depend on hearing.
- Optional silent local Notification Center alerts with Acknowledge, Snooze, and Pause actions.
- Persisted visual nudge counts that survive relaunch until acknowledged.
- One-click voice previews.
- Nonrepeating shuffled voice playback within each personality.
- Independent voice volume control.
- A 30-minute snooze that resumes at the promised time during the bedtime window.
- Pause for tonight and one-click resume.
- Modern launch-at-login support through `SMAppService`.
- A compact native Tonight panel on left click, a full command menu on right click, an adaptive system icon, and accessible SwiftUI preferences.
- A system-native, edge-to-edge preferences window with adaptive Liquid Glass accents on macOS 26 and standard-material fallbacks on earlier supported releases.
- Automatic light and dark appearance, Reduced Transparency, and Reduced Motion adaptation.
- A modern macOS application icon that retains the original sleepy butler character.
- Privacy-preserving website and feedback commands that open the relevant page in the default browser. Mac App Store builds use Apple's update mechanism.
- App Sandbox and hardened runtime configuration.

## Requirements

- macOS 13 Ventura or later.
- Xcode 26 or a compatible Xcode release with Swift 6 support.

## Build and test

Open `Beddy Butler.xcodeproj` in Xcode, or run:

```sh
xcodebuild test \
  -project "Beddy Butler.xcodeproj" \
  -scheme "Beddy Butler" \
  -configuration Debug \
  -derivedDataPath /tmp/BeddyButlerDerivedData \
  CODE_SIGNING_ALLOWED=NO
```

Verify the preserved recordings and every derived release clip without rewriting them:

```sh
python3 Tools/prepare_audio.py --check
```

Create a signed local beta with the installed Developer ID identity:

```sh
Tools/release.sh 2.0 1 --local
```

For a notarized release, first store a `beddy-butler-notary` notarytool Keychain profile, then omit `--local`. The release script notarizes and staples the app, builds and notarizes a drag-to-Applications disk image, creates a ZIP, and writes SHA-256 checksums. The rights holder has confirmed publication and asset rights.

Prepare a Mac App Store build:

```sh
Tools/app_store_release.sh --preflight 2.0 1
Tools/app_store_release.sh --upload 2.0 1
```

The upload command requires an App Store Connect app record, accepted agreements, and working Apple distribution signing. Product copy, review notes, privacy answers, and 2880 by 1800 screenshots live in `AppStore`.

## Website

The static, dependency-free website lives in `Website` and is deployed to GitHub Pages by `.github/workflows/pages.yml`. It includes the product page, support, privacy policy, social preview, sitemap, custom domain, Reduced Motion and Reduced Transparency support, and responsive layouts.

Validate it locally with:

```sh
python3 Tools/validate_website.py
```

## Architecture

| File | Responsibility |
| --- | --- |
| `AppDelegate.swift` | Menu bar lifecycle, adaptive and badged icons, menu commands, and clock-change handling |
| `PreferencesViewController.swift` | SwiftUI preferences hosted in AppKit |
| `ButlerTimer.swift` | Calendar-safe bedtime windows, scheduling, mute behavior, progressive state |
| `UserDefaultKeys.swift` | Typed settings, onboarding state, and migration from legacy preferences |
| `AudioPlayer.swift` | Voice catalog and retained audio playback |
| `LoginItems.swift` | Modern login item state and registration |
| `AboutViewController.swift` | About panel metadata |
| `Website` | BeddyButler.com product, support, and privacy pages |
| `AppStore` | Submission copy, review notes, privacy answers, and screenshots |

The test target covers scheduling before, during, and after a window; active-night and arbitrary alternate-night selection; rotating cycles in both directions around their anchor; one-night overrides; migration from the original Friday and Saturday option; cross-midnight behavior; multiple time zones; the spring daylight-saving gap; progressive escalation; sound, visual, and combined delivery; persistent visual counts; nonrepeating audio selection; exact snooze and bedtime boundaries; first-launch and upgrade migration; volume persistence; login items; and every bundled voice set.

Two local runtime probes supplement XCTest. `Tools/runtime_smoke_test.swift` confirms the real preferences window launches at a usable size. `Tools/accessibility_smoke_test.swift` verifies the window and critical controls appear in the macOS accessibility hierarchy. Both use isolated preferences suites and leave the user's Beddy Butler settings untouched.

The source recordings are stored unchanged in `Audio Sources/Originals`. `Tools/prepare_audio.py` reproducibly creates the release assets, while its `--check` mode verifies inventory, hashes, decoding, and clip duration without modifying files. `Audio Sources/PROCESSING_REPORT.json` records every source hash, splice, gain adjustment, output duration, and measured level.

## Lineage

The revival is based on `NellInc/beddybutlerpub`, with useful behavior selectively ported from `NellInc/beddybutler`. The repositories do not share Git ancestry, so a direct history merge would be unreliable. See `REVIVAL_NOTES.md`, `PERFECTION_PLAN.md`, and the workspace-level `REPOSITORY_MAP.md` for the full collation and product-quality plan.

## License

The source repository is available under the BSD license in `LICENSE`. The recorded voice and brand assets are published with the rights holder's authorization. See `PRIVACY.md` and `RELEASE_CHECKLIST.md` for the distribution contract.
