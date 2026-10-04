#!/bin/bash
# Takes the App Store screenshots on the sample data: a 6.9-inch iPhone and a 13-inch iPad, light and dark, with a
# clean status bar. The images end up in Design/screenshots/app-store/{iphone,ipad}.
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

out=Design/screenshots/app-store
results=build/screenshots
mkdir -p "$results"

shoot() {
  local label=$1 id=$2 folder=$3
  echo "Screenshots on $label…"
  xcrun simctl boot "$id" 2>/dev/null || true
  xcrun simctl bootstatus "$id" -b >/dev/null
  # A fresh simulator shows a tip over the keyboard the first time it appears.
  xcrun simctl spawn "$id" defaults write com.apple.keyboard.preferences DidShowContinuousPathIntroduction -bool true
  xcrun simctl status_bar "$id" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState discharging --batteryLevel 100
  rm -rf "$results/$label.xcresult" "$results/$label"
  TEST_RUNNER_GI_SCREENSHOTS=1 xcodebuild test -project GitIssues.xcodeproj -scheme GitIssuesUITests \
    -destination "platform=iOS Simulator,id=$id" -derivedDataPath build/DerivedData -collect-test-diagnostics never \
    -only-testing:GitIssuesUITests/ScreenshotTests -resultBundlePath "$results/$label.xcresult" -quiet
  xcrun xcresulttool export attachments --path "$results/$label.xcresult" --output-path "$results/$label" >/dev/null
  rm -rf "${out:?}/$folder"
  mkdir -p "$out/$folder"
  # Each attachment is named "AppStore-<name>"; keep those, under their name.
  python3 - "$results/$label" "$out/$folder" <<'PY'
import json, shutil, sys
source, target = sys.argv[1], sys.argv[2]
for test in json.load(open(f"{source}/manifest.json")):
    for attachment in test.get("attachments", []):
        name = attachment.get("suggestedHumanReadableName", "")
        if name.startswith("AppStore-"):
            clean = name[len("AppStore-"):].split("_")[0]
            shutil.copy(f"{source}/{attachment['exportedFileName']}", f"{target}/{clean}.png")
            print(f"  {target}/{clean}.png")
PY
  swift Tools/upright-png.swift "$out/$folder"/*.png
  xcrun simctl status_bar "$id" clear
}

shoot iPhone "$(simulator 'Git Issues iPhone 6.9' 'iPhone 17 Pro Max')" iphone
shoot iPad "$(simulator 'Git Issues iPad' 'iPad Pro 13-inch (M5)')" ipad
echo "Done: $out"
