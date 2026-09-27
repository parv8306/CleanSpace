#!/usr/bin/env bash
# Archives CleanSpace and uploads it to App Store Connect for TestFlight.
#
# Needs: a Mac with Xcode 16+, a paid Apple Developer Program team, and an app record in
# App Store Connect whose bundle ID matches CLEANSPACE_BASE_BUNDLE_ID. See TESTFLIGHT.md.
#
#   TEAM_ID=ABCDE12345 ./scripts/testflight.sh
#
# Optional:
#   BUNDLE_ID=com.you.cleanspace   overrides CLEANSPACE_BASE_BUNDLE_ID for this build
#   BUILD_NUMBER=42              defaults to a date-based number that always increases
#   ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH
#                                App Store Connect API key, for signing and uploading without
#                                an Xcode login (used by CI). Without it, the Apple ID signed
#                                into Xcode › Settings › Accounts is used.
set -euo pipefail

cd "$(dirname "$0")/.."

: "${TEAM_ID:?Set TEAM_ID to your 10-character Apple Developer Team ID}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d).$(date +%H%M)}"
BUILD_DIR="build"
ARCHIVE="$BUILD_DIR/CleanSpace.xcarchive"

AUTH_ARGS=()
if [[ -n "${ASC_KEY_ID:-}" ]]; then
  : "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID with ASC_KEY_ID}"
  : "${ASC_KEY_PATH:?Set ASC_KEY_PATH to the .p8 file with ASC_KEY_ID}"
  AUTH_ARGS=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi

SETTINGS=(DEVELOPMENT_TEAM="$TEAM_ID" CURRENT_PROJECT_VERSION="$BUILD_NUMBER")
if [[ -n "${BUNDLE_ID:-}" ]]; then
  SETTINGS+=(CLEANSPACE_BASE_BUNDLE_ID="$BUNDLE_ID")
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "Archiving build $BUILD_NUMBER"
xcodebuild \
  -project CleanSpace.xcodeproj \
  -scheme CleanSpace \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"} \
  "${SETTINGS[@]}" \
  archive

cp ExportOptions.plist "$BUILD_DIR/ExportOptions.plist"
/usr/libexec/PlistBuddy -c "Add :teamID string $TEAM_ID" "$BUILD_DIR/ExportOptions.plist"

echo "Uploading to App Store Connect"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
  -exportPath "$BUILD_DIR/export" \
  -allowProvisioningUpdates \
  ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"}

echo "Uploaded build $BUILD_NUMBER. It appears in App Store Connect › TestFlight after processing (usually 5 to 30 minutes)."
