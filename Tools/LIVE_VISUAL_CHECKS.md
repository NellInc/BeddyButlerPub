# Opt-in live visual checks

These checks use temporary output folders and isolated defaults. They do not replace the installed app.

## Continuous native motion

Run xcodebuild test with these environment variables:

- TEST_RUNNER_BEDDY_MOTION_PROOF_DIR=/tmp/beddy-motion-proof
- TEST_RUNNER_BEDDY_BUTLER_RIG_CAPTURE=1

`testLiveAnimationTimingCapture` opens a three-avatar window, saves sampled poses, then records uninterrupted simultaneous and individual timing intervals. The TEST_RUNNER_ prefix forwards variables into the test host. Without the opt-in variable, this hardware-dependent diagnostic is skipped. Working evidence consists of populated timing JSON, changing visible poses, and a completed test result; a successful build alone is insufficient.

## Actual secondary menu

Build a separate local Debug candidate (the Debug configuration sets SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG). Launch its executable with:

- BEDDY_MENU_PROOF_DIR=/tmp/beddy-menu-proof
- BEDDY_BUTLER_DEFAULTS_SUITE=BeddyButler.MenuProof.UNIQUE_RUN_NAME

The DEBUG-only capture opens the actual menu for setup, active and paused states, records item enablement, and captures only an owned menu window. It exits afterwards. Inspect PNGs: transient transparent captures are not valid visual evidence. Working output shows disabled Pause before setup, enabled Pause after activation, and enabled Resume when paused. Direct popup capture does not substitute for testing physical mouse dispatch.
