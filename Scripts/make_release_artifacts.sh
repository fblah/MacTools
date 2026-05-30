#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION_OVERRIDE:-$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || echo 1)}"
TAG_NAME="${TAG_NAME:-v$VERSION}"
REPOSITORY="${GITHUB_REPOSITORY:-havokentity/MacTools}"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-com.havokentity.mactools}"
SPARKLE_SIGN_UPDATE="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/sign_update"
ZIP_NAME="DMonte-Toolbox-$VERSION.zip"
ZIP_PATH="$ROOT_DIR/dist/$ZIP_NAME"
APPCAST_PATH="$ROOT_DIR/dist/appcast.xml"
DOWNLOAD_URL="https://github.com/$REPOSITORY/releases/download/$TAG_NAME/$ZIP_NAME"

"$ROOT_DIR/Scripts/package_app.sh"

# Notarize + staple BEFORE zipping, so the Sparkle archive ships a stapled app
# that Gatekeeper opens cleanly offline. notarize_app.sh no-ops (exit 0) when no
# notary credentials are present, so local/CI-without-secrets builds still work.
"$ROOT_DIR/Scripts/notarize_app.sh"

rm -f "$ZIP_PATH" "$APPCAST_PATH"
cd "$ROOT_DIR/dist"
ditto -c -k --sequesterRsrc --keepParent "DMonte Toolbox.app" "$ZIP_NAME"

if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  signature_output="$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SPARKLE_SIGN_UPDATE" --ed-key-file - "$ZIP_PATH")"
else
  signature_output="$("$SPARKLE_SIGN_UPDATE" --account "$SPARKLE_ACCOUNT" "$ZIP_PATH")"
fi

ed_signature="$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' <<< "$signature_output")"
archive_length="$(sed -n 's/.*length="\([^"]*\)".*/\1/p' <<< "$signature_output")"
pub_date="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S %z')"

if [[ -z "$ed_signature" || -z "$archive_length" ]]; then
  echo "Could not parse Sparkle signature output: $signature_output" >&2
  exit 1
fi

cat > "$APPCAST_PATH" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>D'Monte's Toolbox Updates</title>
    <link>https://github.com/$REPOSITORY</link>
    <description>Release feed for D'Monte's Toolbox.</description>
    <language>en</language>
    <item>
      <title>D'Monte's Toolbox $VERSION</title>
      <link>https://github.com/$REPOSITORY/releases/tag/$TAG_NAME</link>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <description sparkle:format="plain-text">D'Monte's Toolbox $VERSION release.</description>
      <pubDate>$pub_date</pubDate>
      <enclosure
        url="$DOWNLOAD_URL"
        sparkle:edSignature="$ed_signature"
        length="$archive_length"
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
XML

echo "Created $ZIP_PATH"
echo "Created $APPCAST_PATH"
