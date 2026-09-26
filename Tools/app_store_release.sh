#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
cd "$root"

mode="${1:---preflight}"
requested_version="${2:-}"
requested_build="${3:-}"
team_id="${BEDDY_APPLE_TEAM_ID:-BBYYCBH7EW}"
temporary_base="${TMPDIR:-/tmp}"
resolved_temporary_base="${temporary_base:A}"

if [[ "$resolved_temporary_base" == "/" || "$resolved_temporary_base" == "${HOME:A}" || "$resolved_temporary_base" == "${root:A}" ]]; then
  print -u2 "Unsafe temporary directory: $temporary_base"
  exit 64
fi

safe_to_replace() {
  local candidate="$1"
  local label="$2"
  local resolved="${candidate:A}"
  local temp_root="$resolved_temporary_base"
  local build_root="${root:A}/build"

  if [[ -L "$candidate" ]]; then
    print -u2 "Refusing to replace symlinked $label path: $candidate"
    exit 64
  fi
  if [[ "$resolved" != "$temp_root"/* && "$resolved" != "$build_root"/* ]]; then
    print -u2 "$label must be inside $temporary_base or $root/build: $candidate"
    exit 64
  fi
}

case "$mode" in
  --preflight|--export|--upload) ;;
  *)
    print -u2 "Usage: Tools/app_store_release.sh [--preflight|--export|--upload] [version] [build]"
    exit 64
    ;;
esac

command -v rg >/dev/null 2>&1 || {
  print -u2 "ripgrep (rg) is required for the update-path scan."
  exit 69
}

build_settings="$(
  xcodebuild -project "Beddy Butler.xcodeproj" -scheme "Beddy Butler" \
    -configuration Release -showBuildSettings 2>/dev/null
)" || {
  print -u2 "Could not read the Release build settings."
  exit 1
}
build_setting() {
  print -r -- "$build_settings" |
    awk -F ' = ' -v key="$1" '
      !found && $1 ~ ("^[[:space:]]*" key "$") { value = $2; found = 1 }
      END { print value }
    '
}
project_version="$(build_setting MARKETING_VERSION)"
project_build="$(build_setting CURRENT_PROJECT_VERSION)"
bundle_id="$(build_setting PRODUCT_BUNDLE_IDENTIFIER)"
[[ -n "$project_version" && -n "$project_build" ]] || {
  print -u2 "Could not resolve the project version and build."
  exit 1
}
version="${requested_version:-$project_version}"
build="${requested_build:-$project_build}"
if [[ "$version" != "$project_version" || "$build" != "$project_build" ]]; then
  print -u2 "Requested $version ($build) differs from the project's $project_version ($project_build)."
  print -u2 "Update MARKETING_VERSION and CURRENT_PROJECT_VERSION in the Xcode project instead."
  exit 65
fi
archive="${BEDDY_ARCHIVE_PATH:-${temporary_base}/BeddyButler-${version}-${build}.xcarchive}"
export_dir="${BEDDY_EXPORT_PATH:-${temporary_base}/BeddyButler-AppStore-${version}-${build}}"

if [[ ! "$version" =~ '^[0-9]+([.][0-9]+){1,2}$' ]]; then
  print -u2 "The marketing version must contain two or three numeric components."
  exit 64
fi
if [[ ! "$build" =~ '^[1-9][0-9]*$' ]]; then
  print -u2 "The build number must be a positive integer."
  exit 64
fi

if [[ "$mode" == "--upload" ]]; then
  python3 Tools/require_publication_approval.py \
    --action app-store-upload \
    --version "$version" \
    --build "$build"
fi

zsh Tools/validate_release_source.sh

required=(
  "Beddy Butler/PrivacyInfo.xcprivacy"
  "Beddy Butler/Beddy Butler.entitlements"
  "Beddy Butler/Info.plist"
  "Website/privacy/index.html"
  "Website/support/index.html"
)
for required_path in "${required[@]}"; do
  [[ -f "$required_path" ]] || { print -u2 "Missing release requirement: $required_path"; exit 1; }
done

plutil -lint   "Beddy Butler/PrivacyInfo.xcprivacy"   "Beddy Butler/Beddy Butler.entitlements"   "Beddy Butler/Info.plist" >/dev/null

[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "Beddy Butler/Beddy Butler.entitlements")" == "true" ]] || {
  print -u2 "App Sandbox must remain enabled for Mac App Store distribution."
  exit 1
}

scan_rc=0
rg -q 'Check for Updates|releases/latest' "Beddy Butler" README.md PRIVACY.md || scan_rc=$?
if (( scan_rc == 0 )); then
  print -u2 "A non-App-Store update path remains in the product surface."
  exit 1
elif (( scan_rc != 1 )); then
  print -u2 "The update-path scan failed with status $scan_rc."
  exit 1
fi

[[ -n "$bundle_id" ]] || { print -u2 "Could not resolve the app bundle identifier."; exit 1; }

print "Mac App Store preflight passed"
print "Bundle identifier: $bundle_id"
print "Version: $version ($build)"
print "Team: $team_id"

if ! security find-identity -v -p codesigning | grep -Eq 'Apple Distribution|3rd Party Mac Developer Application'; then
  print -u2 "Notice: no local Apple Distribution identity is visible. Xcode may use managed cloud signing, otherwise create or download the distribution certificate in Xcode."
fi

[[ "$mode" == "--preflight" ]] && exit 0

[[ "$archive" == *.xcarchive ]] || { print -u2 "Archive path must end in .xcarchive"; exit 64; }
safe_to_replace "$archive" "archive"
safe_to_replace "$export_dir" "export directory"
rm -rf -- "$archive" "$export_dir"

temporary_root="$(mktemp -d "${temporary_base%/}/BeddyButler-AppStore.XXXXXX")"
chmod 700 "$temporary_root"
trap 'rm -rf -- "$temporary_root"' EXIT
export_options="$temporary_root/ExportOptions.plist"

xcodebuild archive   -project "Beddy Butler.xcodeproj"   -scheme "Beddy Butler"   -configuration Release   -destination "generic/platform=macOS"   -archivePath "$archive"   -allowProvisioningUpdates   DEVELOPMENT_TEAM="$team_id"   CODE_SIGN_STYLE=Automatic   MARKETING_VERSION="$version"   CURRENT_PROJECT_VERSION="$build"

python3 Tools/validate_app_bundle.py \
  "$archive/Products/Applications/Beddy Butler.app" \
  --version "$version" \
  --build "$build" \
  --require-universal \
  --require-signed-security

destination="export"
[[ "$mode" == "--upload" ]] && destination="upload"
cat > "$export_options" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store-connect</string>
  <key>destination</key>
  <string>$destination</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>$team_id</string>
  <key>uploadSymbols</key>
  <true/>
  <key>manageAppVersionAndBuildNumber</key>
  <false/>
</dict>
</plist>
PLIST

mkdir -p "$export_dir"
xcodebuild -exportArchive   -archivePath "$archive"   -exportPath "$export_dir"   -exportOptionsPlist "$export_options"   -allowProvisioningUpdates

if [[ "$mode" == "--upload" ]]; then
  print "Uploaded Beddy Butler $version ($build) to App Store Connect."
else
  print "Exported the App Store package to $export_dir"
fi
