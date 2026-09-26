#!/bin/sh
set -e
cd "$(dirname "$0")"

APP=熱モニター
mkdir -p build

CFLAGS="-O -fobjc-arc -target arm64-apple-macos14.0"
SWIFT="swiftc -O -target arm64-apple-macos14.0 -import-objc-header Sources/Bridging.h -framework Foundation -framework IOKit"

clang $CFLAGS -c Sources/sensors.m -o build/sensors.o

if [ "$1" = "--selftest" ]; then
  $SWIFT Sources/Sensors.swift Selftest/main.swift build/sensors.o -o build/selftest
  exec ./build/selftest
fi

$SWIFT Sources/App.swift Sources/Monitor.swift Sources/Sensors.swift build/sensors.o -o "build/$APP"

rm -rf "build/$APP.app"
mkdir -p "build/$APP.app/Contents/MacOS" "build/$APP.app/Contents/Resources"
cp "build/$APP" "build/$APP.app/Contents/MacOS/$APP"

# macmon を同梱（他人のMacで brew 不要にするため）。見つからなければ警告して続行。
MACMON="$(command -v macmon || true)"
if [ -z "$MACMON" ] && [ -x /opt/homebrew/bin/macmon ]; then
  MACMON=/opt/homebrew/bin/macmon
fi
if [ -n "$MACMON" ]; then
  cp -L "$MACMON" "build/$APP.app/Contents/Resources/macmon"
  MACMON_PREFIX="$(brew --prefix macmon 2>/dev/null || true)"
  if [ -n "$MACMON_PREFIX" ] && [ -f "$MACMON_PREFIX/LICENSE" ]; then
    cp "$MACMON_PREFIX/LICENSE" "build/$APP.app/Contents/Resources/macmon-LICENSE"
  fi
  codesign --force -s - "build/$APP.app/Contents/Resources/macmon" >/dev/null
else
  echo "warning: macmon が見つかりません。同梱なしでビルドします" >&2
fi

cat > "build/$APP.app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>ja</string>
	<key>CFBundleExecutable</key>
	<string>熱モニター</string>
	<key>CFBundleIdentifier</key>
	<string>com.tamacoin.thermal-bar</string>
	<key>CFBundleName</key>
	<string>熱モニター</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION:-1.0}</string>
	<key>CFBundleVersion</key>
	<string>${BUILD_NUMBER:-1}</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
</dict>
</plist>
EOF

codesign --force -s - "build/$APP.app" >/dev/null

if [ "$1" = "--release" ]; then
  # 開くと「アプリケーション」へドラッグするだけの標準的な dmg を作る
  rm -rf build/dmg build/ThermalBar.dmg
  mkdir -p build/dmg
  cp -R "build/$APP.app" build/dmg/
  ln -s /Applications build/dmg/Applications
  hdiutil create -volname "$APP" -srcfolder build/dmg -format UDZO -ov build/ThermalBar.dmg >/dev/null
  echo "built: build/ThermalBar.dmg"
else
  rm -rf "$HOME/Applications/$APP.app"
  cp -R "build/$APP.app" "$HOME/Applications/$APP.app"
  echo "built: $HOME/Applications/$APP.app"
fi
