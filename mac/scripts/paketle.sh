#!/bin/bash
# Nabız.app paketini üretir: scripts/paketle.sh [--ac]  -> ~/Applications/Nabız.app
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Nabız"
EXEC_NAME="Nabiz"
BUNDLE_ID="com.nabiz.mac"
OPEN=0
for a in "$@"; do
  case "$a" in
    --ac) OPEN=1 ;;
    *) echo "Bilinmeyen secenek: $a" >&2; exit 2 ;;
  esac
done
PLIST_SRC="Sources/Nabiz/Info.plist"

swift build -c release

APP="$HOME/Applications/$APP_NAME.app"
mkdir -p "$HOME/Applications"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/$EXEC_NAME" "$APP/Contents/MacOS/$EXEC_NAME"
cp "$PLIST_SRC" "$APP/Contents/Info.plist"
# Ikon varsa ekle, yoksa atla.
if [ -f assets/AppIcon.icns ]; then
  cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || true
fi
# Ad-hoc imza (notarize degil)
codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP"

pkill -x "$EXEC_NAME" 2>/dev/null || true
echo "Hazir: $APP"
if [ "$OPEN" = 1 ]; then open "$APP"; fi
