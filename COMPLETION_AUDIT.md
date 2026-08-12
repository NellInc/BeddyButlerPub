# Beddy Butler completion audit

This matrix is the authoritative local status of the full improvement programme. It separates work that this checkout can prove from gates that require a person, an Apple or GitHub account, a signed artifact, a managed security worker, or explicit publication authority.

Status meanings:

* **Proven locally**: current source or exact-candidate machine evidence directly demonstrates the requirement.
* **Prepared locally**: the implementation, documentation, or fail-closed control exists, while its external action remains closed.
* **Person gate**: a person must exercise or judge the exact candidate on suitable hardware.
* **Rights gate**: the rights holder must bind approval to the unchanged assets and intended destinations.
* **Distribution gate**: signing, notarization, upload, TestFlight, or store processing requires external account state and explicit approval.
* **Publication gate**: a live mutation is deliberately withheld until Nell approves it.
* **Environment gate**: the required verifier cannot run under this host profile.
* **Roadmap**: deliberately sequenced after the verified 2.0.2 release rather than implied as release scope.

## Local completion matrix

| Programme surface | Requirement | Status | Authoritative proof or remaining authority |
| --- | --- | --- | --- |
| Release preparation | Candidate identity, dirty-state warning, exact evidence record, large-file guard, metadata guard, visual evidence, and fail-closed publication controls | Proven locally | `RELEASE_EVIDENCE_TEMPLATE.md`, `Tools/create_release_evidence.py`, `Tools/check_large_files.py`, `Tools/require_publication_approval.py`, `Tools/capture_acceptance_states.swift`, integrated source validation |
| Release preparation | Commit, signed archive, notarization, packages, or upload | Distribution gate | Requires a clean exact commit, explicit approval phrase, signing identity, and destination credentials |
| Acceptance | Deterministic scheduling, migration, delivery, notification, audio, rendering, source, bundle, and runtime machine checks | Proven locally | 73 XCTest cases plus source, analyzer, universal Release build, bundle, runtime, website, and negative-control evidence in the latest candidate record under `build/release-evidence` |
| Acceptance | VoiceOver, Full Keyboard Access, native visual judgment, real Notification Centre, audio routes, sleep and wake, clock changes, clean install, upgrade, and multiple displays | Person gate | `RELEASE_CHECKLIST.md` and exact-candidate evidence table |
| Product clarity | First-launch guidance, above-the-fold Tonight state, explicit snooze and pause, preview, onboarding replay, and confirmed defaults restoration | Proven locally | Production views, accessibility identifiers, state captures, and XCTest coverage |
| Accessibility | Labels and hints, text plus symbol state, Reduced Motion behavior, visual delivery, accessibility support route, and dedicated issue intake | Proven locally | App sources, rig tests, `Website/accessibility/index.html`, `.github/ISSUE_TEMPLATE/accessibility.yml` |
| Accessibility | Reading order, focus restoration, Reduced Transparency appearance, alternate input, and real notification action quality | Person gate | Exact-candidate macOS acceptance |
| Accessibility | Authoritative transcript catalogue and first localization | Roadmap plus rights gate | Requires editorial transcription, rights review, stable localization catalogue, and commissioned language review |
| Reliability | DST gap and duplicate hour, cross-midnight windows, long sleep logic, backward clock changes, time-zone changes, snooze edits, persistent visual state, and notification authorization races | Proven locally | `Beddy ButlerTests` and current integrated validation |
| Architecture | Notification boundary, Tonight presentation, and shared design primitives extracted from lifecycle and preferences hosts | Proven locally | `LocalNotificationManager.swift`, `TonightPopoverView.swift`, `BeddyDesign.swift`, project membership, `ARCHITECTURE.md` |
| Architecture | Further settings-model and localization splits | Roadmap | Deferred until feature work needs the boundary, preserving the current release candidate from speculative churn |
| CI | Source, plist, audio, website, App Store, security, publication, live-validator offline controls, large-file checks, formatting, and tests | Prepared locally | `.github/workflows/ci.yml`; remote execution starts only after an approved push |
| Website | Six-page candidate, FAQ, accessibility statement, press page, privacy, support, metadata, sitemap, responsive browser checks, and current live baseline probe | Proven locally | Website validators, browser smoke evidence, and current-mode live validation |
| Website | Candidate deployment and byte-for-byte publication verification | Publication gate | Manual exact-SHA Pages dispatch, live publication mode, domain and environment authority |
| App Store | Copy, review notes, privacy summary, canonical URLs, screenshot order, count, format, and dimensions | Proven locally | `AppStore`, `Tools/validate_app_store_metadata.py`, six 2880 by 1800 screenshots |
| App Store | Account record, agreements, pricing, territories, questionnaires, processed build, TestFlight, and submission | Distribution gate | App Store Connect authority, Apple distribution signing, explicit exact-candidate approval, and person testing |
| Governance | Contribution guide, security policy, issue intake, publication controls, and canonical active checkout documentation | Proven locally | `CONTRIBUTING.md`, `SECURITY.md`, `.github/ISSUE_TEMPLATE`, `REVIVAL_NOTES.md`, repository remote and live validator |
| Governance | Archive, redirect, or retain historical repositories | Publication gate plus Nell decision | Workspace `REPOSITORY_MAP.md` preserves the inventory; remote settings remain untouched |
| Assets | Original and derived inventories, reproducible audio processing, artwork masters, bundle contents, licence boundary, and no implied transcript catalogue | Proven locally | `ASSET_STEWARDSHIP.md`, `DESIGN_SYSTEM.md`, `Audio Sources/PROCESSING_REPORT.json`, audio and bundle validators |
| Assets | Exact-candidate asset and destination rights confirmation | Rights gate | The 22 July authority is historical evidence; this candidate still needs explicit confirmation |
| Privacy | Local-only data, no account or analytics, fixed external links, no microphone, local notifications, sandbox, privacy manifest, and no app network entitlement | Proven locally | `PRIVACY.md`, `SECURITY.md`, entitlements, `PrivacyInfo.xcprivacy`, source and bundle security validators |
| Security | Threat boundary, negative controls, secret scans, dependency applicability review, parser-clean targeted static review, signed-bundle fail-closed checks | Proven locally with stated limits | Latest candidate record under `build/release-evidence`; supplemental checks are not represented as exhaustive |
| Security | Codex Security Deep Scan | Environment gate | Deep discovery twice refused to start because the parent session lacks a managed read-only filesystem permission profile |
| Future roadmap | Accessibility and localization, everyday controls, schedule templates, Shortcuts, and carefully gated experiments have entry, exit, privacy, and support rules | Proven locally as planning | `FUTURE_ROADMAP.md` |

## Exact local candidate

The current candidate remains a dirty local working tree by design. Its evidence record is generated under `build/release-evidence` and binds the base commit, version, build, and complete working-tree digest. That record cannot become publication authority. Any source, copy, asset, metadata, signing, or commit change requires fresh evidence.

No local pass may promote a person, rights, signed-distribution, security-environment, or publication gate. No remote action is authorized by this matrix.

## Closure sequence

1. Nell reviews the complete local diff, exact v3 app, native Preferences window, Tonight states, and App Store screenshots.
2. Record exact-candidate person and rights outcomes in a newly generated evidence record.
3. If accepted, create an intentional exact-path commit and regenerate clean candidate evidence. A commit does not authorize a push.
4. Build and verify a signed local beta, then complete the clean-install, upgrade, VoiceOver, keyboard, display, sleep and wake, clock, time-zone, audio-route, notification, and visual checks.
5. Retry Deep Security Scan only from a session that exposes a managed read-only worker filesystem profile.
6. Authorize and perform each destination action separately: push, Pages deployment, notarization, App Store upload, TestFlight, and App Review.
7. Run publication-mode live validation after website deployment and bind its result to the deployed SHA.

## Working if

Anyone reviewing the candidate can identify the proof for every local claim, see every nonlocal gate without inference, and cannot mistake a green machine check for person acceptance, rights authority, signed distribution, exhaustive security clearance, or permission to publish.
