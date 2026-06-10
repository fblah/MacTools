#!/usr/bin/env bash
set -euo pipefail

# One-time helper to push the code-signing + notarization secrets into the
# GitHub repo so the Release workflow can sign with the Hardened Runtime and
# notarize automatically on every v* tag.
#
# Nothing secret is hard-coded here. You supply:
#   • your Developer ID Application cert (exported from Keychain as a .p12), and
#   • an App Store Connect API key (.p8) plus its Key ID and Issuer ID.
#
# Usage:
#   Scripts/setup_notary_secrets.sh \
#       --p12 ~/DeveloperID.p12 \
#       --notary-key ~/AuthKey_XXXXXXXXXX.p8 \
#       --notary-key-id XXXXXXXXXX \
#       --notary-issuer 11111111-2222-3333-4444-555555555555
#
# The .p12 export passphrase is prompted for interactively (hidden input) —
# it is deliberately NOT a command-line flag, because an argument would land
# in shell history and be visible to every user via `ps`. For non-interactive
# use, export it as P12_PASSWORD in the environment instead.
#
# Any flag may be omitted to set only some secrets; the script reports what it set.

P12="" ; P12_PASSWORD="${P12_PASSWORD:-}" ; NOTARY_KEY="" ; NOTARY_KEY_ID="" ; NOTARY_ISSUER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --p12) P12="$2"; shift 2 ;;
    --p12-password)
      echo "error: --p12-password was removed — a passphrase argument lands in shell history and \`ps\` output." >&2
      echo "       Run again without it to be prompted (hidden input), or export P12_PASSWORD for non-interactive use." >&2
      exit 64 ;;
    --notary-key) NOTARY_KEY="$2"; shift 2 ;;
    --notary-key-id) NOTARY_KEY_ID="$2"; shift 2 ;;
    --notary-issuer) NOTARY_ISSUER="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 64 ;;
  esac
done

# Prompt for the .p12 passphrase (hidden) when a cert is being uploaded and no
# P12_PASSWORD came from the environment. Skipped when stdin is not a TTY so
# scripted runs without the env var still fall through to the warning below.
if [[ -n "$P12" && -z "$P12_PASSWORD" && -t 0 ]]; then
  read -rs -p "Enter the .p12 export passphrase (input hidden): " P12_PASSWORD
  echo
fi

command -v gh >/dev/null || { echo "error: GitHub CLI (gh) not found." >&2; exit 1; }

set_secret() {
  local name="$1" value="$2"
  printf '%s' "$value" | gh secret set "$name"
  echo "  set $name"
}

echo "Setting repository secrets…"

if [[ -n "$P12" ]]; then
  [[ -f "$P12" ]] || { echo "error: p12 not found: $P12" >&2; exit 1; }
  set_secret MACOS_CERT_P12 "$(base64 < "$P12")"
  if [[ -n "$P12_PASSWORD" ]]; then
    set_secret MACOS_CERT_PASSWORD "$P12_PASSWORD"
  else
    echo "  ! MACOS_CERT_PASSWORD not provided — set it before relying on CI signing" >&2
  fi
fi

if [[ -n "$NOTARY_KEY" ]]; then
  [[ -f "$NOTARY_KEY" ]] || { echo "error: notary key not found: $NOTARY_KEY" >&2; exit 1; }
  set_secret NOTARY_KEY_P8 "$(base64 < "$NOTARY_KEY")"
fi
[[ -n "$NOTARY_KEY_ID" ]] && set_secret NOTARY_KEY_ID "$NOTARY_KEY_ID"
[[ -n "$NOTARY_ISSUER" ]] && set_secret NOTARY_KEY_ISSUER "$NOTARY_ISSUER"

echo
echo "Done. Current repo secrets:"
gh secret list
