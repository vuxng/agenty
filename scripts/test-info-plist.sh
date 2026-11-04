#!/bin/bash
# Checks the update settings in App/Info.plist (generated from project.yml by XcodeGen and
# committed): the feed, the public key, and the chosen mode, which is to check daily and ask
# before installing (Sparkle must not offer silent installs), plus the display name, which comes
# from the build configuration ("Agenty Dev" in Debug). Runs anywhere with python3.
set -euo pipefail

PLIST="${INFO_PLIST:-$(cd "$(dirname "$0")/.." && pwd)/App/Info.plist}"

python3 - "$PLIST" <<'PY'
import base64, plistlib, sys

info = plistlib.load(open(sys.argv[1], "rb"))
checks = [
    ("feed_is_the_latest_release_appcast",
     info.get("SUFeedURL") == "https://github.com/vuxng/agenty/releases/latest/download/appcast.xml"),
    ("public_key_is_ed25519",
     len(base64.b64decode(info.get("SUPublicEDKey", ""), validate=True)) == 32),
    ("checks_daily_without_asking_first", info.get("SUEnableAutomaticChecks") is True),
    ("never_offers_silent_installs", info.get("SUAllowsAutomaticUpdates") is False),
    ("does_not_install_silently", info.get("SUAutomaticallyUpdate", False) is False),
    # Debug builds are "Agenty Dev": the name must come from the build configuration.
    ("display_name_comes_from_build_setting", info.get("CFBundleDisplayName") == "$(APP_DISPLAY_NAME)"),
]
failed = 0
for name, ok in checks:
    print(("ok   " if ok else "FAIL ") + name)
    failed += not ok
print(f"{len(checks) - failed} passed, {failed} failed")
sys.exit(1 if failed else 0)
PY
