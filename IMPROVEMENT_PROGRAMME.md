# Beddy Butler improvement programme

This is the local working goal for the full post 2.0.1 improvement sweep. It turns the broad backlog into executable phases while preserving the rule that nothing is pushed, deployed, uploaded, or submitted until Nell verifies the candidate.

## Operating contract

1. Keep all work local until Nell explicitly approves a push, deployment, upload, notarized distribution, or App Review submission.
2. Preserve the active application line in this repository. Historical clones in the parent folder remain reference material unless a task explicitly says otherwise.
3. Separate machine evidence from human acceptance and publication authority. A passing build does not prove VoiceOver quality, rights, App Store readiness, or public release authority.
4. Regenerate release evidence after any candidate source, asset, copy, signing, or metadata change.
5. Keep credentials in Keychain, not files.

## Phase 1, release evidence and candidate control

| Item | Action | Status | Verification |
| --- | --- | --- | --- |
| Evidence template | Maintain a single release evidence template with hash, logs, artifact paths, and human gates | Added locally | `RELEASE_EVIDENCE_TEMPLATE.md` exists |
| Evidence generator | Create a candidate-bound evidence record with project version, build, SHA, branch, date, and dirty-state warning | Added locally | `python3 Tools/create_release_evidence.py` |
| Candidate freeze | Treat version plus build plus Git commit as the candidate identity | Added locally | Template records candidate SHA |
| Dirty release guard | Keep release scripts clean by default, with explicit local override only | Existing | `Tools/validate_release_source.sh` |
| Large file guard | Check working tree and recent history for files above 50 MB before push or release | Added locally | `python3 Tools/check_large_files.py` |
| App Store metadata guard | Validate local App Store copy files, required URLs, privacy summary, and screenshot dimensions | Added locally | `python3 Tools/validate_app_store_metadata.py` |
| CI evidence | Upload test and validation artifacts from CI | Added locally | `.github/workflows/ci.yml` |
| Publication interlocks | Require exact clean commit approval for notarization, App Store upload, and manual website deployment | Added locally | `Tools/require_publication_approval.py`, publication control tests, and `.github/workflows/pages.yml` |
| Visual state evidence | Capture six isolated product states with executable and image hashes, black-frame rejection, and diversity checks | Added locally | `Tools/capture_acceptance_states.swift`; native Preferences inspection remains a person-led gate when offscreen AppKit controls use placeholders |

## Phase 2, human acceptance gates

| Item | Action | Status | Verification |
| --- | --- | --- | --- |
| VoiceOver | Complete onboarding, preferences, Tonight popover, menu, and notification actions | Human gate | Signed acceptance note |
| Full Keyboard Access | Complete every setup and menu path without pointer input | Human gate | Signed acceptance note |
| Multi display | Test one display and multiple displays, including notch or crowded menu bar | Human gate | Signed acceptance note |
| Sleep and wake | Test due nudge during sleep and after wake | Human gate | Signed acceptance note |
| Time changes | Test manual clock correction, daylight saving edge, and travel time zone | Human gate | Signed acceptance note |
| Audio route changes | Test headphones, speakers, muted output, and output device switch | Human gate | Signed acceptance note |
| Clean install and upgrade | Test clean user account plus original preference migration | Human gate | Signed acceptance note |

## Phase 3, product clarity

| Item | Action | Status | Verification |
| --- | --- | --- | --- |
| What happens tonight | Keep next nudge, personality, and paused or snoozed state above the fold | Existing, keep verifying | Screenshot and accessibility smoke |
| Snooze versus pause | Keep copy explicit that snooze is temporary and pause lasts tonight | Existing, keep verifying | Human acceptance |
| Preview moment | Encourage a first launch preview before relying on the schedule | Existing and documented | Welcome guide plus preview control |
| Schedule templates | Define common alternate schedule presets without adding hidden scheduling modes | Roadmap defined | `FUTURE_ROADMAP.md` |
| Replay onboarding | Add menu and Preferences commands to show guidance again without changing settings | Added locally | Unit test and accessible control identifier |
| Restore defaults | Add a confirmed reset for product settings while preserving system level permissions and login configuration | Added locally | Unit test and confirmation dialog |

## Phase 4, accessibility and inclusion

| Item | Action | Status | Verification |
| --- | --- | --- | --- |
| Accessibility issue path | Provide a dedicated GitHub issue template | Added locally | `.github/ISSUE_TEMPLATE/accessibility.yml` |
| Audio descriptions | Keep visible personality descriptions for users who do not hear the preview | Added locally | App guidance and `Website/accessibility/index.html` |
| Full transcripts | Create a reviewed line-by-line catalogue bound to source and release hashes | Rights and editorial gate | `ASSET_STEWARDSHIP.md` and `FUTURE_ROADMAP.md` |
| Reduced Motion | Preserve identity pose and non animated fallback | Existing | Rig tests |
| Reduced Transparency | Preserve readable fallback materials | Existing, human gate | Screenshot inspection |
| Localization | Define String Catalog, pseudolocalization, and first-language gates | Roadmap defined | `FUTURE_ROADMAP.md` |

## Phase 5, reliability and scheduling

| Item | Action | Status | Verification |
| --- | --- | --- | --- |
| DST spring gap | Keep deterministic coverage | Existing | XCTest |
| DST fall duplicate hour | Keep deterministic first occurrence coverage for repeated local times | Added locally | XCTest |
| Long sleep | Cover one overdue nudge inside the active window and no delivery outside it | Added locally | XCTest |
| Clock jumps backward | Recalculate from corrected wall time | Added locally | XCTest |
| Snooze setting edits | Preserve promised resume across frequency and delivery edits, and move safely after active night edits | Added locally | XCTest |
| Notification authorization transitions | Test denied to allowed, allowed to denied, and stale authorization replies | Added locally | Injected notification boundary plus XCTest |

## Phase 6, code architecture

| Item | Action | Status | Verification |
| --- | --- | --- | --- |
| Architecture map | Document current components and split targets | Added locally | `ARCHITECTURE.md` |
| Preferences split | Extract shared visual primitives while retaining one coherent feature view | First slice added locally | `BeddyDesign.swift`, no UI behavior change, tests pass |
| AppDelegate split | Extract notifications and the Tonight popover from lifecycle ownership | Added locally | Complete XCTest suite |
| Settings split | Separate keys, models, migration, and persistence | Future refactor | Migration tests pass |
| Localization seam | Extract strings without changing English copy | Future refactor | Snapshot or accessibility checks |

## Phase 7, website and public presentation

| Item | Action | Status | Verification |
| --- | --- | --- | --- |
| Local website validation | Check local links, assets, metadata, sitemap, manifest, hidden files | Existing, extended candidate | `python3 Tools/validate_website.py` |
| Public destination validation | Verify the current public baseline separately from the approved post-deployment state | Added locally; current mode passes, publication mode remains closed | `python3 Tools/test_live_destinations.py`; `python3 Tools/validate_live_destinations.py --mode current`; use `--mode publication` only as the post-deployment gate |
| Live URL validation | Verify HTTPS 200 for home, support, privacy, sitemap, 404, App Store URL | Human or release gate | Network evidence captured before publish |
| FAQ | Add no account, no tracking, no microphone, notifications, launch at login, quit | Added locally | `Website/support/index.html` |
| Accessibility statement | Add a public accessibility support note with exact-candidate verification boundaries | Added locally | `Website/accessibility/index.html` |
| Press kit | Add icon, screenshots, description, privacy summary, credits | Added locally, rights gate retained | `Website/press/index.html` |

## Phase 8, repository governance

| Item | Action | Status | Verification |
| --- | --- | --- | --- |
| Canonical repository | Confirm public canonical repo and active local folder | Needs Nell decision | Repository map updated after decision |
| Historical clones | Archive, retain, or label each historical repository | Needs Nell decision | GitHub settings or README changes |
| Contribution guide | Add local contribution guidance | Added locally | `CONTRIBUTING.md` |
| Security policy | Add local security policy | Added locally | `SECURITY.md` |
| Issue templates | Expand bug and accessibility reporting | Added locally | `.github/ISSUE_TEMPLATE` |

## Phase 9, asset, rights, and privacy stewardship

| Item | Action | Status | Verification |
| --- | --- | --- | --- |
| Rights confirmation | Record voice, character, icon, name, and publication authority | Human gate | Release evidence note |
| Asset provenance | Keep source recordings and artwork masters distinct from generated assets | Added locally | `ASSET_STEWARDSHIP.md`, `DESIGN_SYSTEM.md`, processing report |
| Bundle inventory | Verify release app includes canonical derived audio only, privacy manifest, identity, version, and architectures | Added and validated locally | `Tools/validate_app_bundle.py` and release scripts |
| Secret handling | Keep notarization and Apple credentials in Keychain | Existing release contract | No plaintext secret files |
| Security posture | Enforce sandbox-only source entitlements, hardened runtime, privacy manifest exactness, fixed destinations, no unsupported sensitive permissions or network surface, and safe signed entitlements | Added locally | `Tools/validate_security_posture.py`, negative controls, and signed bundle validation |
| Privacy questionnaire | Keep App Store answers aligned with actual local only behavior | Human gate | App Store Connect review |

## Phase 10, future product expansion

`FUTURE_ROADMAP.md` defines evidence-gated stages for 2.0.1 acceptance, accessibility and localization, everyday control, schedule convenience, Shortcuts, and carefully gated experiments. Health, Focus, widgets, or cross-platform work waits for concrete demand plus a new privacy, accessibility, support, and threat review.

## Recommended execution order

1. Land local governance, evidence, validation, and issue template improvements.
2. Run validation locally.
3. Nell verifies the local diff and decides canonical repository and publication destinations.
4. Only after approval, commit and push.
5. Complete person led acceptance gates.
6. Notarize or upload the verified candidate.

## Completion authority

`COMPLETION_AUDIT.md` maps every programme surface to current proof or its remaining person, rights, distribution, publication, environment, or roadmap gate. It is the local completion index. The exact candidate evidence record remains the authority for one version, build, commit, and working-tree digest.
