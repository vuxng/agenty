#!/bin/bash
# Checks that Debug builds are "Agenty Dev" with their own bundle id, so a build you run to test
# never shares settings, the login item or permissions with the installed Agenty, and that
# Release builds keep the official identity (updates depend on it).
# Needs xcodebuild and the generated project: run `xcodegen generate` first.
set -euo pipefail

cd "$(dirname "$0")/.."
if [ ! -d Agenty.xcodeproj ]; then
  echo "error: Agenty.xcodeproj not found; run 'xcodegen generate' first." >&2
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# xcodebuild logs unrelated simulator warnings to stderr: show them only if it fails.
settings() {
  if ! xcodebuild -project Agenty.xcodeproj -target Agenty -configuration "$1" \
    -showBuildSettings -json 2>"$work/xcodebuild.log"; then
    cat "$work/xcodebuild.log" >&2
    exit 1
  fi
}
settings Debug > "$work/debug.json"
settings Release > "$work/release.json"

python3 - "$work/debug.json" "$work/release.json" <<'PY'
import json, sys

def load(path):
    return json.load(open(path))[0]["buildSettings"]

debug, release = load(sys.argv[1]), load(sys.argv[2])
checks = [
    ("debug_has_its_own_bundle_id", debug.get("PRODUCT_BUNDLE_IDENTIFIER") == "io.github.vuxng.Agenty.dev"),
    ("debug_app_is_agenty_dev", debug.get("FULL_PRODUCT_NAME") == "Agenty Dev.app"),
    ("debug_display_name_is_agenty_dev", debug.get("APP_DISPLAY_NAME") == "Agenty Dev"),
    ("debug_module_is_still_agenty", debug.get("PRODUCT_MODULE_NAME") == "Agenty"),
    ("release_keeps_the_official_bundle_id", release.get("PRODUCT_BUNDLE_IDENTIFIER") == "io.github.vuxng.Agenty"),
    ("release_app_is_agenty", release.get("FULL_PRODUCT_NAME") == "Agenty.app"),
    ("release_display_name_is_agenty", release.get("APP_DISPLAY_NAME") == "Agenty"),
    ("release_module_is_agenty", release.get("PRODUCT_MODULE_NAME") == "Agenty"),
]
failed = 0
for name, ok in checks:
    print(("ok   " if ok else "FAIL ") + name)
    failed += not ok
print(f"{len(checks) - failed} passed, {failed} failed")
sys.exit(1 if failed else 0)
PY
