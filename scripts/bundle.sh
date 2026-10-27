#!/bin/zsh
# Build "CC Pulse.app" from the Swift package.
#
#   ./scripts/bundle.sh             build into ./build/CC Pulse.app
#   ./scripts/bundle.sh --install   also copy it to ~/Applications and open it
#
# The app is ad-hoc signed (no Apple Developer account needed). A bundle is
# required for notifications and "Launch at login"; `swift run CCPulse` works
# for development but without those two.

set -euo pipefail

repo="${0:A:h:h}"
cd "$repo"

version="$(git describe --tags --always 2>/dev/null || print 0.1.0)"
version="${version#v}"

swift build -c release --product CCPulse
bin="$(swift build -c release --show-bin-path)/CCPulse"

app="$repo/build/CC Pulse.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/CCPulse"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>CC Pulse</string>
  <key>CFBundleDisplayName</key><string>CC Pulse</string>
  <key>CFBundleIdentifier</key><string>io.github.cc-pulse</string>
  <key>CFBundleExecutable</key><string>CCPulse</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${version}</string>
  <key>CFBundleVersion</key><string>${version}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$app"
print "Built: $app"

if [[ "${1:-}" == "--install" ]]; then
  # `open` only activates an already-running copy, so quit it first or the
  # old binary keeps running.
  if pkill -x CCPulse; then
    while pgrep -x CCPulse >/dev/null; do sleep 0.1; done
  fi
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/CC Pulse.app"
  cp -R "$app" "$HOME/Applications/"
  open "$HOME/Applications/CC Pulse.app"
  print "Installed to ~/Applications/CC Pulse.app"
fi
