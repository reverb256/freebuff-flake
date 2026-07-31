#!/usr/bin/env bash
# bump-version.sh — Fetch latest Freebuff AppImage and update package hash.
# Used by .github/workflows/update.yml and can be run manually.
set -euo pipefail

cd "$(dirname "$0")/.."
PKG_FILE="pkgs/freebuff-desktop.nix"

# 1. Resolve the latest download URL
echo "Resolving latest Freebuff AppImage URL …"
REDIRECT_URL=$(curl -sSLI -o /dev/null -w '%{url_effective}' \
  "https://freebuff.com/api/desktop/download/linux" 2>/dev/null || true)

if [ -z "$REDIRECT_URL" ]; then
  echo "ERROR: Could not resolve download URL (got empty redirect)" >&2
  exit 1
fi

echo "  URL: $REDIRECT_URL"

# 2. Extract version from filename (Freebuff-X.Y.Z-linux-x86_64.AppImage)
VERSION=""
if [[ "$REDIRECT_URL" =~ Freebuff-([0-9]+\.[0-9]+\.[0-9]+)-linux-x86_64\.AppImage ]]; then
  VERSION="${BASH_REMATCH[1]}"
fi

if [ -z "$VERSION" ]; then
  echo "ERROR: Could not parse version from URL: $REDIRECT_URL" >&2
  exit 1
fi

echo "  Version: $VERSION"

# 3. Download to compute SHA256
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

echo "  Downloading (to compute hash) …"
curl -sSL -o "$TMPFILE" "$REDIRECT_URL" || {
  echo "ERROR: Download failed" >&2
  exit 1
}

SRI_HASH=$(nix hash path "$TMPFILE" 2>/dev/null || nix hash file "$TMPFILE" 2>/dev/null || nix hash --sri path "$TMPFILE" --type sha256 2>/dev/null || nix --experimental-features nix-command hash path "$TMPFILE" --type sha256 --sri 2>/dev/null || sha256sum "$TMPFILE" | awk '{print "sha256-"$1}' | xxd -r -p | base64 2>/dev/null || true)

if [ -z "$SRI_HASH" ]; then
  # Fallback: compute SRI manually
  SRI_HASH="sha256-$(nix hash --sri path "$TMPFILE" 2>/dev/null || true)"
fi

if [ -z "$SRI_HASH" ]; then
  echo "ERROR: Could not compute hash" >&2
  exit 1
fi

echo "  SRI Hash: $SRI_HASH"

# 4. Read current version from the package file
CURRENT_VERSION=$(grep 'version =' "$PKG_FILE" | sed 's/.*version = "\(.*\)".*/\1/')

if [ "$VERSION" = "$CURRENT_VERSION" ]; then
  echo ""
  echo "No update needed — already at v$VERSION"
  exit 0
fi

# 5. Update package file
sed -i \
  -e "s/version = \".*\";/version = \"$VERSION\";/" \
  -e "s|sha256 = \".*\";|sha256 = \"$SRI_HASH\";|" \
  "$PKG_FILE"

echo ""
echo "=== Update complete ==="
echo "  Version: $CURRENT_VERSION → $VERSION"
echo "  Hash: ${SRI_HASH:0:32}..."
echo ""
echo "Updated: $PKG_FILE"
