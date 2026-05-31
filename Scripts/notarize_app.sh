#!/usr/bin/env bash
set -euo pipefail

# Notarizes and staples the packaged "DMonte Toolbox.app" so Gatekeeper opens it
# without warnings on other people's Macs. Run AFTER Scripts/package_app.sh has
# produced a Developer-ID + Hardened-Runtime signed app.
#
# Credentials come from the environment (never hard-coded — this repo is public).
# Provide ONE of:
#
#   A) App Store Connect API key (recommended for CI):
#        NOTARY_KEY_ID, NOTARY_KEY_ISSUER, NOTARY_KEY_PATH (path to AuthKey_*.p8)
#
#   B) Apple ID + app-specific password:
#        NOTARY_APPLE_ID, NOTARY_TEAM_ID, NOTARY_PASSWORD
#
#   C) A pre-saved notarytool keychain profile:
#        NOTARY_PROFILE  (name passed to `xcrun notarytool ... --keychain-profile`)
#
# If none are set, this prints how to configure them and exits 0 WITHOUT failing,
# so `make_release_artifacts.sh` can run unnotarized for local/ad-hoc builds.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/DMonte Toolbox.app"

if [[ ! -d "$APP_DIR" ]]; then
  echo "error: $APP_DIR not found — run Scripts/package_app.sh first." >&2
  exit 1
fi

# Decide which auth mode we have.
NOTARY_ARGS=()
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
elif [[ -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_KEY_ISSUER:-}" && -n "${NOTARY_KEY_PATH:-}" ]]; then
  NOTARY_ARGS=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_KEY_ISSUER")
elif [[ -n "${NOTARY_APPLE_ID:-}" && -n "${NOTARY_TEAM_ID:-}" && -n "${NOTARY_PASSWORD:-}" ]]; then
  NOTARY_ARGS=(--apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" --password "$NOTARY_PASSWORD")
else
  cat >&2 <<'MSG'
Skipping notarization: no credentials in the environment.

To notarize, set ONE of these credential sets and re-run:
  • API key:   NOTARY_KEY_ID, NOTARY_KEY_ISSUER, NOTARY_KEY_PATH
  • Apple ID:  NOTARY_APPLE_ID, NOTARY_TEAM_ID, NOTARY_PASSWORD
  • Profile:   NOTARY_PROFILE  (see: xcrun notarytool store-credentials)
MSG
  exit 0
fi

# notarytool ingests a zip/dmg/pkg, not a bare .app — zip it for submission.
SUBMIT_ZIP="$(mktemp -d)/DMonteToolbox-notarize.zip"
echo "Zipping app for notarization…"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$SUBMIT_ZIP"

echo "Submitting to Apple notary service (this can take a few minutes)…"
xcrun notarytool submit "$SUBMIT_ZIP" "${NOTARY_ARGS[@]}" --wait

# Staple the ticket onto the .app so it validates offline / after the zip is gone.
echo "Stapling notarization ticket…"
xcrun stapler staple "$APP_DIR"
xcrun stapler validate "$APP_DIR"

# Final Gatekeeper assessment — what a downloader's Mac will actually evaluate.
echo "Gatekeeper assessment:"
spctl --assess --type execute --verbose=2 "$APP_DIR"

rm -f "$SUBMIT_ZIP"
echo "Notarized and stapled: $APP_DIR"
