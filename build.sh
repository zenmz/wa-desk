#!/bin/sh
# Build WA.app dengan swiftc (Command Line Tools), lalu jalankan selftest.
set -eu
cd "$(dirname "$0")"
APP=WA.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O main.swift -o "$APP/Contents/MacOS/WA" \
  -framework Cocoa -framework WebKit -framework UserNotifications
cp Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
# Ad-hoc sign: TCC (kamera/mic) dan UNUserNotificationCenter butuh identitas bundle stabil.
codesign --force --sign - "$APP"
"$APP/Contents/MacOS/WA" --selftest
echo "built $APP"
