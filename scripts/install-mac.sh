#!/bin/bash
# Nabız macOS kurulumu: son sürümü GitHub'dan indirir, /Applications'a koyar, açar.
# Kullanım: curl -fsSL https://raw.githubusercontent.com/serdarabdulkadir/nabiz/main/scripts/install-mac.sh | bash
set -euo pipefail
REPO="serdarabdulkadir/nabiz"
APP="Nabız.app"
DEST="/Applications"
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"

echo "→ Son sürüm aranıyor…"
URL=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
  | grep -o '"browser_download_url": *"[^"]*Nabiz-mac\.zip"' | head -1 | sed 's/.*"\(https[^"]*\)"/\1/')
[ -n "$URL" ] || { echo "İndirme bağlantısı bulunamadı: https://github.com/$REPO/releases" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
echo "→ İndiriliyor: $URL"
curl -fsSL "$URL" -o "$TMP/Nabiz-mac.zip"
ditto -x -k "$TMP/Nabiz-mac.zip" "$TMP"

pkill -x Nabiz 2>/dev/null || true
rm -rf "${DEST:?}/$APP"
ditto "$TMP/$APP" "$DEST/$APP"
# Uygulama notarize edilmedi (ad-hoc imzalı): karantina işaretini kaldır ki Gatekeeper engellemesin.
xattr -dr com.apple.quarantine "$DEST/$APP" 2>/dev/null || true

echo "✓ Kuruldu: $DEST/$APP"
open "$DEST/$APP"
