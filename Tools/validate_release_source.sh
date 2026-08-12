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
xcode_jobs="${BEDDY_XCODE_JOBS:-2}"
if [[ ! "$xcode_jobs" =~ '^[1-9][0-9]*$' ]]; then
  print -u2 "BEDDY_XCODE_JOBS must be a positive integer."
  exit 64
fi
chmod 700 "$validation_root"
trap 'rm -rf -- "$validation_root"' EXIT

xcrun swift-format lint --recursive "Beddy Butler" "Beddy ButlerTests" Tools
plutil -lint \
  "Beddy Butler.xcodeproj/project.pbxproj" \
  "Beddy Butler/Info.plist" \
  "Beddy Butler/Beddy Butler.entitlements" \
  "Beddy Butler/PrivacyInfo.xcprivacy" >/dev/null
python3 Tools/validate_website.py
python3 Tools/validate_app_store_metadata.py
python3 Tools/check_large_files.py
python3 Tools/test_app_bundle_validation.py
python3 Tools/test_release_evidence.py
python3 Tools/test_publication_approval.py
python3 Tools/validate_publication_controls.py
python3 Tools/test_security_posture.py
python3 Tools/test_live_destinations.py
python3 Tools/prepare_audio.py --check
xcodebuild test \
  -project "Beddy Butler.xcodeproj" \
  -scheme "Beddy Butler" \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath "$validation_root/DerivedData" \
  -jobs "$xcode_jobs" \
  -parallel-testing-enabled NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  CLANG_STAT_CACHE_ENABLE=NO \
  CODE_SIGNING_ALLOWED=NO

print "Release source validation passed."
