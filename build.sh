#!/bin/bash
# Builds build/Pomodoro.app, a universal (Apple Silicon + Intel) app; tests run first.
#   ./build.sh            build only
#   ./build.sh install    also copy to ~/Applications and launch
#   VERSION=1.2.0 ./build.sh   stamp a version (the release workflow passes the tag)
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Pomodoro.app
VERSION="${VERSION:-0.0.0}"

rm -rf build
mkdir -p "$APP/Contents/MacOS"

swiftc -O -parse-as-library -target "$(uname -m)-apple-macos13" Core.swift Tests.swift -o build/tests
build/tests

for arch in arm64 x86_64; do
    swiftc -O -parse-as-library -target "$arch-apple-macos13" Core.swift App.swift -o "build/Pomodoro-$arch"
done
lipo -create build/Pomodoro-arm64 build/Pomodoro-x86_64 -output "$APP/Contents/MacOS/Pomodoro"
rm build/Pomodoro-arm64 build/Pomodoro-x86_64

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>Pomodoro</string>
	<key>CFBundleIdentifier</key><string>local.pomodoro</string>
	<key>CFBundleName</key><string>Pomodoro</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>$VERSION</string>
	<key>CFBundleVersion</key><string>$VERSION</string>
	<key>LSMinimumSystemVersion</key><string>13.0</string>
	<key>LSUIElement</key><true/>
	<key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF
codesign --force --sign - "$APP"
echo "Built $APP $VERSION ($(du -sh "$APP" | cut -f1))"

if [[ "${1:-}" == install ]]; then
    pkill -x Pomodoro || true
    mkdir -p ~/Applications
    rm -rf ~/Applications/Pomodoro.app
    cp -R "$APP" ~/Applications/
    open ~/Applications/Pomodoro.app
    echo "Installed ~/Applications/Pomodoro.app"
fi
