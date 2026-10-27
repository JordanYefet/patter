#!/bin/zsh
# Build "Patter.app" from the Swift package.
#
#   ./scripts/bundle.sh             build into ./build/Patter.app
#   ./scripts/bundle.sh --install   also copy it to ~/Applications and open it
#
# The app is ad-hoc signed (no Apple Developer account needed). A bundle is
# required for notifications and "Launch at login"; `swift run Patter` works
# for development but without those two.

set -euo pipefail

repo="${0:A:h:h}"
cd "$repo"

version="$(git describe --tags --always 2>/dev/null || print 0.1.0)"
version="${version#v}"

swift build -c release --product Patter
bin="$(swift build -c release --show-bin-path)/Patter"

app="$repo/build/Patter.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/Patter"

# The icon is drawn by code, so there's no binary asset to keep in sync.
if [[ -f "$repo/scripts/make-icon.swift" ]]; then
  swift "$repo/scripts/make-icon.swift" "$app/Contents/Resources/AppIcon.icns"
else
  print -u2 "bundle: scripts/make-icon.swift not found, building without an app icon"
fi

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Patter</string>
  <key>CFBundleDisplayName</key><string>Patter</string>
  <key>CFBundleIdentifier</key><string>io.github.patter</string>
  <key>CFBundleExecutable</key><string>Patter</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
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
  # old binary keeps running. CCPulse is the app's name before the rename.
  for proc in Patter CCPulse; do
    if pkill -x "$proc"; then
      while pgrep -x "$proc" >/dev/null; do sleep 0.1; done
    fi
  done
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/CC Pulse.app" "$HOME/Applications/Patter.app"
  cp -R "$app" "$HOME/Applications/"
  open "$HOME/Applications/Patter.app"
  print "Installed to ~/Applications/Patter.app"
fi
