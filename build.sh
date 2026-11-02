#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")" && pwd)"
stage="$(mktemp -d "${TMPDIR:-/tmp}/desk-income-build.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app_bundle="$stage/今日收入.app"
mkdir -p "$project_root/build"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
swiftc -swift-version 5 -O -parse-as-library -target arm64-apple-macos14.0 \
  "$project_root/Sources/IncomeModel.swift" "$project_root/Sources/StatusAmountAnimator.swift" "$project_root/Sources/Views.swift" "$project_root/Sources/MenuBarViews.swift" "$project_root/Sources/DesktopApp.swift" \
  -framework AppKit -framework SwiftUI -framework ServiceManagement \
  -o "$app_bundle/Contents/MacOS/DeskIncome"
cat > "$app_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>DeskIncome</string>
  <key>CFBundleIdentifier</key><string>local.deskincome.card</string>
  <key>CFBundleName</key><string>今日收入</string>
  <key>CFBundleDisplayName</key><string>今日收入</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.8.1</string>
  <key>CFBundleVersion</key><string>13</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
# Finder metadata can be added by the Documents file provider; remove only that metadata.
if xattr -p com.apple.FinderInfo "$app_bundle" >/dev/null 2>&1; then
  xattr -d com.apple.FinderInfo "$app_bundle"
fi
codesign --force --sign - --options runtime "$app_bundle"
codesign --verify --deep --strict "$app_bundle"
# Package outside the Documents file provider so it cannot inject FinderInfo during signing.
ditto --norsrc --noextattr -c -k --keepParent "$app_bundle" "$project_root/build/今日收入-mac-arm64.zip"
ditto --norsrc --noextattr "$app_bundle" "$project_root/build/今日收入.app"
printf 'Built archive: %s\n' "$project_root/build/今日收入-mac-arm64.zip"
