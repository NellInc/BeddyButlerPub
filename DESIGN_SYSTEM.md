# Beddy Butler design system

The editable design source lives in [Figma](https://www.figma.com/design/kdPKMw51gdJesIhLhOUq0m). It contains a captured website page and a separate, fully editable macOS UI page for the Tonight popover, Preferences window, and core colour tokens.

## Source of truth

The shipped interface remains native SwiftUI. The canonical implementation is:

* `Beddy Butler/TonightPopoverView.swift` for the menu bar Tonight panel.
* `Beddy Butler/PreferencesViewController.swift` for the Preferences window.
* `Beddy Butler/BeddyDesign.swift` for the palette and shared night glass components.
* `Beddy Butler/ButlerRigView.swift` for the deformable character mesh and personality motion.
* `Website/assets/styles.css` for the corresponding website presentation.

The colour tokens are defined in `BeddyPalette` in `BeddyDesign.swift` and mirrored, except Night Lifted, Success, Orb Bottom, Orb Glyph, Card Eyebrow, and Schedule Time, in the `:root` block of `Website/assets/styles.css`: Night `#061126`, Night Deep `#030916`, Night Lifted `#07152C`, Ink `#F6F9FF`, Muted `#AEBBD0`, Faint `#7889A5` (`#8A9DB9` on the web for AA contrast on cards), Blue `#80C6FF`, Blue Bright `#A9DDFF`, Violet `#9EA9FF`, Warm `#F2B375`, Zombie `#A6D18A`, Success `#A6E2BE`, Glass `#0F1F3A` at 74% (62% on the web), Glass Strong `#0E1D36` at 90% (88% on the web), Line white at 12%, and Line Strong white at 20%.

## Artwork masters

The 4K transparent character masters live in `Artwork Sources/Characters`. The 4K icon master lives in `Artwork Sources/AppIcon/beddy-butler-2026-master-4k.png`. App and website derivatives are generated from these masters rather than from older compressed exports.

## Character motion

Each Butler uses a 32-joint articulated skeleton shared with the website (`Website/assets/avatar-rig/`) and baked by `Tools/bake_native_rigs.cjs` into `Images.xcassets/*Motion.dataset/motion.bin` (`48 × 61..71` SpriteKit warp grids, 120 frames per closed loop, ~9.5 MB total across all three personalities). Native playback runs at 60 fps with `subdivisionLevels = 0`, precomputed source coordinates, cached prefiltered `SKTexture` instances, visibility pausing when offscreen or occluded, and a static unwarped identity pose when Reduce Motion is enabled. Missing or malformed datasets fall back to `ButlerRigidMotion`. The asset catalogue contains crisp 1024-pixel rig textures derived from the 4K masters so the menu bar companion remains lightweight.

## Native visual verification

Set `BEDDY_BUTLER_CAPTURE_UI_DIR` when launching a development build to write exact native renders of the Preferences window and Tonight popover. The App Store screenshot generator accepts these captures through `--preferences` and `--popover`, ensuring the store presentation shows the shipping UI rather than a hand made approximation.

For a candidate-bound state matrix, run `xcrun swift Tools/capture_acceptance_states.swift <executable> <new-output-directory>`. The harness uses isolated defaults domains for welcome, sound, visual, combined progressive, paused, and pending visual states. It records the exact executable and image SHA-256 hashes in `manifest.json`, rejects black or empty images, requires state diversity, refuses a pre-existing candidate process, and removes only its own isolated defaults domains. Manifest schema 2 also records each capture's evidence kind, the Preferences limitation and native-window review requirement, and the fact that the packet carries no publication authority.

The preferences matrix renders the same production sections without the scroll container so the complete form is observable. Some AppKit-backed controls can display unavailable placeholder tiles when rendered without a live window. Treat those images as structural state evidence, then complete exact-candidate native-window visual acceptance on the target Mac. The Tonight popover renders faithfully and at intrinsic height.
