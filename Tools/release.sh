#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
cd "$root"

version="${1:-}"
build="${2:-}"
mode="${3:-notarized}"
notary_profile="${BEDDY_NOTARY_PROFILE:-beddy-butler-notary}"
temporary_base="${TMPDIR:-/tmp}"
archive="${temporary_base}/BeddyButler-${version:-release}-${build:-build}.xcarchive"
exported="${temporary_base}/BeddyButler-${version:-release}-${build:-build}-export"

if [[ -z "$version" || -z "$build" ]]; then
  print -u2 "Usage: Tools/release.sh <marketing-version> <build-number> [--local]"
  exit 64
fi

if [[ "$mode" != "notarized" && "$mode" != "--local" ]]; then
  print -u2 "The optional third argument must be --local."
  exit 64
fi

if [[ ! "$version" =~ '^[0-9]+([.][0-9]+){1,2}$' ]]; then
  print -u2 "The marketing version must contain two or three numeric components."
  exit 64
fi

if [[ ! "$build" =~ '^[1-9][0-9]*$' ]]; then
  print -u2 "The build number must be a positive integer."
  exit 64
fi

temporary_root="${temporary_base:A}"
if [[ "$temporary_root" == "/" || "$temporary_root" == "${HOME:A}" || "$temporary_root" == "${root:A}" ]]; then
  print -u2 "Unsafe temporary directory: $temporary_base"
  exit 64
fi
[[ "${archive:A}" == "$temporary_root"/* && "${exported:A}" == "$temporary_root"/* ]] || {
  print -u2 "Release paths must remain inside $temporary_base"
  exit 64
}
[[ ! -L "$archive" && ! -L "$exported" ]] || {
  print -u2 "Refusing to replace a symlinked release path."
  exit 64
}

zsh Tools/validate_release_source.sh

if ! security find-identity -v -p codesigning | grep -q 'Developer ID Application'; then
  print -u2 "A Developer ID Application identity is required in the macOS Keychain."
  exit 1
fi

if [[ "$mode" == "notarized" ]] && ! xcrun notarytool history --keychain-profile "$notary_profile" >/dev/null 2>&1; then
  print -u2 "The notarization profile '$notary_profile' is unavailable or invalid."
  print -u2 "Store it with: xcrun notarytool store-credentials $notary_profile"
  print -u2 "For a signed local beta without notarization, append --local."
  exit 1
fi

rm -rf -- "$archive" "$exported"
xcodebuild archive \
  -project "Beddy Butler.xcodeproj" \
  -scheme "Beddy Butler" \
  -configuration Release \
  -archivePath "$archive" \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  CODE_SIGN_STYLE=Manual \
  PROVISIONING_PROFILE_SPECIFIER='' \
  MARKETING_VERSION="$version" \
  CURRENT_PROJECT_VERSION="$build"

mkdir -p "$exported"
app="$archive/Products/Applications/Beddy Butler.app"
zip="$exported/Beddy-Butler-${version}-${build}.zip"
notary_zip="$exported/notary-app.zip"
dmg_staging="$exported/dmg-root"
dmg="$exported/Beddy-Butler-${version}-${build}.dmg"

codesign --verify --deep --strict --verbose=2 "$app"

if [[ "$mode" == "notarized" ]]; then
  ditto -c -k --keepParent "$app" "$notary_zip"
  xcrun notarytool submit "$notary_zip" \
    --keychain-profile "$notary_profile" \
    --wait
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  spctl --assess --type exec --verbose=4 "$app"
  rm -f "$notary_zip"
fi

rm -rf -- "$dmg_staging"
mkdir -p "$dmg_staging"
ditto "$app" "$dmg_staging/Beddy Butler.app"
ln -s /Applications "$dmg_staging/Applications"
hdiutil create \
  -volname "Beddy Butler $version" \
  -srcfolder "$dmg_staging" \
  -ov \
  -format UDZO \
  "$dmg"
codesign --force --sign "Developer ID Application" --timestamp "$dmg"

if [[ "$mode" == "notarized" ]]; then
  xcrun notarytool submit "$dmg" \
    --keychain-profile "$notary_profile" \
    --wait
  xcrun stapler staple "$dmg"
  xcrun stapler validate "$dmg"
  spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg"
else
  print -u2 "Local beta mode: the app and disk image are signed but not notarized."
fi

ditto -c -k --keepParent "$app" "$zip"

(
  cd "$exported"
  shasum -a 256 "${zip:t}" "${dmg:t}" > SHA256SUMS
)

rm -rf -- "$dmg_staging"

if [[ "$mode" == "notarized" ]]; then
  print "Notarized artifacts: $zip and $dmg"
else
  print "Signed local beta artifacts: $zip and $dmg"
fi
print "Checksums: $exported/SHA256SUMS"
