#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
if ! command -v xcodebuild >/dev/null 2>&1; then
  print -u2 "Xcode and its command line tools are required on macOS."
  exit 1
fi
xcodebuild \
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
