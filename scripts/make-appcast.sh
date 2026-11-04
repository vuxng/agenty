#!/bin/bash
# Write build/appcast.xml for Sparkle: scripts/make-appcast.sh <version>
#
# Input:  the EdDSA private key on stdin (never as an argument),
#         build/Agenty-<version>-arm64.zip and build/notes.md (markdown release notes).
# Output: build/appcast.xml with one item for this version. The item's signature is checked
#         against SUPublicEDKey of the app inside the zip first, so a key that doesn't match
#         the app never reaches users.
# SPARKLE_BIN   directory with Sparkle's sign_update (default: the SPM artifact after a build)
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <version>   (e.g. $0 0.2.0)" >&2
  exit 1
fi

version="$1"
cd "$(dirname "$0")/.."
SPARKLE_BIN="${SPARKLE_BIN:-build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin}"
zip="build/Agenty-$version-arm64.zip"
notes="build/notes.md"
appcast="build/appcast.xml"
url="https://github.com/vuxng/agenty/releases/download/v$version/Agenty-$version-arm64.zip"

key="$(cat)"
if [ -z "$key" ]; then
  echo "error: Sparkle private key is missing (expected on stdin)." >&2
  exit 1
fi
for file in "$zip" "$notes"; do
  if [ ! -f "$file" ]; then
    echo "error: $file not found." >&2
    exit 1
  fi
done

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
ditto -x -k "$zip" "$work"
plist="$work/Agenty.app/Contents/Info.plist"
info() { plutil -extract "$1" raw -o - "$plist"; }
short_version="$(info CFBundleShortVersionString)"
build_number="$(info CFBundleVersion)"
public_key="$(info SUPublicEDKey)"
minimum_system="$(info LSMinimumSystemVersion)"
if [ "$short_version" != "$version" ]; then
  echo "error: $zip holds version $short_version, not $version." >&2
  exit 1
fi

signed="$(printf '%s' "$key" | "$SPARKLE_BIN/sign_update" --ed-key-file - "$zip")"
if [[ "$signed" =~ sparkle:edSignature=\"([^\"]+)\"\ length=\"([0-9]+)\" ]]; then
  signature="${BASH_REMATCH[1]}"
  length="${BASH_REMATCH[2]}"
else
  echo "error: unexpected sign_update output." >&2
  exit 1
fi

# Compile first: a broken verifier must never read as a key mismatch (that message invites a
# key rotation, which strands every install).
if ! swiftc -O -o "$work/verify-ed-signature" scripts/verify-ed-signature.swift; then
  echo "error: could not compile scripts/verify-ed-signature.swift." >&2
  exit 1
fi
check=0
"$work/verify-ed-signature" "$zip" "$signature" "$public_key" || check=$?
if [ "$check" = 1 ]; then
  echo "error: the Sparkle key does not match SUPublicEDKey in the app ($public_key)." >&2
  exit 1
elif [ "$check" != 0 ]; then
  echo "error: could not check the signature against SUPublicEDKey." >&2
  exit 1
fi

pub_date="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
notes_text="$(cat "$notes")"
# "]]>" would end the CDATA section early: split it across two sections.
notes_cdata="${notes_text//]]>/]]]]><![CDATA[>}"

cat > "$work/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Agenty</title>
    <link>https://github.com/vuxng/agenty</link>
    <item>
      <title>Agenty $short_version</title>
      <pubDate>$pub_date</pubDate>
      <sparkle:version>$build_number</sparkle:version>
      <sparkle:shortVersionString>$short_version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$minimum_system</sparkle:minimumSystemVersion>
      <description sparkle:format="markdown"><![CDATA[$notes_cdata]]></description>
      <enclosure url="$url" length="$length" type="application/octet-stream" sparkle:edSignature="$signature"/>
    </item>
  </channel>
</rss>
EOF
xmllint --noout "$work/appcast.xml"
mv "$work/appcast.xml" "$appcast"
echo "Created $appcast (Agenty $short_version, build $build_number)"
