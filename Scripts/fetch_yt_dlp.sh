#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/.build/vendor/yt-dlp"
OUTPUT_PATH="$VENDOR_DIR/yt-dlp"
VERSION_PATH="$VENDOR_DIR/version"

# yt-dlp is pinned to an exact release + SHA-256 so every build (local and CI)
# embeds the same verified binary. To bump the pin: pick the new tag, grab the
# yt-dlp_macos line from that release's SHA2-256SUMS file, and update the two
# values below (or override per-build with YT_DLP_VERSION=<tag> plus a matching
# YT_DLP_SHA256=<hash>). Overriding YT_DLP_VERSION (including "latest") without
# YT_DLP_SHA256 falls back to the upstream SHA2-256SUMS file and fails closed if
# no expected hash can be obtained; YT_DLP_ALLOW_UNVERIFIED=1 downgrades that to
# a warning for local development only — it must never be set in CI.
PINNED_YT_DLP_VERSION="2026.06.09"
PINNED_YT_DLP_SHA256="b82c3626952e6c14eaf654cc565866775ffd0b9ffb7021628ac59b42c2f4f244"

YT_DLP_VERSION="${YT_DLP_VERSION:-$PINNED_YT_DLP_VERSION}"

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

# Resolve the expected hash without touching the network: an explicit
# YT_DLP_SHA256 wins, otherwise the pinned hash applies when fetching the
# pinned version. Anything else is resolved from SHA2-256SUMS after download.
expected_sha="${YT_DLP_SHA256:-}"
if [[ -z "$expected_sha" && "$RESOLVED_YT_DLP_VERSION" == "$PINNED_YT_DLP_VERSION" ]]; then
  expected_sha="$PINNED_YT_DLP_SHA256"
fi

mkdir -p "$VENDOR_DIR"

if [[ -x "$OUTPUT_PATH" && -f "$VERSION_PATH" && "$(cat "$VERSION_PATH")" == "$RESOLVED_YT_DLP_VERSION" ]]; then
  if [[ -z "$expected_sha" || "$(shasum -a 256 "$OUTPUT_PATH" | awk '{print $1}')" == "$expected_sha" ]]; then
    echo "$OUTPUT_PATH"
    exit 0
  fi
  echo "cached yt-dlp at $OUTPUT_PATH does not match expected SHA-256; re-fetching" >&2
fi

echo "Fetching yt-dlp from $DOWNLOAD_URL" >&2
tmp_path="$OUTPUT_PATH.tmp"
rm -f "$tmp_path"
curl "${curl_args[@]}" "$DOWNLOAD_URL" --output "$tmp_path"

# Verify the download's SHA-256 before trusting the binary. If no expected hash
# was resolved above (overridden version without YT_DLP_SHA256), fetch yt-dlp's
# official SHA2-256SUMS for this release and match the entry for yt-dlp_macos.
# Verification is fail-closed: no expected hash, or a mismatch, aborts the build
# unless YT_DLP_ALLOW_UNVERIFIED=1 (local dev only — never set this in CI).
actual_sha="$(shasum -a 256 "$tmp_path" | awk '{print $1}')"

if [[ -z "$expected_sha" ]]; then
  sums_url="https://github.com/yt-dlp/yt-dlp/releases/download/$RESOLVED_YT_DLP_VERSION/SHA2-256SUMS"
  sums="$(curl --silent "${curl_args[@]}" "$sums_url" || true)"
  if [[ -n "$sums" ]]; then
    expected_sha="$(awk '$2 == "yt-dlp_macos" {print $1}' <<< "$sums" | head -n 1)"
  fi
fi

if [[ -z "$expected_sha" ]]; then
  if [[ "${YT_DLP_ALLOW_UNVERIFIED:-0}" == "1" ]]; then
    echo "warning: no SHA-256 available to verify yt-dlp $RESOLVED_YT_DLP_VERSION (got $actual_sha); continuing because YT_DLP_ALLOW_UNVERIFIED=1" >&2
  else
    echo "error: no SHA-256 available to verify yt-dlp $RESOLVED_YT_DLP_VERSION (got $actual_sha)" >&2
    echo "  set YT_DLP_SHA256=<yt-dlp_macos entry from the release's SHA2-256SUMS>," >&2
    echo "  or YT_DLP_ALLOW_UNVERIFIED=1 for local development only (never in CI)" >&2
    rm -f "$tmp_path"
    exit 1
  fi
elif [[ "$actual_sha" != "$expected_sha" ]]; then
  echo "yt-dlp checksum mismatch for $RESOLVED_YT_DLP_VERSION" >&2
  echo "  expected: $expected_sha" >&2
  echo "  actual:   $actual_sha" >&2
  rm -f "$tmp_path"
  exit 1
else
  echo "yt-dlp checksum verified ($actual_sha)" >&2
fi

mv "$tmp_path" "$OUTPUT_PATH"
chmod 755 "$OUTPUT_PATH"
xattr -cr "$OUTPUT_PATH" 2>/dev/null || true
printf '%s' "$RESOLVED_YT_DLP_VERSION" > "$VERSION_PATH"

echo "$OUTPUT_PATH"
