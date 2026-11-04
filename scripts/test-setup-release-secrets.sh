#!/bin/bash
# Tests for the helpers in scripts/setup-release-secrets.sh. The wizard itself is
# never run: everything but its last line (run_wizard "$@") is sourced, and gh is faked.
set -euo pipefail

WIZARD="$(cd "$(dirname "$0")" && pwd)/setup-release-secrets.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
passed=0
failed=0

check() {
  local name="$1"
  shift
  if "$@"; then
    passed=$((passed + 1)); echo "ok   $name"
  else
    failed=$((failed + 1)); echo "FAIL $name"
  fi
}

sed '$d' "$WIZARD" > "$WORK/wizard-lib.sh"
export ENV_FILE=/dev/null  # as in run_wizard: ask never offers a saved value
# shellcheck source=/dev/null
source "$WORK/wizard-lib.sh"
set +e

# The section the author writes (below the STAGES marker), for static checks.
authored="$(sed -n '/^# STAGES:/,$p' "$WIZARD")"

# make_p12 <name> <team in the certificate subject> [-nokeys]: a throwaway self-signed
# certificate exported with password "pw".
make_p12() {
  local name="$1" team="$2" nokeys="${3:-}"
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
    -keyout "$WORK/$name.key" -out "$WORK/$name.crt" \
    -subj "/CN=Developer ID Application: Test ($team)/OU=$team" >/dev/null 2>&1
  if [ "$nokeys" = "-nokeys" ]; then
    /usr/bin/openssl pkcs12 -export -nokeys -in "$WORK/$name.crt" -out "$WORK/$name.p12" -passout pass:pw
  else
    /usr/bin/openssl pkcs12 -export -inkey "$WORK/$name.key" -in "$WORK/$name.crt" -out "$WORK/$name.p12" -passout pass:pw
  fi
}
# shellcheck disable=SC2153  # TEAM is set by the sourced wizard
wizard_team="$TEAM"
make_p12 good "$wizard_team"
make_p12 other OTHERTEAM1
make_p12 certonly "$wizard_team" -nokeys

check p12_ok_accepts_team_cert_with_key bash -c "P12_PASSWORD=pw; source '$WORK/wizard-lib.sh'; p12_ok '$WORK/good.p12'"
check p12_ok_rejects_wrong_password bash -c "P12_PASSWORD=nope; source '$WORK/wizard-lib.sh'; ! p12_ok '$WORK/good.p12'"
check p12_ok_rejects_other_team bash -c "P12_PASSWORD=pw; source '$WORK/wizard-lib.sh'; ! p12_ok '$WORK/other.p12'"
check p12_ok_rejects_cert_without_key bash -c "P12_PASSWORD=pw; source '$WORK/wizard-lib.sh'; ! p12_ok '$WORK/certonly.p12'"

ask_default_enter_takes_default() { local v; ask_default v "Key ID:" "ABC" <<< "" && [ "$v" = "ABC" ]; }
ask_default_keeps_typed_value() { local v; ask_default v "Key ID:" "ABC" <<< "XYZ" && [ "$v" = "XYZ" ]; }
check ask_default_enter_takes_default ask_default_enter_takes_default
check ask_default_keeps_typed_value ask_default_keeps_typed_value

# Fake gh: exits with $FAKE_GH_EXIT and stores the secret it read from stdin.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'EOF'
#!/bin/bash
cat > "$FAKE_GH_STDIN"
exit "${FAKE_GH_EXIT:-0}"
EOF
chmod +x "$WORK/bin/gh"
upload_records_written() {
  WRITTEN_SECRET=(); SKIPPED=()
  PATH="$WORK/bin:$PATH" FAKE_GH_STDIN="$WORK/stdin" FAKE_GH_EXIT=0 \
    set_env_secret NOTARY_KEY_ID < <(printf 'KEY') >/dev/null
  [ "${WRITTEN_SECRET[*]}" = "NOTARY_KEY_ID" ] && [ "${#SKIPPED[@]}" = 0 ] && [ "$(cat "$WORK/stdin")" = "KEY" ]
}
upload_failure_records_skipped() {
  WRITTEN_SECRET=(); SKIPPED=()
  PATH="$WORK/bin:$PATH" FAKE_GH_STDIN="$WORK/stdin" FAKE_GH_EXIT=1 \
    set_env_secret NOTARY_KEY_ID < <(printf 'KEY') >/dev/null
  [ "${#WRITTEN_SECRET[@]}" = 0 ] && [[ "${SKIPPED[*]}" == *"NOTARY_KEY_ID"* ]]
}
check upload_records_written upload_records_written
check upload_failure_records_skipped upload_failure_records_skipped

# Under pipefail, `cmd | grep -q` can fail after a match: grep exits early and cmd
# dies of SIGPIPE. The stages capture output first instead.
no_piped_grep_q() { ! grep -nE '\|[[:space:]]*grep -[a-zA-Z]*q' <<< "$authored"; }
check no_piped_grep_q_in_stages no_piped_grep_q
# Readline needs colour codes in a prompt wrapped in \001..\002, which the library's
# ask does. The stages must not call read -p with their own prompt.
no_raw_read_prompt() { ! grep -nE '\bread\b.*-p' <<< "$authored"; }
check no_raw_read_prompt_in_stages no_raw_read_prompt

echo "$passed passed, $failed failed"
[ "$failed" = 0 ]
