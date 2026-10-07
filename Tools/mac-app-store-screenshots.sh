#!/bin/bash
# Takes the Mac App Store screenshots from the sample data, 2880 x 1800, into Design/screenshots/app-store/mac.
#   Tools/mac-app-store-screenshots.sh
# Builds a debug copy with its own bundle identifier, so it shares no settings with an Issues you have running,
# opens it in the background, drives it through the debug remote and frames each window with Tools/store-frame.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

out=Design/screenshots/app-store/mac
app=$PWD/build/mac-screenshots/Build/Products/Debug/Issues.app
work=$(mktemp -d)
commands=$work/commands
pid=
bundle_id=com.lukaskbl.GitIssues.screenshots
finish() {
  [ -n "$pid" ] && kill "$pid" 2>/dev/null && sleep 0.5
  defaults delete "$bundle_id" 2>/dev/null || true
  rm -rf "$work" "${HOME:?}/Library/Application Support/${bundle_id:?}"
}
trap finish EXIT

echo "Building…"
xcodebuild build -project GitIssues.xcodeproj -scheme GitIssues -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/mac-screenshots \
  PRODUCT_BUNDLE_IDENTIFIER="$bundle_id" DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual GI_MAC_ENTITLEMENTS= -quiet

: > "$commands"
open -g -n "$app" --args -demo.active YES -screenshotMode YES -appearance light \
  -AppleLanguages '(en)' -AppleLocale en_US -debugCommandFile "$commands"
for _ in $(seq 100); do
  pid=$(pgrep -if "$app/Contents/MacOS/Issues" || true)
  [ -n "$pid" ] && break
  sleep 0.1
done
[ -n "$pid" ] || { echo "The app didn't start." >&2; exit 1; }

send() { printf '%s\n' "$@" >> "$commands"; }
# The remote skips lines written before it started, so knock until it answers.
for _ in $(seq 60); do
  send dump
  sleep 0.5
  [ -s "$commands.log" ] && break
done
[ -s "$commands.log" ] || { echo "The debug remote didn't answer." >&2; exit 1; }

# shot <name> <appearance> <width> <height> <command>…: sets the scene up, lets it settle and takes the window.
shot() {
  local name=$1 appearance=$2 width=$3 height=$4
  shift 4
  send "overlay none" "appearance $appearance" "window $width $height" "select Git Issues" "mode board"
  sleep 1
  for command in "$@"; do send "$command"; sleep 0.6; done
  sleep 1.2
  send "snapshot $work/$name.png"
  for _ in $(seq 50); do [ -s "$work/$name.png" ] && break; sleep 0.1; done
  sleep 0.3
  [ -s "$work/$name.png" ] || { echo "No snapshot of $name." >&2; exit 1; }
  mkdir -p "$out"
  swift Tools/store-frame.swift "$work/$name.png" "$out/$name.png" "$appearance"
  echo "$out/$name.png"
}

echo "Taking screenshots…"
shot 1-board light 1282 680
shot 2-issue dark 1282 760 "open 9"
shot 3-list light 1282 760 "mode list" "scrolllist 0"
shot 4-palette dark 1282 760 "focus 9" "overlay palette"
shot 5-selection light 1282 760 "mode list" "scrolllist 0" "pick 7 8 15"
shot 6-peek dark 1282 760 "mode list" "scrolllist 0" "peek 16"
shot 7-inbox light 1282 760 "select inbox" "entry 25"
