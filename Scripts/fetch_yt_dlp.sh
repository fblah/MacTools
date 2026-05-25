#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/.build/vendor/yt-dlp"
OUTPUT_PATH="$VENDOR_DIR/yt-dlp"
VERSION_PATH="$VENDOR_DIR/version"

YT_DLP_VERSION="${YT_DLP_VERSION:-latest}"

curl_args=(
  --fail
  --location
  --retry 5
  --retry-delay 2
  --retry-all-errors
  --connect-timeout 15
)

if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  curl_args+=(--header "Authorization: Bearer $GITHUB_TOKEN")
fi

if [[ "$YT_DLP_VERSION" == "latest" ]]; then
  release_json="$(curl --silent "${curl_args[@]}" "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest")"
  RESOLVED_YT_DLP_VERSION="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' <<< "$release_json" | head -n 1)"

  if [[ -z "$RESOLVED_YT_DLP_VERSION" ]]; then
    echo "Could not resolve latest yt-dlp release tag" >&2
    exit 1
  fi
else
  RESOLVED_YT_DLP_VERSION="$YT_DLP_VERSION"
fi

DOWNLOAD_URL="https://github.com/yt-dlp/yt-dlp/releases/download/$RESOLVED_YT_DLP_VERSION/yt-dlp_macos"

mkdir -p "$VENDOR_DIR"

if [[ -x "$OUTPUT_PATH" && -f "$VERSION_PATH" && "$(cat "$VERSION_PATH")" == "$RESOLVED_YT_DLP_VERSION" ]]; then
  echo "$OUTPUT_PATH"
  exit 0
fi

echo "Fetching yt-dlp from $DOWNLOAD_URL" >&2
tmp_path="$OUTPUT_PATH.tmp"
rm -f "$tmp_path"
curl "${curl_args[@]}" "$DOWNLOAD_URL" --output "$tmp_path"
mv "$tmp_path" "$OUTPUT_PATH"
chmod 755 "$OUTPUT_PATH"
xattr -cr "$OUTPUT_PATH" 2>/dev/null || true
printf '%s' "$RESOLVED_YT_DLP_VERSION" > "$VERSION_PATH"

echo "$OUTPUT_PATH"
