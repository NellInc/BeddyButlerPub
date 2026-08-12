# Beddy Butler future roadmap

The recommended path protects Beddy Butler's small, calm utility character. Each stage begins only when its entry evidence exists. Features should reduce evening friction without creating accounts, surveillance, health claims, or a large settings burden.

## Recommendation

Ship the verified 2.0.2 candidate first. Then prioritize localization readiness, authoritative audio transcripts, person-led notification permission transition checks, and one configurable snooze duration. These changes improve inclusion and daily usefulness while preserving the product's privacy and simplicity.

## Stage 0, finish and learn from 2.0.2

### Entry

The local source candidate passes all machine gates and is ready for person-led acceptance.

### Work

1. Complete VoiceOver, Full Keyboard Access, display, sleep, wake, clock, time-zone, audio-route, clean-install, and upgrade checks.
2. Confirm rights, canonical repository, release channel, website destination, App Store record, and public support route.
3. Keep validation on ordinary pushes while requiring a separate exact-candidate action for notarization, App Store upload, or website deployment.
4. Run a small signed beta before public submission.
5. Classify feedback by accessibility, scheduling correctness, comprehension, reliability, and delight.

### Exit

The exact version, build, commit, assets, metadata, signed artifact, and acceptance record are approved for a named destination.

## Stage 1, accessibility and international readiness

### Candidate work

1. Create an authoritative transcript catalogue keyed to source and release clip hashes, with reviewed spoken words and vocal effect descriptions.
2. Move user-visible strings into an Xcode String Catalog while preserving English behavior.
3. Add pseudolocalization checks for clipping, expansion, reordered phrases, dates, times, weekdays, and VoiceOver labels.
4. Commission and review the first real localization only after the base catalogue is stable.
5. Take the existing deterministic notification authorization seam through real macOS permission changes, and extend coverage for provisional or ephemeral states where macOS permits them.
6. Extend person-led testing to high contrast, larger text where applicable, switch input, and alternate keyboard layouts.

### Success signal

Every user-visible string has a stable localization key, pseudolocalized screens remain operable, audio meaning is available in reviewed text, and changing notification permission does not leave stale preference or scheduled state.

## Stage 2, everyday control

### Candidate work

1. Offer a small set of snooze choices, with one remembered default and clear bedtime-boundary behavior.
2. Add Skip Tonight as a reversible one-night action with an exact resume statement.
3. Add Wind Down Now as a manual, unscheduled preview that never mutates the recurring schedule.
4. Add a simple notification authorization status row and a direct route to macOS Settings.
5. Offer a non-GitHub support route only after its operator, privacy statement, retention, and response expectations are defined.

### Success signal

The Tonight panel remains understandable at a glance, every temporary action states when normal scheduling resumes, and no action silently changes the recurring routine.

## Stage 3, schedule convenience and automation

### Candidate work

1. Add optional schedule templates for weekends, selected weekdays, religious observance, and common rotating shifts.
2. Keep templates as one-time configuration helpers rather than hidden scheduling modes.
3. Add Shortcuts actions for status, preview, snooze, pause, resume, skip tonight, and one-night adjustment.
4. Require confirmation for automation that changes persistent schedules or login behavior.
5. Keep automation results local and expose the next resulting nudge immediately.

### Success signal

A template produces ordinary editable settings, Shortcuts actions are reversible or explicitly confirmed, and the app always explains the resulting tonight state.

## Stage 4, carefully gated experiments

Health integrations, Focus integration, widgets, shared schedules, cloud sync, iPhone companions, and cross-platform versions require concrete demand and a new privacy and threat review. Health or sleep claims require evidence, regulatory assessment, careful language, and a clear boundary between a friendly reminder and medical advice.

These experiments should remain outside the main release line until a prototype proves that the benefit exceeds the privacy, accessibility, support, and maintenance cost.

## Evidence without surveillance

Product decisions can use opt-in beta interviews, GitHub issue labels, voluntary support reports, App Store reviews, and structured person-led acceptance. Beddy Butler should not add analytics merely to rank ideas. If diagnostic export is later needed, make it local, previewable, redacted by default, and sent only through an explicit user action.

## Decision rules

1. Preserve local-only operation and the existing no-account experience.
2. Prefer one clear reversible control over a generalized rule engine.
3. Add dependencies only when their benefit exceeds supply-chain and maintenance cost.
4. Bind each release claim to machine evidence, human acceptance, rights review, and publication authority at the appropriate layer.
5. Remove or simplify a feature if it weakens the first-minute journey or makes tonight's state harder to explain.

## Working if

The roadmap keeps the next release small, makes inclusion and reliability the first expansion, provides evidence before structural growth, and gives every later feature a measurable entry and exit gate.
