#!/bin/sh
# Build "WA Desk.app" dengan swiftc (Command Line Tools), lalu jalankan selftest.
set -eu
cd "$(dirname "$0")"
APP="WA Desk.app"
TARGET="$(uname -m)-apple-macos14.0"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -target "$TARGET" *.swift -o "$APP/Contents/MacOS/wa-desk" \
  -framework Cocoa -framework WebKit -framework UserNotifications \
  -framework Carbon -framework JavaScriptCore

# Icon: digambar icon/make-icon.swift → iconset → icns (sips & iconutil bawaan macOS).
ICON_TMP=$(mktemp -d)
swiftc -O -target "$TARGET" icon/make-icon.swift -o "$ICON_TMP/make-icon" -framework AppKit
"$ICON_TMP/make-icon" "$ICON_TMP/icon-1024.png"
mkdir -p "$ICON_TMP/AppIcon.iconset"
for s in 16 32 128 256 512; do
  sips -z "$s" "$s" "$ICON_TMP/icon-1024.png" --out "$ICON_TMP/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z "$((s * 2))" "$((s * 2))" "$ICON_TMP/icon-1024.png" --out "$ICON_TMP/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICON_TMP/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICON_TMP"

cp Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
# Ad-hoc sign: TCC (kamera/mic) dan UNUserNotificationCenter butuh identitas bundle stabil.
codesign --force --sign - "$APP"
"$APP/Contents/MacOS/wa-desk" --selftest
echo "built $APP"
