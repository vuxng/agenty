#!/bin/bash
# Tests for scripts/publish-release.sh with a fake gh. No release is touched.
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/publish-release.sh"
passed=0
failed=0

# run_case <name> <expected exit> <check> [VAR=value ...]
# The fake gh logs one line per call to log/gh. FAKE_CREATE_EXIT sets the exit of
# `gh release create`; FAKE_VIEW_OUT/FAKE_VIEW_EXIT set what `gh release view` prints/returns.
# <check> is a shell condition evaluated in the case root after the run.
run_case() {
  local name="$1" want_exit="$2" check="$3"
  shift 3
  local root code=0 output
  root="$(mktemp -d)"
  mkdir -p "$root/scripts" "$root/bin" "$root/log" "$root/build"
  cp "$SCRIPT" "$root/scripts/publish-release.sh"
  : > "$root/build/Agenty-0.2.0-arm64.zip"
  : > "$root/build/Agenty-0.2.0-arm64.zip.sha256"
  cat > "$root/bin/gh" <<'EOF'
#!/bin/bash
echo "$*" >> "$FAKE_LOG/gh"
case "$1 $2" in
  "release create") exit "${FAKE_CREATE_EXIT:-0}" ;;
  "release view") printf '%s\n' "${FAKE_VIEW_OUT:-}"; exit "${FAKE_VIEW_EXIT:-0}" ;;
  "release delete") exit 0 ;;
  *) echo "unexpected gh $*" >&2; exit 1 ;;
esac
EOF
  chmod +x "$root/bin/gh"
  output="$(cd "$root" && env -i PATH="$root/bin:/usr/bin:/bin" FAKE_LOG="$root/log" GITHUB_SHA=abc123 "$@" \
    bash scripts/publish-release.sh 0.2.0 2>&1)" || code=$?
  local ok=1
  [ "$code" = "$want_exit" ] || ok=0
  if ! (cd "$root" && eval "$check"); then ok=0; fi
  if [ "$ok" = 1 ]; then
    passed=$((passed + 1)); echo "ok   $name"
  else
    failed=$((failed + 1)); echo "FAIL $name (exit $code)"
    printf '%s\n' "$output" | sed 's/^/     | /'
    sed 's/^/     gh /' "$root/log/gh" 2>/dev/null || true
  fi
  rm -rf "$root"
}

run_case publishes_both_assets_at_the_commit 0 \
  'grep -qx "release create v0.2.0 build/Agenty-0.2.0-arm64.zip build/Agenty-0.2.0-arm64.zip.sha256 --target abc123 --title Agenty 0.2.0 --generate-notes" log/gh && ! grep -q "release delete" log/gh'
run_case failed_upload_deletes_the_draft 1 \
  'grep -qx "release delete v0.2.0 --yes" log/gh' \
  FAKE_CREATE_EXIT=1 FAKE_VIEW_OUT=true
run_case failure_never_deletes_a_published_release 1 \
  '! grep -q "release delete" log/gh' \
  FAKE_CREATE_EXIT=1 FAKE_VIEW_OUT=false
run_case failure_without_a_release_deletes_nothing 1 \
  '! grep -q "release delete" log/gh' \
  FAKE_CREATE_EXIT=1 FAKE_VIEW_EXIT=1

echo "$passed passed, $failed failed"
[ "$failed" = 0 ]
