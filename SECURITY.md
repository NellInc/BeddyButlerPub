# Security policy

## System and scope

Beddy Butler is a local, sandboxed macOS menu bar app. It stores bedtime preferences in the app's local `UserDefaults` container, plays bundled audio, presents local visual state, may show silent local notifications, and may register itself as a login item. It opens fixed support and website URLs in the user's default browser, but the app has no network entitlement and contains no account, analytics, advertising, telemetry, or remote service.

This policy covers the macOS app, its bundled resources, the static public website, local release tooling, App Store metadata, signing and notarization paths, and GitHub Actions workflows in this repository. Historical repositories elsewhere in the Beddy Butler workspace are retained for provenance and are outside this repository's maintained surface.

The `github-pages` deployment environment is restricted to `master`, verified through the GitHub API on 12 August 2026. Where the repository plan supports it, require Nell as the deployment reviewer and disable administrator bypass. Repository settings are an external control and must be checked again before publication; the workflow's exact-SHA approval inputs remain a separate defense.

Protected assets include private bedtime and schedule state, notification content, user control over login persistence and nudges, the integrity of bundled voice and artwork assets, signing credentials, release artifacts, the website domain, and publication authority.

## Threat model and trust boundaries

Relevant attackers include a malicious or compromised contributor, a dependency or workflow supply-chain attacker, a person attempting to substitute release inputs or artifacts, and a website attacker attempting to alter links or public release claims. User-entered schedule values and persisted legacy preferences are untrusted inputs that must be parsed, clamped, and migrated safely. Notification actions and macOS lifecycle events cross system framework boundaries and must not create unauthorized persistent state.

The app trusts macOS frameworks for sandboxing, notifications, audio playback, login item registration, Keychain access, signing, and notarization. The static website accepts no form input and runs no server-side application code. GitHub, Apple Developer services, App Store Connect, DNS, and the local maintainer account are external trust boundaries.

A Mac already controlled by another process running as the same user can read or alter more local state than this app can defend. That limitation does not excuse unexpected network access, privilege requests, credential exposure, release substitution, or persistence against the user's choice.

## Security invariants

1. App Sandbox and hardened runtime remain enabled for distributed builds.
2. The app requests no microphone, camera, contacts, calendar, photos, location, or broad filesystem access.
3. The app has no network entitlement. External links are fixed HTTPS URLs opened by macOS in the default browser.
4. Bedtime settings, onboarding state, snooze state, and pending visual counts remain in the local sandboxed `UserDefaults` container.
5. Local notification alerts remain silent, expose only minimal schedule information, and respond only to the registered Acknowledge, Snooze, Pause, and open actions.
6. Login item registration follows the user's explicit setting and accurately reports macOS approval state.
7. Release credentials remain in macOS Keychain. They never enter repository files, generated evidence, workflow logs, or release artifacts.
8. Release scripts validate candidate source before archiving, constrain destructive paths to controlled temporary or build directories, reject symlink substitution, and require a clean exact-candidate approval token before notarization or App Store upload. Website pushes validate without deploying; GitHub Pages deployment requires a separate exact-SHA manual dispatch.
9. Machine validation, human acceptance, rights confirmation, and publication approval remain separate gates bound to an exact version, build, and Git commit.
10. The public website must not misrepresent collection, tracking, pricing, availability, accessibility, or release status.

## Reportable findings and severity context

Report source-backed issues that realistically violate an invariant or cross one of the boundaries above. Examples include unexpected transmission or exposure of schedule data, a bypass of App Sandbox or user-controlled login persistence, unsafe legacy preference parsing with material impact, notification action confusion that changes state without the intended user action, credential disclosure, artifact substitution, an unintended upload path, compromised public links, or workflow changes that allow untrusted code to access release authority.

A finding is generally high severity when it enables credential theft, unauthorized publication, release artifact substitution, or material private-data disclosure with plausible reachability. It is generally medium when it can persist unwanted behavior, alter security-sensitive state, or expose limited private schedule information under realistic conditions. Low severity applies to constrained integrity or privacy impact with substantial prerequisites. Final severity depends on proven reachability, effective controls, and concrete impact.

## Out of scope and accepted limitations

The following are outside scope unless they demonstrate a boundary crossing or new privilege gain:

1. Social engineering against maintainers.
2. Denial of service against GitHub, Apple, DNS, or other third-party infrastructure.
3. Behavior requiring physical access to an unlocked, already compromised Mac.
4. A process already running as the same user reading state that macOS exposes to that user, without an app-created escalation or disclosure.
5. Automated scanner output without a concrete, source-backed impact on Beddy Butler.
6. Historical code outside this repository and unsupported private experiments.

No exclusion authorizes publication of credentials, private user data, or weaponized proof of concept material.

## Reporting a vulnerability

Use the private reporting route at `https://github.com/NellInc/beddybutlerpub/security`. If private vulnerability reporting is unavailable, use the minimal public issue form only to request a private contact route. Do not include secrets, private bedtime details, private user data, or exploit instructions in a public issue.

Include the affected version and build, macOS version, realistic attack prerequisites, impact, and the smallest safe reproduction description. Security reports are assessed against the exact candidate or public release in which the behavior occurs.

## Known limitations and compensating controls

The repository cannot prove Apple account state, certificate ownership, domain control, App Store questionnaire answers, asset rights, or person-led device acceptance. Those remain explicit human and publication gates in `RELEASE_CHECKLIST.md` and the exact-candidate release evidence record. Local static checks, deterministic tests, sandbox entitlements, Keychain-backed credentials, code signing, notarization, checksums, and pinned GitHub Actions reduce risk but do not replace those gates.

This policy is working if security reviews focus on the boundaries and invariants above, concrete findings include source-backed reachability and impact, and excluded scanner noise does not suppress a real privacy, persistence, credential, artifact, or publication failure.
