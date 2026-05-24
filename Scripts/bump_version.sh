#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: Scripts/bump_version.sh <semver>" >&2
  exit 64
fi

version="$1"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$ ]]; then
  echo "Version must be semantic, for example 0.2.0 or 1.0.0-beta.1" >&2
  exit 64
fi

printf '%s\n' "$version" > VERSION
echo "Version set to $version"
