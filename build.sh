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

mkdir -p "build/$APP.app/Contents/MacOS"
cp "build/$APP" "build/$APP.app/Contents/MacOS/$APP"
cat > "build/$APP.app/Contents/Info.plist" <<'EOF'
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
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
</dict>
</plist>
EOF

codesign --force -s - "build/$APP.app" >/dev/null
rm -rf "$HOME/Applications/$APP.app"
cp -R "build/$APP.app" "$HOME/Applications/$APP.app"
echo "built: $HOME/Applications/$APP.app"
