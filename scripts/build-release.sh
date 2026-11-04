#!/bin/bash
# Build an arm64-only Release zip: scripts/build-release.sh <version>
#
# Signing (optional):
#   SIGN_IDENTITY   Developer ID identity, e.g. "Developer ID Application: Vu Nguyen (8WJ6LC5Z59)".
#                   Unset: ad-hoc signing.
#   TEAM_ID         Required with SIGN_IDENTITY.
#   SIGN_KEYCHAIN   Keychain that holds the identity (CI).
# Notarization (optional, needs SIGN_IDENTITY):
#   NOTARY_KEYCHAIN_PROFILE                              notarytool store-credentials profile (local), or
#   NOTARY_KEY_PATH + NOTARY_KEY_ID + NOTARY_ISSUER_ID   App Store Connect API key (CI).
# REQUIRE_NOTARIZATION=1   Fail before building unless signing and notary credentials are set (CI).
# BUILD_NUMBER      CFBundleVersion; defaults to the commit count of HEAD.
#
# Output: build/Agenty-<version>-arm64.zip and build/Agenty-<version>-arm64.zip.sha256
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <version>   (e.g. $0 0.1.0)" >&2
  exit 1
fi

VERSION="$1"
cd "$(dirname "$0")/.."

SIGN_IDENTITY="${SIGN_IDENTITY:-}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD)}"
APP="build/DerivedData/Build/Products/Release/Agenty.app"
ZIP_NAME="Agenty-$VERSION-arm64.zip"
ZIP="build/$ZIP_NAME"

sign_settings=()
if [ -n "$SIGN_IDENTITY" ]; then
  if [ -z "${TEAM_ID:-}" ]; then
    echo "error: TEAM_ID is required when SIGN_IDENTITY is set." >&2
    exit 1
  fi
  sign_flags="--timestamp"
  if [ -n "${SIGN_KEYCHAIN:-}" ]; then
    sign_flags="$sign_flags --keychain $SIGN_KEYCHAIN"
  fi
  sign_settings=(
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY"
    DEVELOPMENT_TEAM="$TEAM_ID"
    OTHER_CODE_SIGN_FLAGS="$sign_flags"
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
  )
fi

notary_auth=()
if [ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]; then
  notary_auth=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
elif [ -n "${NOTARY_KEY_PATH:-}" ] && [ -n "${NOTARY_KEY_ID:-}" ] && [ -n "${NOTARY_ISSUER_ID:-}" ]; then
  notary_auth=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
fi

if [ "${REQUIRE_NOTARIZATION:-}" = "1" ]; then
  if [ -z "$SIGN_IDENTITY" ]; then
    echo "error: notarization is required but SIGN_IDENTITY is not set." >&2
    exit 1
  fi
  if [ "${#notary_auth[@]}" -eq 0 ]; then
    echo "error: notarization is required but notary credentials are missing" \
      "(NOTARY_KEYCHAIN_PROFILE, or NOTARY_KEY_PATH + NOTARY_KEY_ID + NOTARY_ISSUER_ID)." >&2
    exit 1
  fi
  if [ -z "${NOTARY_KEYCHAIN_PROFILE:-}" ] && [ ! -s "$NOTARY_KEY_PATH" ]; then
    echo "error: notarization is required but the API key file $NOTARY_KEY_PATH is missing or empty." >&2
    exit 1
  fi
fi

make_zip() {
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
}

# Sparkle ships its helpers ad-hoc signed, and Xcode re-signs only the framework itself, so
# a Developer ID build signs them one by one from the inside out (never --deep), then re-seals
# the app. https://sparkle-project.org/documentation/sandboxing/#code-signing
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
signed_components=(
  "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
  "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
  "$SPARKLE/Versions/B/Autoupdate"
  "$SPARKLE/Versions/B/Updater.app"
  "$SPARKLE"
  "$APP"
)

developer_id_sign() {
  local path="$1"
  local args=(-f -s "$SIGN_IDENTITY" -o runtime --timestamp)
  if [ -n "${SIGN_KEYCHAIN:-}" ]; then
    args+=(--keychain "$SIGN_KEYCHAIN")
  fi
  case "$path" in
    */Downloader.xpc | "$APP") args+=(--preserve-metadata=entitlements) ;;
  esac
  codesign "${args[@]}" "$path"
}

xcodegen generate

xcodebuild -project Agenty.xcodeproj -scheme Agenty -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  ${sign_settings[@]+"${sign_settings[@]}"} build

if [ -n "$SIGN_IDENTITY" ]; then
  for component in "${signed_components[@]}"; do
    developer_id_sign "$component"
  done
  for component in "${signed_components[@]}"; do
    details="$(codesign -dvv "$component" 2>&1)"
    for expected in "Authority=Developer ID Application" "TeamIdentifier=$TEAM_ID" "(runtime)" "Timestamp="; do
      if [[ "$details" != *"$expected"* ]]; then
        echo "error: codesign -dvv output for $component is missing: $expected" >&2
        exit 1
      fi
    done
  done
  codesign --verify --strict --deep "$APP"
else
  codesign --force --deep --options runtime --sign - "$APP"
  codesign --verify --strict "$APP"
fi

ARCHS="$(lipo -archs "$APP/Contents/MacOS/Agenty")"
if [ "$ARCHS" != "arm64" ]; then
  echo "error: expected arm64 only, got: $ARCHS" >&2
  exit 1
fi

make_zip

if [ -n "$SIGN_IDENTITY" ] && [ "${#notary_auth[@]}" -gt 0 ]; then
  xcrun notarytool submit "$ZIP" --wait --timeout 1h --output-format json "${notary_auth[@]}" > build/notary.json || true
  status="$(plutil -extract status raw -o - build/notary.json 2>/dev/null || echo unknown)"
  submission_id="$(plutil -extract id raw -o - build/notary.json 2>/dev/null || true)"
  echo "Notarization status: $status (submission $submission_id)"
  if [ "$status" != "Accepted" ]; then
    if [ -n "$submission_id" ]; then
      xcrun notarytool log "$submission_id" "${notary_auth[@]}" || true
    else
      cat build/notary.json >&2 || true
    fi
    echo "error: notarization failed with status: $status" >&2
    exit 1
  fi
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  make_zip
  assessment="$(spctl --assess --type execute -vv "$APP" 2>&1 || true)"
  echo "$assessment"
  if [[ "$assessment" != *"source=Notarized Developer ID"* ]]; then
    echo "error: Gatekeeper does not report a notarized Developer ID app." >&2
    exit 1
  fi
elif [ -z "$SIGN_IDENTITY" ]; then
  echo "notice: skipping notarization (ad-hoc build)"
else
  echo "notice: skipping notarization (no credentials)"
fi

(cd build && shasum -a 256 "$ZIP_NAME" > "$ZIP_NAME.sha256")
echo "Created $ZIP"
