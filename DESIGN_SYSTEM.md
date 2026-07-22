# Beddy Butler design system

The editable design source lives in [Figma](https://www.figma.com/design/kdPKMw51gdJesIhLhOUq0m). It contains a captured website page and a separate, fully editable macOS UI page for the Tonight popover, Preferences window, and core colour tokens.

## Source of truth

The shipped interface remains native SwiftUI. The canonical implementation is:

* `Beddy Butler/AppDelegate.swift` for the menu bar Tonight panel.
* `Beddy Butler/PreferencesViewController.swift` for the Preferences window and shared night glass components.
* `Website/assets/styles.css` for the corresponding website presentation.

The shared visual language uses Night `#061126`, Glass `#172746`, Blue `#85C9FF`, Violet `#9A94FF`, Warm `#E8A870`, Success `#A5F0BD`, and Ink `#F7FAFF`.

## Artwork masters

The 4K transparent character masters live in `Artwork Sources/Characters`. The 4K icon master lives in `Artwork Sources/AppIcon/beddy-butler-2026-master-4k.png`. App and website derivatives are generated from these masters rather than from older compressed exports.

## Native visual verification

Set `BEDDY_BUTLER_CAPTURE_UI_DIR` when launching a development build to write exact native renders of the Preferences window and Tonight popover. The App Store screenshot generator accepts these captures through `--preferences` and `--popover`, ensuring the store presentation shows the shipping UI rather than a hand made approximation.
