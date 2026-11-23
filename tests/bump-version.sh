#!/usr/bin/env bash
# tests/bump-version.sh — offline regression check for scripts/bump-version.sh
#
# Guards the two failures that made the weekly "Update Freebuff Version"
# workflow fail on main from 2026-10-19 through 2026-11-09:
#
#   1. Version was parsed from the redirect *filename* of
#      freebuff.com/api/desktop/download/linux. Upstream switched the Linux
#      payload to a .deb, the "Freebuff-<ver>-linux-x86_64.AppImage" regex
#      never matched, the script exited 1 and the workflow went red weekly.
#   2. The GitHub API auth header was committed with a redacted placeholder
#      ("Bearer ***") instead of "${GITHUB_TOKEN}", so authenticated calls
#      were not actually authenticated and the rate limit still bit.
#
# No network, no nix: pure source inspection, so it is safe in any CI job.
set -euo pipefail

cd "$(dirname "$0")/.."
script="scripts/bump-version.sh"
fail=0

note() { echo "  $*"; }
bad()  { echo "FAIL: $*" >&2; fail=1; }

[ -f "$script" ] || { echo "FAIL: $script missing" >&2; exit 1; }

echo "== syntax"
bash -n "$script" && note "bash -n ok" || bad "bash -n failed"

echo "== version must not come from the download redirect filename"
if grep -qE 'Freebuff-\(\[0-9\]\+.*linux-x86_64' "$script"; then
  bad "old filename regex is back — upstream serves a .deb now"
else
  note "no redirect-filename regex"
fi
grep -q 'releases/download' "$script" \
  || bad "asset URL must be built from the versioned release tag"
grep -q 'ASSET="Freebuff-${VERSION}-linux-x86_64.AppImage"' "$script" \
  || bad "AppImage asset name template changed unexpectedly"

echo "== auth header must reference the token, never a placeholder"
if grep -q 'Bearer \*\*\*' "$script"; then
  bad "Authorization header is a placeholder (Bearer ***) — API calls are unauthenticated"
fi
grep -q 'Bearer \${GITHUB_TOKEN}' "$script" \
  || bad "Authorization header does not reference \${GITHUB_TOKEN}"

echo "== fetchurl must use a flat sha256 SRI (not a NAR path hash)"
grep -q 'nix hash file --type sha256 --sri' "$script" \
  || bad "flat-file hash command missing (nix hash path hashes the NAR)"

echo "== the payload is checked to be an ELF before it is pinned"
grep -q 'ELF' "$script" || bad "missing ELF magic guard (upstream format-change trap)"

if [ "$fail" -ne 0 ]; then
  echo "RESULT: FAIL"
  exit 1
fi
echo "RESULT: PASS"
