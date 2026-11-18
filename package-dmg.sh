#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"

./build.sh

app_path="$PWD/.build/PPSKSwitcher.app"
app_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")
dmg_path="$PWD/.build/PPSKSwitcher-$app_version.dmg"
staging_dir=$(mktemp -d "$PWD/.build/dmg-staging.XXXXXX")
trap 'rm -rf "$staging_dir"' EXIT

ditto "$app_path" "$staging_dir/PPSKSwitcher.app"
ln -s /Applications "$staging_dir/Applications"
cat > "$staging_dir/Install.txt" <<'EOF'
Drag PPSKSwitcher.app to Applications, then open it from Applications.

If macOS cannot verify the developer, open System Settings > Privacy & Security
and choose Open Anyway for PPSKSwitcher, only if you trust this copy.

This build is ad-hoc signed and is not notarized by Apple.
EOF

hdiutil create -volname "PPSK Switcher" -srcfolder "$staging_dir" \
  -format UDZO -ov "$dmg_path"
hdiutil verify "$dmg_path"
print "DMG: $dmg_path"
