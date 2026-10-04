#!/bin/bash
# Runs the unit tests, then the UI tests of the iPhone and iPad app on the sample data, on one iPhone and one
# iPad simulator (created on first use). Screenshots of every step end up in build/test-results.
#   Tools/test-ios.sh            both devices
#   Tools/test-ios.sh iphone     only the iPhone
set -euo pipefail
cd "$(dirname "$0")/.."

runtime=$(xcrun simctl list runtimes | awk '/^iOS 27/ { id = $NF } END { print id }')
if [ -z "$runtime" ]; then
  echo "No iOS 27 simulator runtime. Install it in Xcode › Settings › Components." >&2
  exit 1
fi

simulator() {
  local name=$1 type=$2
  local id
  id=$(xcrun simctl list devices | awk -v name="$name" -F '[()]' '$0 ~ "    " name " \\(" { print $2; exit }')
  if [ -z "$id" ]; then id=$(xcrun simctl create "$name" "$type" "$runtime"); fi
  echo "$id"
}

echo "Unit tests…"
(cd Packages/GitIssuesKit && swift test --quiet)

mkdir -p build/test-results

# A fresh simulator shows a tip over the keyboard the first time it appears, which would cover the keys.
prepare() {
  xcrun simctl boot "$1" 2>/dev/null || true
  xcrun simctl bootstatus "$1" -b >/dev/null
  xcrun simctl spawn "$1" defaults write com.apple.keyboard.preferences DidShowContinuousPathIntroduction -bool true
}

run() {
  local label=$1 id=$2
  echo "UI tests on $label…"
  prepare "$id"
  rm -rf "build/test-results/$label.xcresult"
  xcodebuild test -project GitIssues.xcodeproj -scheme GitIssuesUITests \
    -destination "platform=iOS Simulator,id=$id" -derivedDataPath build/DerivedData -collect-test-diagnostics never \
    -resultBundlePath "build/test-results/$label.xcresult" -quiet
}

case "${1:-all}" in
  iphone) run iPhone "$(simulator 'Git Issues iPhone' 'iPhone 17 Pro')" ;;
  ipad) run iPad "$(simulator 'Git Issues iPad' 'iPad Pro 13-inch (M5)')" ;;
  *)
    run iPhone "$(simulator 'Git Issues iPhone' 'iPhone 17 Pro')"
    run iPad "$(simulator 'Git Issues iPad' 'iPad Pro 13-inch (M5)')"
    ;;
esac
echo "All tests passed. Results and screenshots: build/test-results"
