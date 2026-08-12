# Beddy Butler

Beddy Butler is an original macOS menu bar companion, first released in 2016 and now rebuilt in Swift 6. It nudges you toward bed with increasingly persuasive voice reminders, visual reminders, or both. It is completely free.

**Current source and App Review submission:** Beddy Butler 2.0.1 (build 612)

**Design and engineering by Nell Watson and David Garces.**

**QA by Filip Alimpić.**

The current edition preserves the original artwork and all 91 source recordings while replacing the obsolete storyboard, custom double slider, timer arithmetic, login item API, mutable build-number script, and fragile tests.

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
- A focused night appearance with Reduced Transparency and Reduced Motion adaptation.
- Personality-specific 2D skeletal animation with independently rigged head, torso, hands, and Zombie brain motion.
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

Run the complete source candidate gate:

```sh
zsh Tools/validate_release_source.sh
```

Create a candidate-bound evidence record after each source, asset, copy, or metadata change:

```sh
python3 Tools/create_release_evidence.py
```

Validate a finished application bundle before packaging or upload:

```sh
python3 Tools/validate_app_bundle.py \
  "/path/to/Beddy Butler.app" \
  --version 2.0.1 \
  --build 612 \
  --require-universal
```

For a signed archive, add `--require-signed-security`. This rejects ad-hoc or
unrecognized signatures, missing hardened runtime, a lost sandbox entitlement,
debug entitlement leakage, and unexpected signed entitlements. Add
`--require-distribution-authority` for a final Developer ID or locally exported
Apple distribution artifact. The App Store script validates the trusted signed
archive before Xcode applies managed distribution signing during export or upload.

Create a signed local beta with the installed Developer ID identity:

```sh
Tools/release.sh 2.0.1 612 --local
```

There is no default distribution mode. `--local` must be written explicitly. For a notarized release, first store a `beddy-butler-notary` notarytool Keychain profile, obtain Nell's approval for the exact clean commit, version, and build, set `BEDDY_NOTARIZATION_APPROVAL` to `NOTARIZE:<40-character-commit>:<version>:<build>`, then use `--notarized`. The release script validates the built bundle, notarizes and staples the app, builds and notarizes a drag-to-Applications disk image, creates a ZIP, and writes SHA-256 checksums. The existing rights record is retained in the release checklist; publication of each exact candidate still requires explicit approval.

Prepare a Mac App Store build:

```sh
Tools/app_store_release.sh --preflight 2.0.1 612
Tools/app_store_release.sh --upload 2.0.1 612
```

Release scripts require a clean Git working tree and rerun formatting, metadata,
website, audio, and XCTest validation before any archive is created. For a
deliberate local verification of uncommitted work, set
`BEDDY_ALLOW_DIRTY_RELEASE=1`; distribution builds should remain clean.

The upload command requires an App Store Connect app record, accepted agreements, working Apple distribution signing, and Nell's exact clean commit, version, and build approval in `BEDDY_APP_STORE_UPLOAD_APPROVAL`. Product copy, review notes, privacy answers, and 2880 by 1800 screenshots live in `AppStore`.

## Project guidance

The improvement programme and release controls are maintained in these local documents:

| Document | Purpose |
| --- | --- |
| `IMPROVEMENT_PROGRAMME.md` | Phased product, accessibility, reliability, governance, and release roadmap |
| `COMPLETION_AUDIT.md` | Requirement-by-requirement proof and remaining authority matrix |
| `RELEASE_EVIDENCE_TEMPLATE.md` | Exact-candidate machine, human, rights, and publication evidence |
| `RELEASE_CHECKLIST.md` | Distribution and person-led acceptance gates |
| `ARCHITECTURE.md` | Current boundaries and behavior-preserving refactor order |
| `CONTRIBUTING.md` | Local setup, checks, and contribution expectations |
| `SECURITY.md` | Security boundary, invariants, reportability, and private reporting guidance |
| `ASSET_STEWARDSHIP.md` | Source assets, derivatives, rights boundaries, bundle inventory, and transcript status |
| `FUTURE_ROADMAP.md` | Evidence-gated accessibility, localization, daily control, and automation priorities |

## Website

The static, dependency-free website lives in `Website`. `.github/workflows/pages.yml` validates website changes on pull requests and pushes, while deployment requires a separate manual dispatch containing Nell's approved exact commit SHA and matching approval phrase. It includes the product page, support, privacy policy, social preview, sitemap, custom domain, Reduced Motion and Reduced Transparency support, and responsive layouts.

Validate it locally with:

```sh
python3 Tools/validate_website.py
python3 Tools/test_live_destinations.py
python3 Tools/validate_live_destinations.py --mode current
```

The live destination validator is read only. Current mode proves the existing public baseline and requires candidate-only routes to remain unpublished. Publication mode is the post-deployment gate and requires every public candidate file to match the local candidate byte for byte. It also checks the canonical redirect, sitemap, robots file, security contact, App Store record, canonical GitHub repository, and a genuine HTTP 404.

## Architecture

| File | Responsibility |
| --- | --- |
| `AppDelegate.swift` | Menu bar lifecycle, adaptive and badged icons, menu commands, popover hosting, and clock-change handling |
| `LocalNotificationManager.swift` | Local notification authorization, delivery, categories, and actions |
| `TonightPopoverView.swift` | Compact status panel and immediate Tonight actions |
| `BeddyDesign.swift` | Shared palette, backdrop, card, capsule, and button primitives |
| `PreferencesViewController.swift` | SwiftUI preferences hosted in AppKit |
| `ButlerRigView.swift` | Native SpriteKit mesh rig, personality choreography, and Reduced Motion fallback |
| `ButlerTimer.swift` | Calendar-safe bedtime windows, scheduling, mute behavior, progressive state |
| `UserDefaultKeys.swift` | Typed settings, onboarding state, and migration from legacy preferences |
| `AudioPlayer.swift` | Voice catalog and retained audio playback |
| `LoginItems.swift` | Modern login item state and registration |
| `AboutViewController.swift` | About panel metadata |
| `Website` | BeddyButler.com product, support, and privacy pages |
| `AppStore` | Submission copy, review notes, privacy answers, and screenshots |
| `DESIGN_SYSTEM.md` | Figma source, shared visual tokens, 4K masters, and native capture workflow |

See `ARCHITECTURE.md` for dependency direction, responsibility boundaries, and the recommended extraction sequence.

The test target covers scheduling before, during, and after a window; active-night and arbitrary alternate-night selection; rotating cycles in both directions around their anchor; one-night overrides; migration from the original Friday and Saturday option; cross-midnight behavior; multiple time zones; the spring daylight-saving gap; progressive escalation; sound, visual, and combined delivery; persistent visual counts; nonrepeating audio selection; exact snooze and bedtime boundaries; first-launch and upgrade migration; volume persistence; login items; and every bundled voice set.

Two local runtime probes supplement XCTest. `Tools/runtime_smoke_test.swift` confirms the real preferences window launches at a usable size. `Tools/accessibility_smoke_test.swift` verifies the window and critical controls appear in the macOS accessibility hierarchy. Both use isolated preferences suites and leave the user's Beddy Butler settings untouched.

`Tools/capture_acceptance_states.swift` adds an exact-executable six-state image matrix with isolated defaults, SHA-256 manifest binding, empty-frame rejection, and state-diversity checks. Its Tonight renders are suitable for visual inspection. Its complete-form Preferences renders expose every production section, but AppKit-backed controls can show placeholders without a live window, so they supplement rather than replace exact-candidate native-window acceptance.

The source recordings are stored unchanged in `Audio Sources/Originals`. `Tools/prepare_audio.py` reproducibly creates the release assets, while its `--check` mode verifies inventory, hashes, decoding, and clip duration without modifying files. `Audio Sources/PROCESSING_REPORT.json` records every source hash, splice, gain adjustment, output duration, and measured level.

## Project history

Beddy Butler is an original work first created in 2016. The older Beddy Butler repositories preserve earlier iterations and experiments within the same project. See `REVIVAL_NOTES.md`, `PERFECTION_PLAN.md`, and the workspace-level `REPOSITORY_MAP.md` for the full collation and product-quality plan.

## License

The source repository is available under the BSD license in `LICENSE`. Recorded voice, character, icon, name, and brand assets have separate rights boundaries documented in `ASSET_STEWARDSHIP.md`. See `PRIVACY.md` and `RELEASE_CHECKLIST.md` for the candidate distribution contract.
