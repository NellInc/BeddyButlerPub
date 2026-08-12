# Beddy Butler asset stewardship

This document separates canonical source material, generated release assets, public presentation assets, licence terms, rights evidence, and publication authority. The current inventory is locally verifiable. Reuse rights and permission to publish remain decisions recorded against the exact release candidate.

## Asset classes and authority

| Asset class | Canonical source | Derived or public copies | Automated evidence | Authority boundary |
| --- | --- | --- | --- | --- |
| Voice recordings | `Audio Sources/Originals`, 91 preserved MP3 files | `Beddy Butler/Sounds`, 103 normalized and split MP3 files | `python3 Tools/prepare_audio.py --check` and `Audio Sources/PROCESSING_REPORT.json` | The source code licence does not independently grant voice reuse rights |
| Character artwork | `Artwork Sources/Characters`, three transparent 4K PNG masters | Rig and icon images in `Beddy Butler/Images.xcassets`, responsive WebP files in `Website/assets` | Xcode asset compilation, website validation, and visual review | Character publication and third party reuse require rights-holder authority |
| Application icon | `Artwork Sources/AppIcon/beddy-butler-2026-master-4k.png` | App icon set, website icons, social image, App Store screenshots | Xcode asset compilation, website validation, App Store metadata validation | Brand, name, and icon permission remain distinct from the BSD source licence |
| Interface design | Native SwiftUI source and the Figma file named in `DESIGN_SYSTEM.md` | Native captures and App Store screenshot compositions | XCTest, runtime smoke, accessibility smoke, visual inspection | Screenshots must represent the accepted candidate and retain accurate credits |
| Website and store copy | `Website` and `AppStore/en-GB` | GitHub Pages and App Store Connect | Website and metadata validators | Publication requires explicit destination and candidate approval |
| Release artifacts | Candidate source plus signed archive | Application, ZIP, disk image, or App Store package | Bundle validator, signing checks, notarization checks, and checksums | Machine evidence cannot grant upload, submission, or publication authority |

## Audio provenance and transformation

The 91 source recordings remain byte preserved in `Audio Sources/Originals`. `Tools/prepare_audio.py` is the reproducible transformation authority for the 103 release clips. Its report records source hashes, output hashes, silence based splits, gain adjustments, measured level, and duration. The application bundle must contain only the 103 derived release clips.

The three voice choices have visible, nonverbal descriptions in the app and on the accessibility page:

* Shy is quiet, discreet, and polite.
* Insistent is firmer and more direct.
* Zombie is theatrical, exaggerated, and intentionally startling.

An authoritative line by line transcript catalogue is not present. No release document may imply that one exists. If full transcripts are commissioned, each entry should bind a source hash to reviewed text and distinguish spoken words, vocal effects, silence, and alternate takes. Editorial and rights-holder review is required before those transcripts are published.

## Artwork derivation rules

1. Keep the 4K transparent character and icon masters unchanged.
2. Generate derivatives from a named master, never from a compressed website or screenshot export.
3. Preserve transparency, aspect ratio, colour profile, and intended crop.
4. Keep native application assets, website exports, and store screenshots in their separate destinations.
5. Recreate App Store screenshots from accepted native captures after any visible product change.
6. Record human visual approval for changed character, icon, or screenshot assets.

## Bundle inventory

Run this against every finished application bundle:

```sh
python3 Tools/validate_app_bundle.py \
  "/path/to/Beddy Butler.app" \
  --version 2.0.1 \
  --build 612 \
  --require-universal
```

The validator checks bundle identity, version and build when supplied, executable architectures, exactly 103 MP3 resources with canonical filenames and SHA-256 content, absence of source-only audio directories, and the privacy manifest's local UserDefaults declaration. Release and App Store archive scripts invoke it before distribution packaging.

## Rights and publication record

The existing release checklist records a rights-holder confirmation dated 22 July 2026 for the voice, character, icon, name, and repository. Every candidate still needs an explicit evidence entry confirming that the unchanged assets and intended publication destinations remain within that authority. Any altered voice, artwork, credit, licence, store listing, or destination reopens the rights gate.

The BSD licence in `LICENSE` governs source redistribution under its terms. Recorded voice, character, logo, name, and brand assets carry separate rights. The press page may make published web assets available for editorial reference, while commercial reuse or alteration requires direct permission.

## Stewardship checklist

1. Run source audio, website, App Store metadata, large file, and built bundle validators.
2. Confirm the candidate evidence file records exact source SHA, asset checks, visual review, rights review, and publication destination.
3. Confirm all public credits match README, About, App Store copy, and the press page.
4. Confirm no credential, private schedule data, unreviewed transcript, source-only recording directory, or unsupported rights claim enters a public artifact.
5. Keep push, deployment, notarized distribution, App Store upload, and App Review submission closed until Nell approves the exact candidate.

## Working if

Every shipped asset can be traced to a canonical source or explicit authored copy, generated files are reproducible where practical, the application bundle contains only intended derivatives, rights claims match recorded authority, and publication requires a separate explicit decision.
