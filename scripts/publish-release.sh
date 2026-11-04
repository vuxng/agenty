#!/bin/bash
# Publish build/Agenty-<version>-arm64.zip, its .sha256 and build/appcast.xml as GitHub Release
# v<version> at $GITHUB_SHA, with build/notes.md as the release notes:
# scripts/publish-release.sh <version>. Needs gh with a token (GH_TOKEN).
#
# With assets, gh creates a draft, uploads, then publishes it, and GitHub creates the tag
# only at that last step. If any of it fails, the leftover draft is deleted so a re-run
# starts clean. A published release is never deleted.
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <version>   (e.g. $0 0.1.0)" >&2
  exit 1
fi

version="$1"
tag="v$version"
zip="build/Agenty-$version-arm64.zip"
cd "$(dirname "$0")/.."

if gh release create "$tag" "$zip" "$zip.sha256" build/appcast.xml \
  --target "${GITHUB_SHA:?GITHUB_SHA must be set}" --title "Agenty $version" --notes-file build/notes.md; then
  exit 0
fi

if [ "$(gh release view "$tag" --json isDraft --jq .isDraft 2>/dev/null || true)" = "true" ]; then
  echo "error: publishing $tag failed; deleting its draft release." >&2
  gh release delete "$tag" --yes || echo "warning: could not delete the draft release $tag." >&2
else
  echo "error: publishing $tag failed." >&2
fi
exit 1
