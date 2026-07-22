#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
cd "$root"

mode="${1:---preflight}"
version="${2:-2.0}"
build="${3:-609}"
team_id="${BEDDY_APPLE_TEAM_ID:-BBYYCBH7EW}"
archive="${BEDDY_ARCHIVE_PATH:-${TMPDIR:-/tmp}/BeddyButler-${version}-${build}.xcarchive}"
export_dir="${BEDDY_EXPORT_PATH:-${TMPDIR:-/tmp}/BeddyButler-AppStore-${version}-${build}}"
export_options="${TMPDIR:-/tmp}/BeddyButler-AppStore-ExportOptions.plist"

case "$mode" in
  --preflight|--export|--upload) ;;
  *)
    print -u2 "Usage: Tools/app_store_release.sh [--preflight|--export|--upload] [version] [build]"
    exit 64
    ;;
esac

if [[ ! "$version" =~ '^[0-9]+([.][0-9]+){1,2}$' ]]; then
  print -u2 "The marketing version must contain two or three numeric components."
  exit 64
fi
if [[ ! "$build" =~ '^[1-9][0-9]*$' ]]; then
  print -u2 "The build number must be a positive integer."
  exit 64
fi

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

if rg -q 'Check for Updates|releases/latest' "Beddy Butler" README.md PRIVACY.md; then
  print -u2 "A non-App-Store update path remains in the product surface."
  exit 1
fi

bundle_id="$(
  xcodebuild -project "Beddy Butler.xcodeproj" -scheme "Beddy Butler"     -configuration Release -showBuildSettings 2>/dev/null |
    awk -F ' = ' '/^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER = / {print $2; exit}'
)"
[[ -n "$bundle_id" ]] || { print -u2 "Could not resolve the app bundle identifier."; exit 1; }

print "Mac App Store preflight passed"
print "Bundle identifier: $bundle_id"
print "Version: $version ($build)"
print "Team: $team_id"

if ! security find-identity -v -p codesigning | grep -Eq 'Apple Distribution|3rd Party Mac Developer Application'; then
  print -u2 "Notice: no local Apple Distribution identity is visible. Xcode may use managed cloud signing, otherwise create or download the distribution certificate in Xcode."
fi

[[ "$mode" == "--preflight" ]] && exit 0

rm -rf "$archive" "$export_dir"
xcodebuild archive   -project "Beddy Butler.xcodeproj"   -scheme "Beddy Butler"   -configuration Release   -destination "generic/platform=macOS"   -archivePath "$archive"   -allowProvisioningUpdates   DEVELOPMENT_TEAM="$team_id"   CODE_SIGN_STYLE=Automatic   MARKETING_VERSION="$version"   CURRENT_PROJECT_VERSION="$build"

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
