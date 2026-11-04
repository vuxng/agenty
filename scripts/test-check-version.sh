#!/bin/bash
# Tests for scripts/check-version.sh. Each case runs in a throwaway git repo.
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-version.sh"
passed=0
failed=0

# make_repo <MARKETING_VERSION line value or empty for no line> [tags...]
# Prints the temp repo path.
make_repo() {
  local version_line="$1"
  shift
  local tmp
  tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  {
    echo "settings:"
    if [ -n "$version_line" ]; then
      echo "    MARKETING_VERSION: $version_line"
    fi
    echo "    CURRENT_PROJECT_VERSION: 1"
  } > "$tmp/project.yml"
  git -C "$tmp" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
  local tag
  for tag in "$@"; do
    git -C "$tmp" tag "$tag"
  done
  echo "$tmp"
}

# run_case <name> <expected exit> <expected stdout or ""> <expected stderr substring or ""> <repo>
run_case() {
  local name="$1" want_exit="$2" want_out="$3" want_err="$4" tmp="$5"
  local out err code=0
  out="$(cd "$tmp" && PROJECT_YML="$tmp/project.yml" GITHUB_OUTPUT="$tmp/out" "$SCRIPT" 2> "$tmp/stderr")" || code=$?
  err="$(cat "$tmp/stderr")"
  local ok=1
  [ "$code" = "$want_exit" ] || ok=0
  if [ -n "$want_out" ] && [ "$out" != "$want_out" ]; then ok=0; fi
  if [ -n "$want_err" ] && [[ "$err" != *"$want_err"* ]]; then ok=0; fi
  if [ "$want_exit" = 0 ] && [ -n "$want_out" ]; then
    grep -qx "$want_out" "$tmp/out" 2>/dev/null || ok=0
  fi
  # A failed check must not print a version or hand one to later workflow steps.
  if [ "$want_exit" != 0 ]; then
    [ -z "$out" ] || ok=0
    [ ! -s "$tmp/out" ] || ok=0
  fi
  if [ "$ok" = 1 ]; then
    passed=$((passed + 1))
    echo "ok   $name"
  else
    failed=$((failed + 1))
    echo "FAIL $name (exit $code, stdout: $out, stderr: $err)"
  fi
  rm -rf "$tmp"
}

run_case no_tags_passes 0 "version=0.1.0" "" "$(make_repo '0.1.0')"
run_case quoted_version_parses 0 "version=0.2.0" "" "$(make_repo '"0.2.0"' v0.1.0)"
run_case trailing_space_parses 0 "version=0.2.0" "" "$(make_repo '0.2.0  ' v0.1.0)"
run_case tag_exists_fails 1 "" "already released" "$(make_repo '0.1.0' v0.1.0)"
run_case older_than_latest_fails 1 "" "must be greater than the latest release v0.2.0" "$(make_repo '0.1.0' v0.2.0)"
run_case semver_not_lexical 0 "version=0.10.0" "" "$(make_repo '0.10.0' v0.9.0)"
run_case non_release_tags_ignored 0 "version=0.2.0" "" "$(make_repo '0.2.0' v0.1.0 v1.0.0-beta.1 next)"
run_case bad_format_fails 1 "" "is not X.Y.Z" "$(make_repo '0.2')"
run_case missing_key_fails 1 "" "not found" "$(make_repo '')"

echo "$passed passed, $failed failed"
[ "$failed" = 0 ]
