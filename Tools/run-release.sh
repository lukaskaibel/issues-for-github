#!/bin/bash
# Builds an optimised copy of the app, quits the copy that is running, and opens the new one.
#   Tools/run-release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

app=build/DerivedData/Build/Products/Release/Issues.app
bundle_id=$(xcodebuild -project GitIssues.xcodeproj -scheme GitIssues -configuration Release -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ PRODUCT_BUNDLE_IDENTIFIER = / { print $2; exit }')

echo "Building…"
if ! xcodebuild -project GitIssues.xcodeproj -scheme GitIssues -configuration Release \
     -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -allowProvisioningUpdates build -quiet; then
  echo "Build failed; the running app was left alone." >&2
  exit 1
fi

# Ask the running copy to quit the normal way, so it finishes what it is doing.
swift - "$bundle_id" <<'SWIFT' 2>/dev/null || true
import AppKit
let apps = NSRunningApplication.runningApplications(withBundleIdentifier: CommandLine.arguments[1])
apps.forEach { $0.terminate() }
let deadline = Date().addingTimeInterval(5)
while apps.contains(where: { !$0.isTerminated }) && Date() < deadline { usleep(100_000) }
SWIFT

open "$app"
echo "Opened $app"
