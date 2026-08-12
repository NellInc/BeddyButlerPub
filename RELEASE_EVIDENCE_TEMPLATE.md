# Beddy Butler release evidence template

Copy this file to `build/release-evidence/BeddyButler-<version>-<build>-<shortsha>.md` for each release candidate. Do not treat an older evidence file as valid after any source, asset, metadata, signing, or copy change.

## Candidate identity

| Field | Value |
| --- | --- |
| Version |  |
| Build |  |
| Git commit |  |
| Working tree digest |  |
| Branch |  |
| Date prepared |  |
| Prepared by |  |
| Release channel | Local beta, Developer ID, Mac App Store, or GitHub Pages |
| Push or deploy approved by Nell | No until explicitly changed |

## Machine evidence

| Gate | Command or source | Result | Artifact path |
| --- | --- | --- | --- |
| Working tree | `git status --short --branch` |  |  |
| Formatting | `xcrun swift-format lint --recursive "Beddy Butler" "Beddy ButlerTests" Tools` |  |  |
| Plists | `plutil -lint ...` |  |  |
| Website | `python3 Tools/validate_website.py` |  |  |
| Current public destinations | `python3 Tools/validate_live_destinations.py --mode current` |  |  |
| Published destinations | `python3 Tools/validate_live_destinations.py --mode publication` after an approved deployment |  |  |
| App Store metadata | `python3 Tools/validate_app_store_metadata.py` |  |  |
| Website design lint | `npx --yes impeccable detect Website` |  |  |
| Website browser smoke | Local home, accessibility, and press routes at desktop and narrow widths |  |  |
| Audio | `python3 Tools/prepare_audio.py --check` |  |  |
| Large files | `python3 Tools/check_large_files.py` |  |  |
| Publication controls | `python3 Tools/test_publication_approval.py` and `python3 Tools/validate_publication_controls.py` |  |  |
| Security posture | `python3 Tools/test_security_posture.py` and `python3 Tools/test_app_bundle_validation.py` |  |  |
| XCTest | `xcodebuild test ...` |  |  |
| Static analyzer | `xcodebuild analyze ...` |  |  |
| Release build | `xcodebuild build ...` |  |  |
| Runtime smoke | `xcrun swift Tools/runtime_smoke_test.swift <app executable>` |  |  |
| Accessibility smoke | `xcrun swift Tools/accessibility_smoke_test.swift <app executable>` |  |  |
| Visual state matrix | `xcrun swift Tools/capture_acceptance_states.swift <app executable> <new-output-directory>` |  |  |
| Bundle inventory | `python3 Tools/validate_app_bundle.py <app> --version <version> --build <build> --require-universal` |  |  |
| Signed bundle security | Add `--require-signed-security`; also add `--require-distribution-authority` for a final Developer ID or locally exported Apple distribution artifact |  |  |
| Signing | `codesign --verify --deep --strict --verbose=2 <app>` |  |  |
| Notarization | `xcrun notarytool submit ... --wait` and `xcrun stapler validate` |  |  |
| Checksums | `shasum -a 256` |  |  |

## Human acceptance

| Gate | Tester | Date | Result | Notes |
| --- | --- | --- | --- | --- |
| VoiceOver reading order |  |  |  |  |
| Full Keyboard Access |  |  |  |  |
| Fresh install |  |  |  |  |
| Upgrade migration |  |  |  |  |
| Sound delivery |  |  |  |  |
| Visual delivery |  |  |  |  |
| Both delivery |  |  |  |  |
| Notification actions |  |  |  |  |
| Sleep and wake |  |  |  |  |
| Manual clock correction |  |  |  |  |
| Time zone change |  |  |  |  |
| Multiple displays |  |  |  |  |
| Dark, contrast, reduced transparency |  |  |  |  |
| Exact-candidate native preferences inspected |  |  |  | Full-form machine renders are structural evidence only when AppKit controls show placeholders |
| App Store screenshots reviewed at full size |  |  |  |  |
| Replay Welcome Guide preserves settings |  |  |  |  |
| Restore recommended defaults preserves system choices |  |  |  |  |
| Asset and publication rights |  |  |  |  |

## Publication authority

| Question | Decision |
| --- | --- |
| Is this exact commit approved to push? | No until Nell says yes |
| Is GitHub Pages deployment approved? | No until Nell says yes |
| Is notarized public distribution approved? | No until Nell says yes |
| Is Mac App Store upload approved? | No until Nell says yes |
| Is App Review submission approved? | No until Nell says yes |

## Final notes

Record every deviation from the checklist here. If a gate is intentionally skipped, state who accepted the risk and why.
