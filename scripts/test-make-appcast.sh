#!/bin/bash
# shellcheck disable=SC2016  # run_case checks are single-quoted on purpose: run_case evals them in the case root.
# Tests for scripts/make-appcast.sh. The fake sign_update signs for real (Ed25519 through CryptoKit,
# with throwaway key pairs made per run), so the script's check against SUPublicEDKey sees real
# signatures. Needs macOS (ditto, plutil, xmllint, swift).
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
passed=0
failed=0

# Test-only Ed25519 tool: `keygen` prints "<seed-b64> <public-b64>"; `sign <file>` reads a seed
# (base64, the format generate_keys -x exports) from stdin and prints the signature.
cat > "$WORK/ed25519.swift" <<'EOF'
import CryptoKit
import Foundation

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "keygen":
    let key = Curve25519.Signing.PrivateKey()
    print(key.rawRepresentation.base64EncodedString(), key.publicKey.rawRepresentation.base64EncodedString())
case "sign":
    let input = FileHandle.standardInput.readDataToEndOfFile()
    let seed = String(decoding: input, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    let key = try! Curve25519.Signing.PrivateKey(rawRepresentation: Data(base64Encoded: seed)!)
    let data = try! Data(contentsOf: URL(fileURLWithPath: args[2]))
    print(try! key.signature(for: data).base64EncodedString())
default:
    exit(2)
}
EOF
swiftc -O -o "$WORK/ed25519" "$WORK/ed25519.swift"
read -r SEED PUB < <("$WORK/ed25519" keygen)
read -r OTHER_SEED _ < <("$WORK/ed25519" keygen)

NOTES=$'## What\'s Changed\n* Check for updates with Sparkle by @vuxng in #9'
TRICKY_NOTES='a ]]> b & <c>'
# shellcheck disable=SC2034  # used by the eval'd check in writes_one_signed_item
URL_020="https://github.com/vuxng/agenty/releases/download/v0.2.0/Agenty-0.2.0-arm64.zip"

# make_root <root> <zip version> <app version> <notes>: a repo root with the script, a release zip
# whose app has CFBundleVersion 45 and SUPublicEDKey=$PUB, the notes, and the fake sign_update.
make_root() {
  local root="$1" zip_version="$2" app_version="$3" notes="$4"
  mkdir -p "$root/scripts" "$root/build" "$root/bin" "$root/log" "$root/stage/Agenty.app/Contents"
  cp "$DIR/make-appcast.sh" "$DIR/verify-ed-signature.swift" "$root/scripts/"
  local plist="$root/stage/Agenty.app/Contents/Info.plist"
  plutil -create xml1 "$plist"
  plutil -insert CFBundleShortVersionString -string "$app_version" "$plist"
  plutil -insert CFBundleVersion -string 45 "$plist"
  plutil -insert LSMinimumSystemVersion -string 27.0 "$plist"
  plutil -insert SUPublicEDKey -string "$PUB" "$plist"
  (cd "$root/stage" && ditto -c -k --keepParent Agenty.app "$root/build/Agenty-$zip_version-arm64.zip")
  printf '%s' "$notes" > "$root/build/notes.md"
  cat > "$root/bin/sign_update" <<'EOF'
#!/bin/bash
echo "$*" >> "$FAKE_LOG/sign_update.args"
if [ "$1 $2" != "--ed-key-file -" ]; then
  echo "fake sign_update: expected --ed-key-file -" >&2
  exit 2
fi
file="${*: -1}"
signature="$("$ED25519" sign "$file")"
printf 'sparkle:edSignature="%s" length="%s"\n' "$signature" "$(stat -f %z "$file")"
EOF
  chmod +x "$root/bin/sign_update"
}

# run_case <name> <expected exit> <expected output substring> <check> <key on stdin> <version>
#          [zip version] [app version] [notes] [prepare: shell run in the case root first]
run_case() {
  local name="$1" want_exit="$2" want_text="$3" check="$4" key="$5" version="$6"
  local zip_version="${7:-0.2.0}" app_version="${8:-0.2.0}" notes="${9:-$NOTES}" prepare="${10:-}"
  local root code=0 output
  root="$(mktemp -d "$WORK/case.XXXXXX")"
  make_root "$root" "$zip_version" "$app_version" "$notes"
  if [ -n "$prepare" ]; then (cd "$root" && eval "$prepare"); fi
  output="$(cd "$root" && printf '%s' "$key" | env -i HOME="$HOME" PATH="$root/bin:/usr/bin:/bin:/usr/sbin" \
    FAKE_LOG="$root/log" ED25519="$WORK/ed25519" SPARKLE_BIN="$root/bin" \
    bash scripts/make-appcast.sh "$version" 2>&1)" || code=$?
  local ok=1
  [ "$code" = "$want_exit" ] || ok=0
  if [ -n "$want_text" ] && [[ "$output" != *"$want_text"* ]]; then ok=0; fi
  if [ -n "$check" ] && ! (cd "$root" && eval "$check"); then ok=0; fi
  if [ "$ok" = 1 ]; then
    passed=$((passed + 1)); echo "ok   $name"
  else
    failed=$((failed + 1)); echo "FAIL $name (exit $code)"; printf '%s\n' "$output" | sed 's/^/     | /' | tail -8
  fi
}

# xp <xpath>: string value from build/appcast.xml (sparkle:* names are matched by local name).
xp() { xmllint --xpath "string($1)" build/appcast.xml; }

run_case writes_one_signed_item 0 "" '
  [ "$(xp "count(//item)")" = 1 ] &&
  [ "$(xp "//item/*[local-name()=\"version\"]")" = 45 ] &&
  [ "$(xp "//item/*[local-name()=\"shortVersionString\"]")" = 0.2.0 ] &&
  [ "$(xp "//item/*[local-name()=\"minimumSystemVersion\"]")" = 27.0 ] &&
  [ "$(xp "//item/enclosure/@url")" = "$URL_020" ] &&
  [ "$(xp "//item/enclosure/@length")" = "$(stat -f %z build/Agenty-0.2.0-arm64.zip)" ] &&
  [ "$(xp "//item/description/@*[local-name()=\"format\"]")" = markdown ] &&
  [ "$(xp "//item/description")" = "$NOTES" ] &&
  swift scripts/verify-ed-signature.swift build/Agenty-0.2.0-arm64.zip \
    "$(xp "//item/enclosure/@*[local-name()=\"edSignature\"]")" "$PUB"' \
  "$SEED" 0.2.0
run_case notes_with_cdata_end_stay_valid 0 "" \
  'xmllint --noout build/appcast.xml && [ "$(xp "//item/description")" = "$TRICKY_NOTES" ]' \
  "$SEED" 0.2.0 0.2.0 0.2.0 "$TRICKY_NOTES"
run_case missing_key_fails 1 "Sparkle private key is missing" '[ ! -e build/appcast.xml ]' "" 0.2.0
run_case mismatched_key_fails 1 "the Sparkle key does not match SUPublicEDKey" '[ ! -e build/appcast.xml ]' \
  "$OTHER_SEED" 0.2.0
run_case version_mismatch_fails 1 "holds version 0.2.0, not 0.2.1" '[ ! -e build/appcast.xml ]' \
  "$SEED" 0.2.1 0.2.1 0.2.0
run_case key_never_in_arguments 0 "" '[ -s log/sign_update.args ] && ! grep -F -- "$SEED" log/sign_update.args' \
  "$SEED" 0.2.0

# A broken verifier must not be reported as a key mismatch: that message invites a key rotation.
run_case verifier_that_does_not_compile_is_not_a_key_mismatch 1 "could not compile scripts/verify-ed-signature.swift" \
  '[ ! -e build/appcast.xml ]' "$SEED" 0.2.0 0.2.0 0.2.0 "$NOTES" \
  'echo "this is not Swift" > scripts/verify-ed-signature.swift'

echo "$passed passed, $failed failed"
[ "$failed" = 0 ]
