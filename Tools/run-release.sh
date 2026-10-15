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
pids=$(swift - "$bundle_id" <<'SWIFT' 2>/dev/null || true
import AppKit
for app in NSRunningApplication.runningApplications(withBundleIdentifier: CommandLine.arguments[1]) {
  app.terminate()
  print(app.processIdentifier)
}
SWIFT
)

# Opening the app while the old copy is still quitting (say, finishing a sync) only brings that copy to the front, and
# then nothing is left running. So wait for its process to end; NSRunningApplication.isTerminated would never change
# without a run loop.
still_running() {
  local pid
  for pid in $pids; do kill -0 "$pid" 2>/dev/null && return 0; done
  return 1
}
SECONDS=0
said_waiting=
while still_running; do
  if (( SECONDS >= 60 )); then
    echo "The running copy still hasn't quit after a minute, so the new one wasn't opened. Quit it, then: open $app" >&2
    exit 1
  fi
  if (( SECONDS >= 3 )) && [[ -z $said_waiting ]]; then
    echo "Waiting for the running copy to quit…"
    said_waiting=1
  fi
  sleep 0.2
done

open -n "$app"

# Make sure the new copy is the one running.
executable="$(pwd -P)/$app/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist")"
SECONDS=0
until ps -axo comm= | grep -xF -- "$executable" >/dev/null; do
  if (( SECONDS >= 15 )); then
    echo "Opened $app, but it isn't running. Open it by hand: open $app" >&2
    exit 1
  fi
  sleep 0.2
done
echo "Opened $app"
