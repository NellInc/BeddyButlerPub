#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
cd "$root"

temporary_base="${TMPDIR:-/tmp}"
resolved_temporary_base="${temporary_base:A}"
if [[ "$resolved_temporary_base" == "/" || "$resolved_temporary_base" == "${HOME:A}" || "$resolved_temporary_base" == "${root:A}" ]]; then
  print -u2 "Unsafe temporary directory: $temporary_base"
  exit 64
fi

if [[ "${BEDDY_ALLOW_DIRTY_RELEASE:-0}" != "1" ]] && [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
  print -u2 "Release validation requires a clean Git working tree."
  print -u2 "Commit or stash the intended release, or set BEDDY_ALLOW_DIRTY_RELEASE=1 for a deliberate local verification."
  exit 65
fi

validation_root="$(mktemp -d "${temporary_base%/}/BeddyButler-ReleaseValidation.XXXXXX")"
chmod 700 "$validation_root"
trap 'rm -rf -- "$validation_root"' EXIT

xcrun swift-format lint --recursive "Beddy Butler" "Beddy ButlerTests" Tools
plutil -lint \
  "Beddy Butler.xcodeproj/project.pbxproj" \
  "Beddy Butler/Info.plist" \
  "Beddy Butler/Beddy Butler.entitlements" \
  "Beddy Butler/PrivacyInfo.xcprivacy" >/dev/null
python3 Tools/validate_website.py
python3 Tools/prepare_audio.py --check
xcodebuild test \
  -project "Beddy Butler.xcodeproj" \
  -scheme "Beddy Butler" \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath "$validation_root/DerivedData" \
  CODE_SIGNING_ALLOWED=NO

print "Release source validation passed."
