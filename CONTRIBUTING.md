# Contributing to Beddy Butler

Thank you for improving Beddy Butler. This project is a small, privacy preserving macOS utility, so contributions should keep the app calm, understandable, accessible, and dependable.

## Local setup

1. Use macOS with Xcode 26 or a compatible Swift 6 toolchain.
2. Install ffmpeg for audio verification: `brew install ffmpeg`.
3. Open `Beddy Butler.xcodeproj`, or use the command line checks below.

## Required checks

Before proposing changes, run:

```sh
python3 Tools/validate_website.py
python3 Tools/validate_app_store_metadata.py
python3 Tools/prepare_audio.py --check
python3 Tools/check_large_files.py
xcodebuild test \
  -project "Beddy Butler.xcodeproj" \
  -scheme "Beddy Butler" \
  -configuration Debug \
  -derivedDataPath /tmp/BeddyButlerDerivedData \
  CODE_SIGNING_ALLOWED=NO
```

For release candidates, use:

```sh
zsh Tools/validate_release_source.sh
```

External actions are separate from source validation. Notarization, App Store upload, and GitHub Pages deployment require Nell's approval bound to the exact clean commit. Do not weaken or bypass `Tools/require_publication_approval.py` or the manual Pages dispatch controls.

After producing a Release application bundle, validate its identity, resources, privacy manifest, and architectures:

```sh
python3 Tools/validate_app_bundle.py \
  "/path/to/Beddy Butler.app" \
  --version 2.0.2 \
  --build 612 \
  --require-universal
```

## Product principles

1. The first viewport should answer what Beddy Butler will do tonight and when.
2. The app should remain a menu bar companion, not a sleep tracking platform.
3. Privacy preserving local behavior is a product feature. Do not add accounts, analytics, or network dependencies casually.
4. Accessibility is part of the core experience. State must not depend on color or sound alone.
5. Scheduling must be calendar safe around midnight, daylight saving, sleep, wake, and travel.
6. Voice, character, icon, and brand assets require rights aware handling. Follow `ASSET_STEWARDSHIP.md` and do not replace or redistribute assets without explicit approval.

## Scope guidance

Small fixes are preferred. Larger work should first update `IMPROVEMENT_PROGRAMME.md` or add a focused design note explaining the user outcome, risks, and verification plan.

## Pull request checklist

1. Describe the user visible change.
2. Include the exact checks run and their results.
3. Note any skipped human gates, such as VoiceOver or multi display testing.
4. Confirm no file above 50 MB is added.
5. Confirm no credentials or private data are included.
