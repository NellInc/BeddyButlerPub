# Beddy Butler release checklist

## Automated gate

1. Run the full XCTest suite, static analyzer, Release build, plist validation, `python3 Tools/prepare_audio.py --check`, and design lint.
2. Confirm every Zombie release clip is at most 10 seconds and the processing report matches the 91 preserved sources.
3. Confirm the Release bundle contains 103 MP3 files and no source-only recordings.
4. Confirm App Sandbox and hardened runtime remain enabled, with no microphone or network entitlement.
5. Check the staged tree and recent commit range for files larger than 50 MB.
6. Run `xcrun swift Tools/runtime_smoke_test.swift <path-to-signed-executable>` and confirm the real preferences window appears.
7. Run `xcrun swift Tools/accessibility_smoke_test.swift <path-to-signed-executable>` from a terminal with Accessibility permission.
8. Confirm visual nudge state and count survive quit and relaunch until acknowledged.
9. Confirm silent local notifications contain Acknowledge, Snooze, and Pause actions and make no network request.
10. Confirm `PrivacyInfo.xcprivacy` is present in `Contents/Resources`, declares UserDefaults reason `CA92.1`, and declares no tracking or collected data.

## Signed beta gate

1. Store notarization credentials once with `xcrun notarytool store-credentials beddy-butler-notary`.
2. Run `Tools/release.sh <version> <build>` from a Mac holding the Developer ID Application identity.
3. Install the notarized build on a clean macOS account.
4. Confirm first launch, normal and pending menu-bar icons, left-click Tonight panel, right-click command menu, preferences, audio, Open at Login approval, quit, and relaunch.

## Mac App Store gate

1. Create the App Store Connect record for bundle identifier `com.nellwatson.Beddy-Butler` before uploading a build.
2. Accept current developer agreements and confirm Beddy Butler is available as the product name.
3. Run `Tools/app_store_release.sh --preflight 2.0 1` and resolve every failure.
4. Confirm an Apple Distribution certificate or Xcode managed cloud signing is available.
5. Run `Tools/app_store_release.sh --upload 2.0 1` and confirm the build finishes processing in App Store Connect.
6. Apply the copy and URLs from `AppStore/en-GB`, then upload the 2880 by 1800 images from `AppStore/Screenshots`.
7. Complete the age rating, pricing, territories, export compliance, content rights, and app privacy questionnaires accurately.
8. Confirm the Marketing, Support, and Privacy URLs return HTTP 200 over HTTPS before submission.
9. Test the processed build through TestFlight on a clean macOS account before sending it to review.

## Website gate

1. Run `python3 Tools/validate_website.py` and `npx impeccable detect Website`.
2. Confirm the GitHub Pages workflow completes on `master`.
3. Configure `www.beddybutler.com` as the repository custom domain before changing DNS.
4. Point the apex to GitHub Pages and `www` to `NellInc.github.io`, then enable HTTPS after DNS validation.
5. Verify the apex redirects to `https://www.beddybutler.com/` and that the home, privacy, support, sitemap, and 404 responses are correct.

## Person-led acceptance

1. Complete every control using Full Keyboard Access.
2. Complete onboarding and the menu workflow with VoiceOver, checking reading order, focus restoration, and spoken state changes.
3. Verify Sound, Visual, and Both delivery. Confirm Visual stays silent, the badge persists across relaunch until acknowledged, and Both produces one sound plus one badge.
4. Verify arbitrary active-night and second-schedule combinations, including a religious-observance pattern, a rotating-shift pattern, a cross-midnight window, and a one-night adjustment.
5. Inspect default, minimum-size, dark, increased-contrast, and reduced-transparency appearances.
6. Test sleep and wake, a manual clock correction, a time-zone change, an overnight window, and an audio-output-device change.
7. Test on one-display and multiple-display Macs.
8. Record that voice, character, icon, name, and repository publication rights were confirmed by the rights holder on 22 July 2026.
