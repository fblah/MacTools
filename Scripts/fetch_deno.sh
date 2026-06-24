#!/usr/bin/env bash
set -euo pipefail

# Fetches the Deno runtime for the Video Downloader and prints the directory that
# holds it. yt-dlp uses Deno to solve YouTube's JavaScript "n challenge" (required
# whenever cookies are sent, and increasingly in general); without a supported JS
# runtime yt-dlp can only see image/storyboard formats and fails with "Requested
# format is not available". Node is NOT a supported runtime for this — Deno is.
#
# Mirrors fetch_ffmpeg.sh: pinned version + SHA-256, verified fail-closed. Deno is
# MIT-licensed (a credits file ships alongside it). It runs as a separate child
# process spawned by yt-dlp, never linked into the app.
#
# Bumping the pin: pick a release from https://github.com/denoland/deno/releases,
# download deno-<arch>-apple-darwin.zip, and update the version + SHA-256 below
# (or override per build with DENO_VERSION / DENO_SHA256). With no pinned/override
# hash the script fails closed unless DENO_ALLOW_UNVERIFIED=1 (local dev only).

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/.build/vendor/deno"
VERSION_PATH="$VENDOR_DIR/version"

PINNED_DENO_VERSION="2.8.3"
# SHA-256 of deno-<arch>-apple-darwin.zip. arm64 is pinned (downloaded + verified
# to solve the challenge); amd64 is left empty and requires DENO_SHA256 to verify.
PINNED_ARM64_SHA256="88b350be928fdba0e5d8142ff7c101a17133426371e3cf5ed0e0f74e62476f6c"
PINNED_AMD64_SHA256=""

DENO_VERSION="${DENO_VERSION:-$PINNED_DENO_VERSION}"

case "$(uname -m)" in
  arm64)
    DENO_ARCH="aarch64"
    PINNED_SHA256="$PINNED_ARM64_SHA256"
    ;;
  x86_64)
    DENO_ARCH="x86_64"
    PINNED_SHA256="$PINNED_AMD64_SHA256"
    ;;
  *)
    echo "unsupported architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

DOWNLOAD_URL="https://github.com/denoland/deno/releases/download/v$DENO_VERSION/deno-$DENO_ARCH-apple-darwin.zip"
VERSION_TAG="$DENO_VERSION-$DENO_ARCH"

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

mkdir -p "$VENDOR_DIR"

if [[ -x "$VENDOR_DIR/deno" && -f "$VERSION_PATH" && "$(cat "$VERSION_PATH")" == "$VERSION_TAG" ]]; then
  echo "$VENDOR_DIR"
  exit 0
fi

expected_sha="${DENO_SHA256:-$PINNED_SHA256}"

echo "Fetching deno from $DOWNLOAD_URL" >&2
tmp_zip="$VENDOR_DIR/deno.zip.tmp"
rm -f "$tmp_zip"
curl "${curl_args[@]}" "$DOWNLOAD_URL" --output "$tmp_zip"

actual_sha="$(shasum -a 256 "$tmp_zip" | awk '{print $1}')"
if [[ -z "$expected_sha" ]]; then
  if [[ "${DENO_ALLOW_UNVERIFIED:-0}" == "1" ]]; then
    echo "warning: no SHA-256 to verify deno (got $actual_sha); continuing because DENO_ALLOW_UNVERIFIED=1" >&2
  else
    echo "error: no SHA-256 to verify deno $VERSION_TAG (got $actual_sha)" >&2
    echo "  set DENO_SHA256=<expected>, or DENO_ALLOW_UNVERIFIED=1 for local dev only" >&2
    rm -f "$tmp_zip"
    exit 1
  fi
elif [[ "$actual_sha" != "$expected_sha" ]]; then
  echo "deno checksum mismatch for $VERSION_TAG" >&2
  echo "  expected: $expected_sha" >&2
  echo "  actual:   $actual_sha" >&2
  rm -f "$tmp_zip"
  exit 1
else
  echo "deno checksum verified ($actual_sha)" >&2
fi

rm -f "$VENDOR_DIR/deno"
unzip -oq "$tmp_zip" "deno" -d "$VENDOR_DIR"
chmod 755 "$VENDOR_DIR/deno"
xattr -cr "$VENDOR_DIR/deno" 2>/dev/null || true
rm -f "$tmp_zip"

printf '%s' "$VERSION_TAG" > "$VERSION_PATH"

echo "$VENDOR_DIR"
