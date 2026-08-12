# Beddy Butler release checklist

Use `COMPLETION_AUDIT.md` for the programme-wide proof matrix. This checklist remains the operational gate list for a specific release candidate.

## Automated gate

1. Run `zsh Tools/validate_release_source.sh`, then run the static analyzer, unsigned universal Release build, and design lint.
2. Confirm every Zombie release clip is at most 10 seconds and the processing report matches the 91 preserved sources.
3. Run `python3 Tools/validate_app_bundle.py <app> --version <version> --build <build> --require-universal` and confirm the Release bundle contains all 103 canonical MP3 files with matching SHA-256 content, no source-only recordings, the expected privacy manifest, and both supported architectures.
4. Run `python3 Tools/test_security_posture.py` and confirm App Sandbox, hardened runtime, minimal entitlements, privacy declarations, fixed destinations, and absence of sensitive permissions or network APIs.
5. Run `python3 Tools/check_large_files.py` and confirm the working tree, staged tree, and recent commit range contain no file larger than 50 MB.
6. Run `xcrun swift Tools/runtime_smoke_test.swift <path-to-signed-executable>` and confirm the real preferences window appears.
7. Run `xcrun swift Tools/accessibility_smoke_test.swift <path-to-signed-executable>` from a terminal with Accessibility permission.
8. Run `xcrun swift Tools/capture_acceptance_states.swift <app executable> <new-output-directory>`. Verify all 12 image hashes against the manifest and inspect the six-state Tonight contact sheet. Treat the complete-form Preferences renders as structural evidence when AppKit controls display placeholders, then inspect the real Preferences window manually on the exact candidate.
9. Confirm visual nudge state and count survive quit and relaunch until acknowledged.
10. Confirm silent local notifications contain Acknowledge, Snooze, and Pause actions and make no network request.
11. Confirm `PrivacyInfo.xcprivacy` is present in `Contents/Resources`, declares UserDefaults reason `CA92.1`, and declares no tracking or collected data.
12. Run `python3 Tools/validate_app_store_metadata.py` and confirm all text limits, canonical URLs, privacy wording, screenshot names, count, and dimensions pass.
13. Create the candidate evidence record with `python3 Tools/create_release_evidence.py`, then record every command result and artifact path in that exact candidate's file.

## Signed beta gate

1. Store notarization credentials once with `xcrun notarytool store-credentials beddy-butler-notary`.
2. Confirm the signed app passes `python3 Tools/validate_app_bundle.py <app> --version <version> --build <build> --require-universal --require-signed-security --require-distribution-authority`, including a Developer ID authority, hardened runtime, App Sandbox, no debug entitlement, and no unexpected entitlements. The release script enforces this before notarization.
3. Record Nell's approval for the exact clean commit, version, and build. Set `BEDDY_NOTARIZATION_APPROVAL` to `NOTARIZE:<40-character-commit>:<version>:<build>`, then run `Tools/release.sh <version> <build> --notarized` from a Mac holding the Developer ID Application identity.
4. Install the notarized build on a clean macOS account.
5. Confirm first launch, normal and pending menu-bar icons, left-click Tonight panel, right-click command menu, preferences, audio, Open at Login approval, quit, and relaunch.

## Mac App Store gate

1. Create the App Store Connect record for bundle identifier `com.nellwatson.Beddy-Butler` before uploading a build.
2. Accept current developer agreements and confirm Beddy Butler is available as the product name.
3. Run `Tools/app_store_release.sh --preflight 2.0.2 612` and resolve every failure.
4. Confirm an Apple Distribution certificate or Xcode managed cloud signing is available.
5. Record Nell's approval for the exact clean commit, version, and build. Set `BEDDY_APP_STORE_UPLOAD_APPROVAL` to `APP_STORE_UPLOAD:<40-character-commit>:2.0.2:612`, run `Tools/app_store_release.sh --upload 2.0.2 612`, and confirm the build finishes processing in App Store Connect.
6. Apply the copy and URLs from `AppStore/en-GB`, then upload the six 2880 by 1800 images from `AppStore/Screenshots` in filename order.
7. Complete the age rating, pricing, territories, export compliance, content rights, and app privacy questionnaires accurately.
8. Confirm the Marketing, Support, and Privacy URLs return HTTP 200 over HTTPS before submission.
9. Test the processed build through TestFlight on a clean macOS account before sending it to review.
10. Leave upload and App Review submission closed until Nell explicitly approves the exact version, build, commit, metadata, screenshots, and rights record.

## Website gate

1. Run `python3 Tools/validate_website.py`, `python3 Tools/test_live_destinations.py`, and `npx impeccable detect Website`.
2. Run `python3 Tools/validate_live_destinations.py --mode current`. Confirm the current public home, privacy, support, sitemap, security contact, App Store record, and canonical repository are coherent, while the unpublished accessibility and press routes remain HTTP 404.
3. After Nell approves the exact clean commit, manually dispatch the GitHub Pages workflow on `master` with that 40-character SHA and `DEPLOY_WEBSITE:<40-character-commit>` as the approval input. Confirm validation and deployment complete for that SHA.
4. Confirm the `github-pages` environment remains restricted to `master`. This was verified through the GitHub API on 12 August 2026. If the repository plan supports it, require Nell as a deployment reviewer and disable administrator bypass. Workflow input checks remain required even when environment protection is configured.
5. Configure `www.beddybutler.com` as the repository custom domain before changing DNS.
6. Point the apex to GitHub Pages and `www` to `NellInc.github.io`, then enable HTTPS after DNS validation.
7. After deployment, run `python3 Tools/validate_live_destinations.py --mode publication`. Confirm the apex redirects to the canonical `www` origin, every candidate web file matches the local candidate byte for byte, and the home, privacy, support, accessibility, press, sitemap, robots, security contact, App Store record, repository, and unknown-route 404 checks all pass.

## Person-led acceptance

1. Complete every control using Full Keyboard Access.
2. Complete onboarding and the menu workflow with VoiceOver, checking reading order, focus restoration, and spoken state changes.
3. Verify Sound, Visual, and Both delivery. Confirm Visual stays silent, the badge persists across relaunch until acknowledged, and Both produces one sound plus one badge.
4. Verify arbitrary active-night and second-schedule combinations, including a religious-observance pattern, a rotating-shift pattern, a cross-midnight window, and a one-night adjustment.
5. Inspect default, minimum-size, dark, increased-contrast, and reduced-transparency appearances.
6. Test sleep and wake, a manual clock correction, a time-zone change, an overnight window, and an audio-output-device change.
7. Test on one-display and multiple-display Macs.
8. Record that voice, character, icon, name, and repository publication rights were confirmed by the rights holder on 22 July 2026.
9. Replay the Welcome Guide and confirm the saved schedule, personality, volume, and delivery choices remain unchanged.
10. Restore recommended defaults, confirm the destructive action asks first, and verify Open at Login plus macOS notification permission remain unchanged.
11. Record every result in the exact candidate evidence file. A prior candidate's acceptance does not transfer after any source, asset, metadata, or signing change.
