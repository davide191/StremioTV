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
  echo "→ Téléchargement $kit ${VERSION}…"
  curl -L --fail -o "$tmp/kit.tar.xz" "$BASE_URL/$kit-$VERSION.tar.xz"
  echo "→ Extraction ${kit}…"
  tar -xJf "$tmp/kit.tar.xz" -C "$tmp"
  local src; src="$(find "$tmp" -maxdepth 3 -name "$framework" -type d | head -1)"
  [ -n "$src" ] || { echo "✗ $framework introuvable dans l'archive"; exit 1; }
  rm -rf "$DEST/$framework"
  cp -R "$src" "$DEST/"
  rm -rf "$tmp"
  echo "✅ Vendor/$framework installé."
}

# Les binaires VideoLAN embarquent des tranches 32 bits (armv7/armv7s) dans la
# slice device de MobileVLCKit. Une app arm64 (iOS 17+) qui les embarque fait
# échouer l'empaquetage App Store avec un « Copy failed » opaque à l'export.
# On amincit donc le binaire device en arm64 uniquement (idempotent).
strip_legacy_archs() {
  local fw="$DEST/MobileVLCKit.xcframework/ios-arm64_armv7_armv7s/MobileVLCKit.framework"
  local bin="$fw/MobileVLCKit"
  [ -f "$bin" ] || return 0
  if lipo -archs "$bin" 2>/dev/null | tr ' ' '\n' | grep -qx armv7; then
    echo "→ Amincissement MobileVLCKit (device) → arm64…"
    lipo "$bin" -thin arm64 -output "$bin.tmp" && mv "$bin.tmp" "$bin"
    rm -rf "$fw/_CodeSignature"   # signature obsolète : Xcode re-signe à l'embed
    echo "✅ MobileVLCKit device = arm64 ($(lipo -archs "$bin"))."
  else
    echo "✓ MobileVLCKit device déjà arm64 uniquement."
  fi
}

fetch "TVVLCKit"
fetch "MobileVLCKit"
strip_legacy_archs

echo ""
echo "Lance maintenant : xcodegen generate"
