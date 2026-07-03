#!/usr/bin/env bash
#
# Récupère les lecteurs VLC (libvlc) dans Vendor/ :
#   - TVVLCKit.xcframework      → cible tvOS  (Apple TV)
#   - MobileVLCKit.xcframework  → cible iOS   (iPhone / iPad)
#
# Les binaires (~560 Mo chacun) ne sont PAS versionnés ; lance ce script après
# un clone (ou en CI), puis `xcodegen generate`.
#
# Source : binaires officiels VideoLAN (contiennent les tranches simulateur).
set -euo pipefail

VERSION="3.7.3-319ed2c0-79128878"
BASE_URL="https://download.videolan.org/cocoapods/prod"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Vendor"
mkdir -p "$DEST"

fetch() {
  local kit="$1"                       # TVVLCKit | MobileVLCKit
  local framework="$kit.xcframework"
  if [ -d "$DEST/$framework" ]; then
    echo "✓ $framework déjà présent — ignoré."
    return
  fi
  local tmp; tmp="$(mktemp -d)"
  echo "→ Téléchargement $kit $VERSION…"
  curl -L --fail -o "$tmp/kit.tar.xz" "$BASE_URL/$kit-$VERSION.tar.xz"
  echo "→ Extraction $kit…"
  tar -xJf "$tmp/kit.tar.xz" -C "$tmp"
  local src; src="$(find "$tmp" -maxdepth 3 -name "$framework" -type d | head -1)"
  [ -n "$src" ] || { echo "✗ $framework introuvable dans l'archive"; exit 1; }
  rm -rf "$DEST/$framework"
  cp -R "$src" "$DEST/"
  rm -rf "$tmp"
  echo "✅ Vendor/$framework installé."
}

fetch "TVVLCKit"
fetch "MobileVLCKit"

echo ""
echo "Lance maintenant : xcodegen generate"
