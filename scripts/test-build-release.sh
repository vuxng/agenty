#!/bin/bash
# shellcheck disable=SC2016  # run_case checks are single-quoted on purpose: run_case evals them in the case root.
# Tests for scripts/build-release.sh against a fake toolchain (xcodegen, xcodebuild, codesign,
# lipo, ditto, xcrun, spctl). Nothing is built or signed. Needs macOS (plutil, shasum).
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/build-release.sh"
IDENTITY="Developer ID Application: Test (TEAM123456)"
passed=0
failed=0

# make_stubs <dir> writes the fake tools into <dir>/bin; calls are logged in <dir>/log.
make_stubs() {
  local root="$1" bin="$1/bin"
  mkdir -p "$bin" "$root/log"
  cat > "$bin/xcodegen" <<'EOF'
#!/bin/bash
touch "$FAKE_LOG/xcodegen.called"
EOF
  cat > "$bin/xcodebuild" <<'EOF'
#!/bin/bash
echo "$*" > "$FAKE_LOG/xcodebuild.args"
app=build/DerivedData/Build/Products/Release/Agenty.app
mkdir -p "$app/Contents/MacOS"
touch "$app/Contents/MacOS/Agenty"
sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
mkdir -p "$sparkle/XPCServices/Installer.xpc" "$sparkle/XPCServices/Downloader.xpc" "$sparkle/Updater.app"
touch "$sparkle/Autoupdate"
echo "** BUILD SUCCEEDED **"
EOF
  # Logs every call. -dvv leaves out Timestamp= for paths containing $FAKE_NO_TIMESTAMP.
  cat > "$bin/codesign" <<'EOF'
#!/bin/bash
echo "$*" >> "$FAKE_LOG/codesign"
path="${*: -1}"
for arg in "$@"; do
  if [ "$arg" = "-dvv" ]; then
    printf 'Authority=Developer ID Application: Test (%s)\nTeamIdentifier=%s\nCodeDirectory v=20500 flags=0x10000(runtime)\n' "$TEAM_ID" "$TEAM_ID" >&2
    if [ -z "${FAKE_NO_TIMESTAMP:-}" ] || [[ "$path" != *"$FAKE_NO_TIMESTAMP"* ]]; then
      echo "Timestamp=Nov 4, 2026" >&2
    fi
  fi
done
EOF
  cat > "$bin/lipo" <<'EOF'
#!/bin/bash
echo arm64
EOF
  cat > "$bin/ditto" <<'EOF'
#!/bin/bash
: > "${*: -1}"
EOF
  cat > "$bin/xcrun" <<'EOF'
#!/bin/bash
case "$1 $2" in
  "notarytool submit")
    echo "$*" > "$FAKE_LOG/notarytool-submit.args"
    printf '{"id":"sub-1","status":"%s","message":"fake"}\n' "${FAKE_NOTARY_STATUS:-Accepted}" ;;
  "notarytool log") touch "$FAKE_LOG/notarytool-log.called"; echo "fake notary log" ;;
  "stapler staple"|"stapler validate") echo "The $2 action worked!" ;;
  *) echo "unexpected xcrun $*" >&2; exit 1 ;;
esac
EOF
  cat > "$bin/spctl" <<'EOF'
#!/bin/bash
printf 'Agenty.app: accepted\nsource=Notarized Developer ID\n' >&2
EOF
  chmod +x "$bin"/*
}

# run_case <name> <expected exit> <expected output substring> <check> [VAR=value ...]
# <check> is a shell condition evaluated in the case root after the run ("" for none).
run_case() {
  local name="$1" want_exit="$2" want_text="$3" check="$4"
  shift 4
  local root code=0 output
  root="$(mktemp -d)"
  mkdir -p "$root/scripts"
  cp "$SCRIPT" "$root/scripts/build-release.sh"
  make_stubs "$root"
  : > "$root/empty.p8"
  printf 'key' > "$root/key.p8"
  output="$(cd "$root" && env -i HOME="$HOME" PATH="$root/bin:/usr/bin:/bin:/usr/sbin" \
    FAKE_LOG="$root/log" BUILD_NUMBER=7 "$@" bash scripts/build-release.sh 0.1.0 2>&1)" || code=$?
  local ok=1
  [ "$code" = "$want_exit" ] || ok=0
  if [ -n "$want_text" ] && [[ "$output" != *"$want_text"* ]]; then ok=0; fi
  if [ -n "$check" ] && ! (cd "$root" && eval "$check"); then ok=0; fi
  if [ "$ok" = 1 ]; then
    passed=$((passed + 1)); echo "ok   $name"
  else
    failed=$((failed + 1)); echo "FAIL $name (exit $code)"; printf '%s\n' "$output" | sed 's/^/     | /' | tail -8
  fi
  rm -rf "$root"
}

run_case adhoc_build_says_ad_hoc 0 "notice: skipping notarization (ad-hoc build)" \
  '[ -f build/Agenty-0.1.0-arm64.zip ] && grep -q "Agenty-0.1.0-arm64.zip$" build/Agenty-0.1.0-arm64.zip.sha256'
run_case devid_without_credentials_says_no_credentials 0 "notice: skipping notarization (no credentials)" "" \
  SIGN_IDENTITY="$IDENTITY" TEAM_ID=TEAM123456
run_case missing_team_id_fails 1 "TEAM_ID is required" "" \
  SIGN_IDENTITY="$IDENTITY"
run_case required_notarization_without_credentials_fails_before_build 1 "notarization is required" \
  '[ ! -e log/xcodegen.called ]' \
  REQUIRE_NOTARIZATION=1 SIGN_IDENTITY="$IDENTITY" TEAM_ID=TEAM123456
run_case required_notarization_without_identity_fails 1 "SIGN_IDENTITY" '[ ! -e log/xcodegen.called ]' \
  REQUIRE_NOTARIZATION=1 NOTARY_KEYCHAIN_PROFILE=p
run_case required_notarization_with_empty_key_fails 1 "missing or empty" '[ ! -e log/xcodegen.called ]' \
  REQUIRE_NOTARIZATION=1 SIGN_IDENTITY="$IDENTITY" TEAM_ID=TEAM123456 \
  NOTARY_KEY_PATH=empty.p8 NOTARY_KEY_ID=ABC NOTARY_ISSUER_ID=x
run_case notarization_accepted_uses_timeout 0 "Notarization status: Accepted" \
  'grep -q -- "--timeout" log/notarytool-submit.args' \
  REQUIRE_NOTARIZATION=1 SIGN_IDENTITY="$IDENTITY" TEAM_ID=TEAM123456 NOTARY_KEYCHAIN_PROFILE=p
run_case notarization_rejected_fails_with_log 1 "notarization failed with status: Invalid" \
  '[ -e log/notarytool-log.called ]' \
  SIGN_IDENTITY="$IDENTITY" TEAM_ID=TEAM123456 NOTARY_KEY_PATH=key.p8 NOTARY_KEY_ID=ABC NOTARY_ISSUER_ID=x \
  FAKE_NOTARY_STATUS=Invalid

# Signing calls (codesign -f -s ...), for the checks below.
signs() { grep -e '-f -s ' log/codesign || true; }
signed_names() { signs | awk '{print $NF}' | sed 's|.*/||' | paste -sd ' ' -; }
DEVID=(SIGN_IDENTITY="$IDENTITY" TEAM_ID=TEAM123456)

run_case devid_signs_sparkle_inside_out 0 "" \
  '[ "$(signed_names)" = "Installer.xpc Downloader.xpc Autoupdate Updater.app Sparkle.framework Agenty.app" ]' \
  "${DEVID[@]}"
run_case devid_signing_never_uses_deep 0 "" \
  '[ -n "$(signs)" ] && [ -z "$(signs | grep -e --deep)" ]' "${DEVID[@]}"
run_case devid_signing_uses_runtime_and_timestamp 0 "" \
  '[ -n "$(signs)" ] && [ -z "$(signs | grep -v -e "-o runtime")" ] && [ -z "$(signs | grep -v -e --timestamp)" ]' \
  "${DEVID[@]}"
run_case devid_signing_uses_keychain_when_set 0 "" \
  '[ -n "$(signs)" ] && [ -z "$(signs | grep -v -e "--keychain k.keychain-db")" ]' \
  "${DEVID[@]}" SIGN_KEYCHAIN=k.keychain-db
run_case downloader_keeps_its_entitlements 0 "" \
  '[[ "$(signs | grep -e "Downloader.xpc$")" == *"--preserve-metadata=entitlements"* ]]' "${DEVID[@]}"
run_case helper_without_timestamp_fails_before_notarizing 1 "Autoupdate is missing: Timestamp=" \
  '[ ! -e log/notarytool-submit.args ]' \
  "${DEVID[@]}" NOTARY_KEYCHAIN_PROFILE=p FAKE_NO_TIMESTAMP=Autoupdate
run_case adhoc_does_not_sign_helpers_one_by_one 0 "" \
  '[ -s log/codesign ] && [ -z "$(signs | grep -e Installer.xpc)" ]'

echo "$passed passed, $failed failed"
[ "$failed" = 0 ]
