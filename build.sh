#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"

# Respect an explicit override; otherwise use the selected full Xcode or find
# an installed copy. /usr/bin/xcodebuild also exists with only Command Line Tools.
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  selected_developer_dir="$(xcode-select -p 2>/dev/null || true)"
  if [[ -x "$selected_developer_dir/usr/bin/xcodebuild" ]]; then
    export DEVELOPER_DIR="$selected_developer_dir"
  else
    xcode_candidates=(/Applications/Xcode*.app/Contents/Developer(N))
    best_xcode_version=0
    autoload -Uz is-at-least
    for xcode_developer_dir in "${xcode_candidates[@]}"; do
      [[ -x "$xcode_developer_dir/usr/bin/xcodebuild" ]] || continue
      xcode_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
        "$xcode_developer_dir/../Info.plist" 2>/dev/null) || continue
      if is-at-least "$best_xcode_version" "$xcode_version"; then
        best_xcode_version="$xcode_version"
        export DEVELOPER_DIR="$xcode_developer_dir"
      fi
    done
  fi
fi
if [[ ! -x "${DEVELOPER_DIR:-}/usr/bin/xcodebuild" ]]; then
  print -u2 "Full Xcode is required. Install it, then set DEVELOPER_DIR to its Contents/Developer folder."
  exit 1
fi
print "Using Xcode: $DEVELOPER_DIR"
"$DEVELOPER_DIR/usr/bin/xcodebuild" \
  -project PPSKSwitcher.xcodeproj \
  -scheme PPSKSwitcher \
  -configuration Release \
  -derivedDataPath "$PWD/.build/DerivedData" \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY="-" \
  build
mkdir -p .build
rm -rf ".build/PPSKSwitcher.app.tmp"
cp -R ".build/DerivedData/Build/Products/Release/PPSKSwitcher.app" ".build/PPSKSwitcher.app.tmp"
rm -rf ".build/PPSKSwitcher.app"
mv ".build/PPSKSwitcher.app.tmp" ".build/PPSKSwitcher.app"
echo "Built: $PWD/.build/PPSKSwitcher.app"
echo "Launch: open '$PWD/.build/PPSKSwitcher.app'"
