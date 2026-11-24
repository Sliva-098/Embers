#!/bin/bash
# Собирает Embers.dmg с оформленным окном установки: ./Installer/make-dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."
APP="Embers.app"
[ -d "$APP" ] || ./build.sh
VOL="Embers"
OUT="Embers.dmg"
TMP="$(mktemp -d)/rw.dmg"
rm -f "$OUT"
hdiutil detach "/Volumes/$VOL" -force >/dev/null 2>&1 || true

hdiutil create -size 40m -fs HFS+ -volname "$VOL" -ov "$TMP" >/dev/null
hdiutil attach "$TMP" -mountpoint "/Volumes/$VOL" -nobrowse -noverify >/dev/null
cp -R "$APP" "/Volumes/$VOL/"
ln -s /Applications "/Volumes/$VOL/Applications"
mkdir "/Volumes/$VOL/.background"
cp Installer/background.png "/Volumes/$VOL/.background/background.png"
cp "$APP/Contents/Resources/AppIcon.icns" "/Volumes/$VOL/.VolumeIcon.icns"
SetFile -a C "/Volumes/$VOL" 2>/dev/null || true

# Оформление окна: размер, иконки, фон. Finder должен быть доступен для автоматизации.
osascript <<EOS
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 520}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 13
    set background picture of opts to file ".background:background.png"
    set position of item "$APP" of container window to {180, 225}
    set position of item "Applications" of container window to {480, 225}
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
EOS
sync
hdiutil detach "/Volumes/$VOL" >/dev/null
hdiutil convert "$TMP" -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null
rm -f "$TMP"
echo "OK: $(pwd)/$OUT ($(du -h "$OUT" | cut -f1))"
