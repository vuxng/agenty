#!/bin/bash
# Check that MARKETING_VERSION in project.yml is a new release: X.Y.Z, not tagged yet,
# and greater than the latest vX.Y.Z tag. Prints version=X.Y.Z (also to $GITHUB_OUTPUT).
# Needs the repo's tags (CI: actions/checkout with fetch-depth: 0).
set -euo pipefail

file="${PROJECT_YML:-project.yml}"

line="$(grep -m1 'MARKETING_VERSION:' "$file" || true)"
if [ -z "$line" ]; then
  echo "error: MARKETING_VERSION not found in $file." >&2
  exit 1
fi

version="$(printf '%s' "${line#*MARKETING_VERSION:}" | tr -d "\"' \t\r")"
if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: MARKETING_VERSION \"$version\" in $file is not X.Y.Z." >&2
  exit 1
fi

if git rev-parse -q --verify "refs/tags/v$version" >/dev/null; then
  echo "error: v$version is already released (tag exists). Bump MARKETING_VERSION in project.yml." >&2
  exit 1
fi

latest_tag="$(git tag --list 'v*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1 || true)"
if [ -n "$latest_tag" ]; then
  latest_ver="${latest_tag#v}"
  highest="$(printf '%s\n%s\n' "$latest_ver" "$version" | sort -V | tail -1)"
  if [ "$highest" != "$version" ] || [ "$latest_ver" = "$version" ]; then
    echo "error: $version must be greater than the latest release $latest_tag." >&2
    exit 1
  fi
fi

echo "version=$version"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "version=$version" >> "$GITHUB_OUTPUT"
fi
