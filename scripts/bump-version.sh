#!/usr/bin/env bash
# bump-version.sh — re-pin pkgs/freebuff-desktop.nix to the latest upstream
# Freebuff Desktop AppImage.
#
# Used by .github/workflows/update.yml (weekly) and runnable by hand:
#   nix develop .# -c scripts/bump-version.sh
#
# Upstream layout (verified 2026-11):
#   https://freebuff.com/api/desktop/download/linux  -> 302
#     -> https://github.com/CodebuffAI/codebuff-community/releases/download/
#          freebuff-desktop-v<X.Y.Z>/Freebuff-<X.Y.Z>-linux-amd64.deb
#   AppImage asset (same release):
#          Freebuff-<X.Y.Z>-linux-x86_64.AppImage
#
# Two things this script must NOT rely on (both broke the weekly bump):
#   1. Parsing the version out of the endpoint's redirect *filename* — upstream
#      switched the Linux payload to .deb, so the old
#      "Freebuff-<ver>-linux-x86_64.AppImage" regex never matched.
#   2. `nix hash path` for the SRI — that hashes the NAR serialisation of the
#      path, while fetchurl's `sha256` is the *flat* file hash. Use
#      `nix hash file --type sha256 --sri` instead.
#
# The package URL is derived from `version` in the .nix file, so bumping only
# needs to rewrite `version` + `sha256`; both stay in lockstep by construction.
set -euo pipefail

cd "$(dirname "$0")/.."
PKG_FILE="pkgs/freebuff-desktop.nix"

readonly REPO="CodebuffAI/codebuff-community"
readonly TAG_PREFIX="freebuff-desktop-v"
readonly API="https://api.github.com/repos/${REPO}"
readonly ENDPOINT="https://freebuff.com/api/desktop/download/linux"

log()  { echo "[bump] $*"; }
die()  { echo "[bump] ERROR: $*" >&2; exit 1; }

# Authenticate GitHub API calls when a token is available: runners share IPs
# and the unauthenticated limit (60/h) is routinely exhausted. Every API call
# below has a non-API fallback, so this is an optimisation, not a requirement.
AUTH=()
if [ -n "${GITHUB_TOKEN:-}" ]; then
  AUTH=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

[ -f "$PKG_FILE" ] || die "cannot find $PKG_FILE (run from the repo root)"

# ── 1. Resolve the latest desktop version ───────────────────────────────
# 1a. Ask freebuff.com where it points today — upstream decides "latest".
VERSION=""
LOCATION=$(curl -fsSI --max-time 30 "$ENDPOINT" 2>/dev/null \
  | awk 'tolower($1)=="location:" {print $2}' | tr -d '\r' | head -1 || true)

if [[ "$LOCATION" =~ /download/${TAG_PREFIX}([0-9]+\.[0-9]+\.[0-9]+)/ ]]; then
  VERSION="${BASH_REMATCH[1]}"
  log "endpoint points at ${TAG_PREFIX}${VERSION}"
fi

# 1b. Fallback: highest desktop tag in the upstream git repo. One request,
#     complete tag list, no API rate limit (the release list is not ordered
#     by desktop version, so scanning it would need many pages).
if [ -z "$VERSION" ]; then
  log "falling back to upstream git tags …"
  VERSION=$(git ls-remote --tags --refs "https://github.com/${REPO}.git" 2>/dev/null \
    | sed "s|.*refs/tags/${TAG_PREFIX}||" \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1 || true)
fi

[ -n "$VERSION" ] || die "could not determine the latest version (endpoint unreachable and no desktop git tags found)"
log "latest version: $VERSION"

TAG="${TAG_PREFIX}${VERSION}"
ASSET="Freebuff-${VERSION}-linux-x86_64.AppImage"
ASSET_URL="https://github.com/${REPO}/releases/download/${TAG}/${ASSET}"

# ── 2. Confirm the AppImage asset actually exists for this release ─────
log "checking asset: $ASSET"
ASSET_FOUND=$(curl "${AUTH[@]}" -fsS --max-time 30 "${API}/releases/tags/${TAG}" 2>/dev/null \
  | grep -o "https://[^\"]*/${ASSET}" | head -1 || true)

if [ -z "$ASSET_FOUND" ]; then
  # API rate-limited / unavailable: fall back to a ranged HEAD on the asset.
  CODE=$(curl -sSL -r 0-0 -o /dev/null --max-time 30 \
    -w '%{http_code}' "$ASSET_URL" 2>/dev/null || true)
  [ "$CODE" = "200" ] || [ "$CODE" = "206" ] \
    || die "no x86_64 AppImage published for ${TAG} (HTTP ${CODE:-000}) — upstream may have dropped the AppImage"
  ASSET_FOUND="$ASSET_URL"
else
  ASSET_URL="$ASSET_FOUND"
fi
log "asset: $ASSET_URL"

# ── 3. Download and compute the flat sha256 SRI that fetchurl expects ──
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

log "downloading to compute hash …"
curl -fsSL --retry 3 --max-time 900 -o "$TMPFILE" "$ASSET_URL" \
  || die "download failed"

# Reject a truncated/HTML payload before it gets enshrined in the flake.
[ -s "$TMPFILE" ] || die "downloaded file is empty"
MAGIC=$(od -An -c -N 4 "$TMPFILE" | tr -d ' \n')
case "$MAGIC" in
  *ELF*) : ;;
  *) die "downloaded payload is not an ELF AppImage (magic: ${MAGIC}) — upstream format changed again" ;;
esac

SRI_HASH=$(nix hash file --type sha256 --sri "$TMPFILE" 2>/dev/null || true)
if [ -z "$SRI_HASH" ]; then
  # Portable fallback (no nix on PATH): SRI is "sha256-" + base64(raw digest).
  DIGEST=$(openssl dgst -sha256 -binary "$TMPFILE" | base64 | tr -d '\n')
  [ -n "$DIGEST" ] && SRI_HASH="sha256-${DIGEST}"
fi
[ -n "$SRI_HASH" ] || die "could not compute sha256"
log "sha256: $SRI_HASH ($(wc -c <"$TMPFILE") bytes)"

# ── 4. Compare with what is pinned today ────────────────────────────────
CURRENT_VERSION=$(grep -oE '^ *version = "[0-9][0-9.]*";' "$PKG_FILE" \
  | sed -E 's/.*"([0-9][0-9.]*)".*/\1/' | head -1)
CURRENT_HASH=$(grep -oE 'sha256 = "sha256-[^"]*";' "$PKG_FILE" \
  | sed -E 's/sha256 = "([^"]*)";/\1/' | head -1)

[ -n "$CURRENT_VERSION" ] || die "could not read current version from $PKG_FILE"

if [ "$VERSION" = "$CURRENT_VERSION" ] && [ "$SRI_HASH" = "$CURRENT_HASH" ]; then
  echo ""
  echo "No update needed — already at v$VERSION with the current hash"
  exit 0
fi

# ── 5. Update the pin ──────────────────────────────────────────────────
sed -i \
  -e "s|^ *version = \"[0-9][0-9.]*\";|  version = \"$VERSION\";|" \
  -e "s|sha256 = \"sha256-[^\"]*\";|sha256 = \"$SRI_HASH\";|" \
  "$PKG_FILE"

echo ""
echo "=== Update complete ==="
echo "  Version: ${CURRENT_VERSION:-none} → $VERSION"
echo "  Hash:    $SRI_HASH"
echo ""
echo "Updated: $PKG_FILE"
